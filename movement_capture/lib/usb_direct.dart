/// Hardware diagnostics for the direct-USB camera backend. Hosts do not need
/// this: `MovementCapture.open` picks the backend itself. The lab's USB test
/// page uses it to check a webcam on a real device.
library;

export 'src/data/usb_direct_camera_gateway.dart'
    show UsbDirectCameraGateway, usbTargetSize;
export 'src/domain/camera_gateway.dart'
    show CameraFrameSize, CameraGatewayException, CameraLost, CameraLostReason;
