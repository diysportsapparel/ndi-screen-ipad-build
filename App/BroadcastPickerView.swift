import ReplayKit
import SwiftUI

struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String
    let showsMicrophoneButton: Bool

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 64, height: 64)
        )
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = showsMicrophoneButton
        picker.tintColor = .white
        picker.backgroundColor = .clear

        if let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            let image = UIImage(
                systemName: "dot.radiowaves.left.and.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            )
            button.setImage(image, for: .normal)
            button.tintColor = .white
            button.backgroundColor = .clear
        }

        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = preferredExtension
        uiView.showsMicrophoneButton = showsMicrophoneButton
        uiView.tintColor = .white
    }
}

