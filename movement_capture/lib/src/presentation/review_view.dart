import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/capture_state.dart';
import '../domain/config.dart';
import 'controller.dart';
import 'customization.dart';

/// Full-screen playback of the clip just recorded, the overall quality
/// result, and Continue (or Use anyway) / Record again / Cancel.
class ReviewView extends StatefulWidget {
  const ReviewView({
    super.key,
    required this.controller,
    required this.review,
    required this.strings,
    required this.icons,
    required this.activeColor,
    required this.onCancel,
  });

  final MovementCaptureController controller;
  final Reviewing review;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final Color activeColor;
  final VoidCallback onCancel;

  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  late final VideoPlayerController _player =
      VideoPlayerController.file(widget.review.video);
  bool _ready = false;
  bool _failed = false;
  bool _busy = false; // a choice was made; ignore further taps

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.initialize();
      await _player.setLooping(true);
      await _player.setVolume(0);
      await _player.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('movement_capture: review playback failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _choose(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _player.pause();
    } catch (_) {} // the player may have failed; the choice still stands
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.strings;
    final c = widget.controller;
    final config = c.config;
    final mode = config.mode;
    final flip =
        config.reviewMirrorFor(widget.review.cameraKind, defaultTargetPlatform);
    final quality = widget.review.quality;
    final good = quality.passes;
    const tall = Size(0, 56);

    final video = _failed
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(s.reviewUnavailable,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: scheme.onInverseSurface)),
            ),
          )
        : !_ready
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Transform.flip(
                  flipX: flip,
                  child: AspectRatio(
                    aspectRatio: _player.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_player),
                      ],
                    ),
                  ),
                ),
              );

    final cancel = OutlinedButton(
      style: OutlinedButton.styleFrom(
          minimumSize: tall,
          foregroundColor: scheme.onInverseSurface,
          side: BorderSide(color: scheme.onInverseSurface)),
      onPressed: _busy ? null : widget.onCancel,
      child: Text(s.cancel),
    );
    final againLabel = Text(s.recordAgain);
    final again = good
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: tall,
                foregroundColor: scheme.onInverseSurface,
                side: BorderSide(color: scheme.onInverseSurface)),
            onPressed: _busy ? null : () => _choose(c.retakeStep),
            icon: Icon(widget.icons.recordAgain),
            label: againLabel,
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: tall),
            onPressed: _busy ? null : () => _choose(c.retakeStep),
            icon: Icon(widget.icons.recordAgain),
            label: againLabel,
          );
    // Passed: Continue is the obvious next step. Failed: Record again is,
    // and Use anyway is a quieter choice (hidden when config turns it off).
    final Widget? use = good
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: tall),
            onPressed: _busy ? null : () => _choose(c.acceptReview),
            icon: Icon(widget.icons.useVideo),
            label: Text(s.summaryContinue),
          )
        : config.allowUseAnyway
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: tall,
                    foregroundColor: scheme.onInverseSurface,
                    side: BorderSide(color: scheme.onInverseSurface)),
                onPressed: _busy ? null : () => _choose(c.acceptReview),
                icon: Icon(widget.icons.useVideo),
                label: Text(s.useAnyway),
              )
            : null;

    return ColoredBox(
      color: scheme.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        s.stepProgress(c.stepIndex, c.stepCount, c.currentStep),
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(s.reviewTitle,
                        style: mode == CaptureMode.selfGuided
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(s.reviewHintFor(mode),
                        style: theme.textTheme.titleMedium),
                    if (quality.measured) ...[
                      const SizedBox(height: 12),
                      Row(
                        key: const ValueKey('quality-result'),
                        children: [
                          Icon(
                              good
                                  ? widget.icons.statusGood
                                  : widget.icons.statusBad,
                              size: 32,
                              color: good ? widget.activeColor : scheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              good
                                  ? s.summaryGoodTitle
                                  : '${s.summaryRedoTitle}. ${s.summaryReason(quality)}',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: video),
            if (_ready) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _player,
                    builder: (context, v, _) => IconButton.filledTonal(
                      iconSize: 32,
                      constraints:
                          const BoxConstraints(minWidth: 56, minHeight: 56),
                      tooltip: v.isPlaying ? s.pause : s.play,
                      onPressed: () =>
                          v.isPlaying ? _player.pause() : _player.play(),
                      icon: Icon(
                          v.isPlaying ? widget.icons.pause : widget.icons.play),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: VideoProgressIndicator(
                        _player,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: widget.activeColor,
                          bufferedColor: scheme.outlineVariant,
                          backgroundColor: scheme.outline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    good ? use! : again,
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 12),
                      Expanded(child: good ? again : (use ?? const SizedBox())),
                    ]),
                  ],
                );
              }
              return Row(children: [
                SizedBox(width: 180, child: cancel),
                const Spacer(),
                if (!good && use != null) ...[
                  SizedBox(width: 240, child: use),
                  const SizedBox(width: 16),
                ],
                SizedBox(width: 280, child: good ? use! : again),
                if (good) ...[
                  const SizedBox(width: 16),
                  SizedBox(width: 240, child: again),
                ],
              ]);
            }),
          ],
        ),
      ),
    );
  }
}
