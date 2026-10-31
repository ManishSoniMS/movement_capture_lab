import '../domain/body_sides.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';
import '../domain/capture_step.dart';
import '../domain/config.dart';
import 'customization.dart';

/// What the planner needs to know about the screen right now.
class SpeechSnapshot {
  const SpeechSnapshot({
    required this.state,
    required this.step,
    required this.stepIndex,
    this.lastSaved,
    this.awaitingSideChoice = false,
    this.sideChoice = SideChoice.both,
    this.outOfFrameWarning = false,
  });
  final CaptureState state;
  final CaptureStep step;
  final int stepIndex;
  final CaptureStep? lastSaved;

  /// The hands / feet question is on screen.
  final bool awaitingSideChoice;
  final SideChoice sideChoice;

  /// "Come back into the frame" warning is active while recording.
  final bool outOfFrameWarning;
}

/// Decides what to say for each state change. Each event is spoken once;
/// only an unresolved problem repeats, every [issueRepeat].
///
/// The controller notifies several times a second, so every branch is keyed:
/// the same key twice in a row yields nothing.
class SpeechPlanner {
  SpeechPlanner({
    required this.strings,
    required this.mode,
    this.issueRepeat = const Duration(seconds: 6),
  });

  final MovementCaptureStrings strings;
  final CaptureMode mode;
  final Duration issueRepeat;

  String? _lastKey;
  CaptureIssue? _lastIssue;
  DateTime? _lastIssueAt;
  int _goodCount = 0;

  /// Text to speak now, or null.
  String? next(SpeechSnapshot s, DateTime now) {
    final state = s.state;
    switch (state) {
      case Initializing():
        return null;
      case Checking() when s.awaitingSideChoice:
        _clearIssue();
        return _once(
            'sides:${s.stepIndex}', () => strings.sideChoiceTitle(s.step));
      case Checking(issue: final issue?):
        final repeatDue = _lastIssue == issue &&
            _lastIssueAt != null &&
            now.difference(_lastIssueAt!) >= issueRepeat;
        if (_lastIssue == issue && !repeatDue) return null;
        _lastIssue = issue;
        _lastIssueAt = now;
        _lastKey = 'issue';
        return strings.issueFor(issue, mode);
      case Checking(armed: false):
        _clearIssue();
        return _once('intro:${s.stepIndex}:${s.sideChoice.name}', () {
          final instruction = s.step.hasSides && s.sideChoice != SideChoice.both
              ? strings.sideInstruction(s.step, s.sideChoice)
              : strings.stepInstructionFor(s.step, mode);
          return s.lastSaved == null
              ? instruction
              : '${strings.voiceStepDone} $instruction';
        });
      case Checking(armed: true):
        final cameFromIssue = _lastKey == 'issue';
        _clearIssue();
        if (cameFromIssue) {
          return _once(
              'good:${s.stepIndex}:${++_goodCount}', () => strings.voiceGood);
        }
        return _once('armed:${s.stepIndex}', () => strings.hintArmedFor(mode));
      case CountingDown(:final secondsLeft):
        _clearIssue();
        final first = !(_lastKey?.startsWith('count:${s.stepIndex}:') ?? false);
        return _once(
            'count:${s.stepIndex}:$secondsLeft',
            () =>
                first ? strings.voiceStartingIn(secondsLeft) : '$secondsLeft');
      case Recording() when s.outOfFrameWarning:
        // Repeats like an issue: once when it starts, then every issueRepeat
        // while the subject is still out of frame.
        final due = _lastKey != 'comeback' ||
            _lastIssueAt == null ||
            now.difference(_lastIssueAt!) >= issueRepeat;
        if (!due) return null;
        _lastIssueAt = now;
        _lastKey = 'comeback';
        return strings.voiceComeBack;
      case Recording(:final liveChecks):
        _clearIssue();
        return _once(
            'rec:${s.stepIndex}:$liveChecks',
            () => liveChecks
                ? strings.voiceRecording
                : strings.noLiveChecksNotice);
      case Reviewing():
        _clearIssue();
        return _once('review:${s.stepIndex}', () => strings.voiceReview);
      case NeedsOperator():
        _clearIssue();
        return _once(
            'help:${s.stepIndex}', () => strings.needsOperatorFor(mode));
      case CameraUnavailable(:final reason):
        _clearIssue();
        return _once(
            'camera:${reason.name}', () => strings.cameraFailure(reason));
      case Finishing():
        return _once('finishing', () => strings.voiceFinishing);
      case FinishFailed():
        return _once('failed', () => strings.uploadFailed);
      case SessionComplete():
        return _once('complete', () => strings.completed);
    }
  }

  String? _once(String key, String Function() text) {
    if (key == _lastKey) return null;
    _lastKey = key;
    return text();
  }

  void _clearIssue() {
    _lastIssue = null;
    _lastIssueAt = null;
  }
}
