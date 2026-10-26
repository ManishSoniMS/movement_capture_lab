import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:movement_capture/movement_capture.dart';

/// Lab voice: speaks through the device's text-to-speech engine.
/// The kiosk and consumer apps build their own the same way.
class TtsVoice implements MovementCaptureVoice {
  TtsVoice({this.language = 'en-IN', this.rate = 0.45});

  final String language;
  final double rate;
  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  Future<void> _init() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.duckOthers],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      final available = await _tts.isLanguageAvailable(language);
      if (available == true) {
        await _tts.setLanguage(language);
      } else {
        debugPrint('TtsVoice: $language not available; using the default voice');
      }
      await _tts.setSpeechRate(rate); // slower for elderly listeners
      await _tts.setVolume(1.0);
    } catch (e) {
      debugPrint('TtsVoice: init failed: $e');
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await (_ready ??= _init());
      await _tts.stop(); // interrupt the previous prompt
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TtsVoice: speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TtsVoice: stop failed: $e');
    }
  }
}
