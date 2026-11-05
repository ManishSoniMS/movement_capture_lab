# Third-party notices

`movement_capture` includes the following for the direct-USB camera backend (Android). Hosts should list them in their licence screen.

| Component | Licence | Notes |
|---|---|---|
| UVCCamera / `org.uvccamera:lib` 0.0.13 (Java wrapper + JNI) | Apache-2.0 | https://github.com/alexey-pelykh/uvccamera. `UsbDirectCamera.kt` adapts code from its Flutter plugin (`UvcCameraPlatform.java`), also Apache-2.0 |
| libuvc | BSD-3-Clause | linked into `libuvc.so` |
| libjpeg-turbo | IJG / BSD-style (BSD-3-Clause, zlib) | `libjpeg-turbo1500.so` |
| **libusb** | **LGPL-2.1** | `libusb100.so`, shipped as its **own shared library**, so an app can relink or replace it |

**LGPL note for legal review (MedPredict):** libusb is LGPL-2.1. It is dynamically linked as a separate `.so` and unmodified. Confirm that distribution through the kiosk MDM and the public stores meets the LGPL notice and relinking terms, and that the licence text is shown in the host's licence screen.
