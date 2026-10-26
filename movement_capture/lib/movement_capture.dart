/// Public API. Hosts import only this file.
library;

export 'package:camera/camera.dart'
    show CameraDescription, CameraLensDirection, ResolutionPreset;

export 'src/api.dart';
export 'src/domain/camera_choice.dart';
export 'src/domain/capture_step.dart';
export 'src/domain/result.dart';
export 'src/domain/support_report.dart'
    show
        SupportReport,
        SupportIssue,
        SupportIssueCode,
        SupportSeverity,
        SupportRequirements;
export 'src/domain/capture_issue.dart';
export 'src/domain/config.dart';
export 'src/domain/uploader.dart';
export 'src/domain/voice.dart';
export 'src/presentation/customization.dart';
export 'src/presentation/screen.dart' show MovementCaptureScreen;
