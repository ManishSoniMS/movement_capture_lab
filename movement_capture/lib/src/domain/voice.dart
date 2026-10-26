/// Text-to-speech, supplied by the host app (the package has no TTS
/// dependency). The host speaks the given text in the user's language; the
/// text is already translated (it comes from MovementCaptureStrings).
abstract interface class MovementCaptureVoice {
  /// Speaks [text] now, interrupting anything still being spoken.
  /// Must not throw.
  Future<void> speak(String text);

  /// Stops speaking. Must not throw.
  Future<void> stop();
}
