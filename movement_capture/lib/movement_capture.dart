/// Public API. Hosts import only this file.
library;

export 'package:camera/camera.dart'
    show CameraDescription, CameraLensDirection, ResolutionPreset;

export 'src/api.dart';
export 'src/domain/body_sides.dart' show BodySide, SideChoice, SideStatus;
export 'src/domain/camera_choice.dart';
export 'src/domain/capture_step.dart';
export 'src/domain/result.dart';
export 'src/domain/scan_selection.dart';
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
export 'src/presentation/scan_type_picker.dart' show ScanTypePicker;
export 'src/presentation/screen.dart' show MovementCaptureScreen;
