import AVFoundation
import CoreMedia
import Darwin
import Dispatch
import Foundation
import os.log
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let targetAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    private var settings = BroadcastSettings()
    private var sender: NDISenderBridge?
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let toneQueue = DispatchQueue(label: "com.example.ndiscreen.tone")
    private var toneTimer: DispatchSourceTimer?
    private var tonePhase: Double = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        stopTestTone()
        settings = BroadcastSettings.load()
        sender = nil
        audioConverter = nil
        converterInputFormat = nil

        os_log(
            "NDI Screen broadcast started: %{public}@, %d fps",
            settings.safeSourceName,
            settings.normalizedFrameRate
        )
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            if sender == nil {
                configureSender(from: sampleBuffer)
            }
            sender?.sendVideoSampleBuffer(sampleBuffer)

        case .audioApp:
            if settings.audioSource == .appAudio {
                sendAudio(sampleBuffer)
            }

        case .audioMic:
            if settings.audioSource == .microphone {
                sendAudio(sampleBuffer)
            }

        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        stopTestTone()
        sender?.stop()
        sender = nil
        audioConverter = nil
        converterInputFormat = nil
        os_log("NDI Screen broadcast finished")
    }

    private func configureSender(from sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(imageBuffer)
        let sourceHeight = CVPixelBufferGetHeight(imageBuffer)
        let outputSize = settings.resolution.dimensions(
            forSourceWidth: sourceWidth,
            height: sourceHeight
        )

        sender = NDISenderBridge(
            name: settings.safeSourceName,
            width: outputSize.width,
            height: outputSize.height,
            fps: settings.normalizedFrameRate
        )

        if sender == nil {
            os_log(
                "Failed to create NDI sender at %dx%d",
                type: .error,
                outputSize.width,
                outputSize.height
            )
        } else if settings.audioSource == .testTone {
            startTestTone()
        }
    }

    private func startTestTone() {
        guard toneTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: toneQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(20),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.emitTestToneFrame()
        }
        toneTimer = timer
        timer.resume()
        os_log("NDI test tone started")
    }

    private func stopTestTone() {
        toneTimer?.cancel()
        toneTimer = nil
        tonePhase = 0
    }

    private func emitTestToneFrame() {
        guard let sender else { return }
        let format = targetAudioFormat

        let frameCount: AVAudioFrameCount = 960
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return
        }
        buffer.frameLength = frameCount

        guard let channels = buffer.floatChannelData else { return }
        let channelCount = Int(format.channelCount)
        let phaseIncrement = 2.0 * Double.pi * 440.0 / format.sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(tonePhase)) * 0.12
            for channel in 0..<channelCount {
                channels[channel][frame] = sample
            }
            tonePhase += phaseIncrement
            if tonePhase >= 2.0 * Double.pi {
                tonePhase -= 2.0 * Double.pi
            }
        }

        sender.send(buffer, timestamp: .zero)
    }

    private func sendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let sender else { return }
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
            let inputFormat = AVAudioFormat(streamDescription: streamDescription)
        else {
            return
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        let channelCount = max(1, Int(inputFormat.channelCount))
        let bufferListSize = MemoryLayout<AudioBufferList>.size
            + (channelCount - 1) * MemoryLayout<AudioBuffer>.size
        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            os_log("Audio buffer list extraction failed: %d", type: .error, status)
            return
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            bufferListNoCopy: audioBufferList,
            deallocator: nil
        ) else {
            os_log("AVAudioPCMBuffer creation failed", type: .error)
            return
        }
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let outputBuffer: AVAudioPCMBuffer

        if formatsMatch(inputFormat, targetAudioFormat) {
            outputBuffer = inputBuffer
        } else {
            guard let convertedBuffer = convertAudio(
                inputBuffer: inputBuffer,
                inputFormat: inputFormat,
                timestamp: timestamp
            ) else {
                return
            }
            outputBuffer = convertedBuffer
        }

        sender.send(outputBuffer, timestamp: timestamp)
        withExtendedLifetime(blockBuffer) {}
    }

    private func convertAudio(
        inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        timestamp: CMTime
    ) -> AVAudioPCMBuffer? {
        if audioConverter == nil || converterInputFormat != inputFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetAudioFormat)
            audioConverter?.sampleRateConverterQuality = .max
            audioConverter?.primeMethod = .none
            converterInputFormat = inputFormat
        }

        guard let audioConverter else { return nil }

        let ratio = targetAudioFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * ratio)
        ) + 1_024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetAudioFormat,
            frameCapacity: capacity
        ) else {
            return nil
        }

        var error: NSError?
        var providedInput = false
        let conversionStatus = audioConverter.convert(
            to: outputBuffer,
            error: &error
        ) { _, outStatus in
            if providedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            providedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if conversionStatus == .error {
            os_log(
                "Audio conversion failed: %{public}@",
                type: .error,
                error?.localizedDescription ?? "unknown"
            )
            return nil
        }

        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.commonFormat == rhs.commonFormat &&
            lhs.isInterleaved == rhs.isInterleaved
    }
}

