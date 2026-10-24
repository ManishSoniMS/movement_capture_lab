# Local patches to camera_avfoundation

Upstream: https://github.com/flutter/packages/tree/main/packages/camera/camera_avfoundation
Base version: 0.10.3+1

1. getAvailableCameras also discovers `.external` devices on iPadOS 17+, so
   USB webcams appear with lensDirection = external. (CameraPlugin.swift)

When upgrading the `camera` package: re-vendor the new matching version and
re-apply patch 1. Remove this folder once upstream discovers external cameras.
