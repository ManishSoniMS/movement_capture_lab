import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice.dart';
import 'controller.dart';
import 'speech_planner.dart';

/// Connects the controller to the host's voice through the planner.
class VoiceGuide {
  VoiceGuide({
    required this.controller,
    required this.voice,
    required this.planner,
  }) {
    controller.addListener(_onChange);
  }

  final MovementCaptureController controller;
  final MovementCaptureVoice voice;
  final SpeechPlanner planner;
  bool _muted = false;
  bool _disposed = false;

  bool get muted => _muted;

  set muted(bool value) {
    _muted = value;
    if (value) unawaited(_safe(voice.stop));
  }

  void _onChange() {
    if (_disposed) return;
    final text = planner.next(
      SpeechSnapshot(
        state: controller.state,
        step: controller.currentStep,
        stepIndex: controller.stepIndex,
        lastSaved: controller.lastSavedStep,
        awaitingSideChoice: controller.awaitingSideChoice,
        sideChoice: controller.sideChoiceFor(controller.currentStep),
      ),
      DateTime.now(),
    );
    // The planner still tracks state while muted, so unmuting doesn't replay
    // old prompts.
    if (text == null || _muted) return;
    unawaited(_safe(() => voice.speak(text)));
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('movement_capture: voice failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_onChange);
    unawaited(_safe(voice.stop));
  }
}
