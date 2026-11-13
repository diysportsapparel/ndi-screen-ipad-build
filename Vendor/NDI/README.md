# NDI SDK for iOS

This project does not redistribute the NDI SDK. Download the iOS SDK from the
official NDI developer site, accept the SDK license, and place the files here:

```text
Vendor/NDI/
  include/
    Processing.NDI.Lib.h
    Processing.NDI.Send.h
    Processing.NDI.Recv.h
    ...
  lib/
    iOS/
      libndi_ios.a
```

The exact SDK layout can vary by NDI SDK version. If the static library is in a
different directory, update `LIBRARY_SEARCH_PATHS` in `project.yml`.

NDI is proprietary technology. The SDK is free to download for development, but
you must review and comply with the current NDI SDK license before distributing
an app or IPA.

