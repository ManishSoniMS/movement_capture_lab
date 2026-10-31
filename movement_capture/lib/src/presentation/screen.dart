import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/native_bridge.dart';
import '../domain/body_sides.dart';
import '../domain/camera_choice.dart';
import '../domain/capture_state.dart';
import '../domain/config.dart';
import '../domain/result.dart';
import '../domain/support_report.dart';
import '../domain/uploader.dart';
import '../domain/voice.dart';
import 'controller.dart';
import 'customization.dart';
import 'debug_overlay.dart';
import 'review_view.dart';
import 'side_choice_view.dart';
import 'quality_status_bar.dart';
import 'skeleton_layer.dart';
import 'speech_planner.dart';
import 'voice_guide.dart';

/// Pops with a [MovementCaptureResult]: completed when every recorded step was
/// uploaded, cancelled otherwise. Steps already uploaded keep their IDs.
class MovementCaptureScreen extends StatefulWidget {
  const MovementCaptureScreen({
    super.key,
    required this.config,
    required this.uploader,
    required this.support,
    this.strings = const MovementCaptureStrings(),
    this.icons = const MovementCaptureIcons(),
    this.style = const MovementCaptureStyle(),
    this.showDebugOverlay = false,
    this.onCameraChanged,
    this.voice,
  });

  final MovementCaptureConfig config;
  final MovementUploader uploader;
  final SupportReport support;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final MovementCaptureStyle style;
  final bool showDebugOverlay;
  final void Function(CameraDescription camera)? onCameraChanged;

  /// Speaks prompts when [MovementCaptureConfig.speaks]. Null = silent.
  final MovementCaptureVoice? voice;

  @override
  State<MovementCaptureScreen> createState() => _MovementCaptureScreenState();
}

class _MovementCaptureScreenState extends State<MovementCaptureScreen>
    with WidgetsBindingObserver {
  late final MovementCaptureController _controller;
  VoiceGuide? _voiceGuide;
  bool _closing = false;
  bool _confirming = false; // the quit dialog is open

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortestSide =
        (view.physicalSize / view.devicePixelRatio).shortestSide;
    SystemChrome.setPreferredOrientations(
        widget.config.orientationsFor(shortestSide));
    unawaited(NativeBridge.setKeepScreenOn(true));
    _controller = MovementCaptureController(
      config: widget.config,
      uploader: widget.uploader,
      onCameraChanged: widget.onCameraChanged,
      lowMemoryDevice: widget.support.has(SupportIssueCode.lowMemoryDevice),
    );
    final voice = widget.voice;
    if (voice != null && widget.config.speaks) {
      _voiceGuide = VoiceGuide(
        controller: _controller,
        voice: voice,
        planner: SpeechPlanner(
          strings: widget.strings,
          mode: widget.config.mode,
          issueRepeat: widget.config.voiceIssueRepeat,
        ),
      );
    } else if (widget.config.mode == CaptureMode.selfGuided) {
      debugPrint('movement_capture: self-guided mode without a voice. '
          'Users who stepped back cannot read the screen; pass `voice`.');
    }
    unawaited(_controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Really in the background: release the camera.
        unawaited(_controller.suspend());
      case AppLifecycleState.resumed:
        unawaited(_controller.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // `inactive` also fires for the camera permission prompt, Control
        // Center, the notification shade and call banners. Keep the camera.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(widget.config.restoreOrientations);
    unawaited(NativeBridge.setKeepScreenOn(false));
    _voiceGuide?.dispose();
    _controller.dispose(); // stops recording, cancels uploads, deletes files
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    final complete = _controller.state is SessionComplete;
    Navigator.of(context).pop(MovementCaptureResult(
      status: complete
          ? MovementCaptureStatus.completed
          : MovementCaptureStatus.cancelled,
      support: widget.support,
      steps: _controller.results,
    ));
  }

  /// Every "Cancel" and the back gesture come here.
  Future<void> _requestClose() async {
    if (_closing || _confirming) return;
    if (!_controller.hasUnsavedWork) {
      _close();
      return;
    }
    _confirming = true;
    final s = widget.strings;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.quitTitle),
        content:
            Text(s.quitMessage, style: Theme.of(context).textTheme.titleMedium),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(140, 56)),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.quitKeepGoing),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(140, 56)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.quitConfirm),
          ),
        ],
      ),
    );
    _confirming = false;
    if (stop == true && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    final ui = _Ui(
      strings: widget.strings,
      icons: widget.icons,
      error: style.errorColor ?? scheme.error,
      active: style.activeColor ?? scheme.primary,
      warning: style.warningColor ?? const Color(0xFFFFB300),
      skeleton: SkeletonColors(
        body: style.skeletonBodyColor ?? scheme.primary,
        hand: style.skeletonHandColor ?? scheme.secondary,
        foot: style.skeletonFootColor ?? scheme.inversePrimary,
      ),
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_requestClose()); // back gesture = Cancel, at any time
          },
          child: Scaffold(
            backgroundColor: scheme.scrim,
            body: SafeArea(
              child: _CaptureBody(
                controller: _controller,
                state: state,
                ui: ui,
                showDebug:
                    widget.showDebugOverlay && _controller.config.showDetails,
                onClose: () => unawaited(_requestClose()),
                onDone: _close,
                voiceGuide: _voiceGuide,
                onToggleMute: () => setState(() {
                  final g = _voiceGuide;
                  if (g != null) g.muted = !g.muted;
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Resolved customisation passed down the tree.
class _Ui {
  const _Ui({
    required this.strings,
    required this.icons,
    required this.error,
    required this.active,
    required this.warning,
    required this.skeleton,
  });
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final Color error;
  final Color active;
  final Color warning;
  final SkeletonColors skeleton;
}

Future<void> _showCameraSheet(
  BuildContext context,
  MovementCaptureController controller,
  _Ui ui,
) {
  unawaited(controller.refreshCameras()); // pick up newly plugged cameras
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final s = ui.strings;
        final selectedId = controller.selectedCamera?.id;
        final usb = controller.cameras.where((c) => c.isExternal).toList();
        final tablet = controller.cameras.where((c) => !c.isExternal).toList();

        Widget heading(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(text, style: theme.textTheme.titleMedium),
            );

        Widget tile(CameraChoice c) => ListTile(
              minTileHeight: 64,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(
                c.isExternal ? ui.icons.usbCamera : ui.icons.tabletCamera,
                size: 32,
              ),
              title: Text(s.cameraLabel(c), style: theme.textTheme.titleLarge),
              trailing: c.id == selectedId
                  ? Icon(ui.icons.selectedCamera, color: ui.active, size: 32)
                  : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(controller.selectCamera(c));
              },
            );

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(s.chooseCamera,
                      style: theme.textTheme.headlineSmall),
                ),
                heading(s.usbCamerasHeading),
                if (usb.isEmpty)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Icon(ui.icons.info, size: 28),
                    title: Text(s.noUsbCameraNotice,
                        style: theme.textTheme.bodyLarge),
                  )
                else
                  ...usb.map(tile),
                if (tablet.isNotEmpty) heading(s.tabletCamerasHeading),
                ...tablet.map(tile),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(160, 56)),
                      onPressed: controller.refreshCameras,
                      icon: Icon(ui.icons.refresh),
                      label: Text(s.refreshCameras),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _CaptureBody extends StatelessWidget {
  const _CaptureBody({
    required this.controller,
    required this.state,
    required this.ui,
    required this.showDebug,
    required this.onClose,
    required this.onDone,
    required this.voiceGuide,
    required this.onToggleMute,
  });

  final MovementCaptureController controller;
  final CaptureState state;
  final _Ui ui;
  final bool showDebug;
  final VoidCallback onClose;
  final VoidCallback onDone;
  final VoiceGuide? voiceGuide;
  final VoidCallback onToggleMute;

  bool _mirror(CameraChoice? c) => c == null
      ? false
      : controller.config.mirrorPreviewFor(c.kind, defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    if (state case final Reviewing review) {
      return ReviewView(
        key: ValueKey(review.video.path), // new clip, new player
        controller: controller,
        review: review,
        strings: ui.strings,
        icons: ui.icons,
        skeletonColors: ui.skeleton,
        activeColor: ui.active,
        onCancel: onClose,
      );
    }
    final cam = controller.camera;
    final issue = switch (state) {
      Checking(:final issue) => issue,
      _ => null,
    };
    final borderColor = issue != null
        ? ui.error
        : state is Recording
            ? ui.active
            : Colors.transparent;

    final stack = Stack(
      children: [
        if (cam != null && cam.value.isInitialized)
          Center(
            // Display-only mirroring; the recorded file is never mirrored.
            child: Transform.flip(
              flipX: _mirror(controller.selectedCamera),
              child: CameraPreview(
                cam,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _SafeZoneOverlay(inset: controller.config.safeZoneInset),
                    // Tracking marks sit above the safe-zone box. They are not
                    // "details": `showDetails` does not hide them, only
                    // `showSkeleton` does. The debug rings (showDebug) are
                    // drawn by the same layer.
                    if (controller.config.showSkeleton || showDebug)
                      Transform.flip(
                        flipX: controller.selectedCamera != null &&
                            controller.config.overlayFlipFor(
                                controller.selectedCamera!.kind,
                                defaultTargetPlatform),
                        child: SkeletonLayer(
                          frames: controller.overlay,
                          colors: ui.skeleton,
                          minLikelihood:
                              controller.config.skeletonMinLikelihood,
                          transition: const Duration(milliseconds: 50),
                          drawMarks: controller.config.showSkeleton,
                          debugMetrics: showDebug ? controller.metrics : null,
                          debugBadColor: ui.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 10),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: voiceGuide != null ? 88 : 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final banner =
                  _TopBanner(controller: controller, state: state, ui: ui);
              if (!showDebug) return banner;
              final debug = DebugMetricsPanel(metrics: controller.metrics);
              if (constraints.maxWidth <
                  MovementCaptureConfig.tabletShortestSide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [banner, const SizedBox(height: 12), debug],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: banner),
                  const SizedBox(width: 16),
                  SizedBox(width: 280, child: debug),
                ],
              );
            },
          ),
        ),
        if (state case CountingDown(:final secondsLeft))
          Center(
            child: _CountdownNumber(
              seconds: secondsLeft,
              size:
                  controller.config.mode == CaptureMode.selfGuided ? 220 : 180,
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _BottomBar(
            controller: controller,
            state: state,
            ui: ui,
            onCancel: onClose,
            onChooseCamera: () => _showCameraSheet(context, controller, ui),
          ),
        ),
        if (voiceGuide case final guide?)
          Positioned(
            top: 16,
            right: 16,
            child: IconButton.filledTonal(
              iconSize: 32,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              tooltip: guide.muted ? ui.strings.unmute : ui.strings.mute,
              onPressed: onToggleMute,
              icon: Icon(guide.muted ? ui.icons.voiceOff : ui.icons.voiceOn),
            ),
          ),
        if (_panel(context) case final Widget panel) panel,
        if (state is Checking && controller.awaitingSideChoice)
          Positioned.fill(
            child: SideChoiceView(
              step: controller.currentStep,
              strings: ui.strings,
              onChoose: controller.chooseSides,
              onCancel: onClose,
            ),
          ),
      ],
    );
    final showStatus = state is Checking ||
        state is CountingDown ||
        (state is Recording && (state as Recording).liveChecks);
    if (!showStatus) return stack;
    // The status sits above the picture, never on it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QualityStatusBar(
          status: controller.status,
          cameraWeak: controller.cameraWeak,
          strings: ui.strings,
          icons: ui.icons,
          goodColor: ui.active,
          warningColor: ui.warning,
          badColor: ui.error,
          outOfFrameWarning: controller.outOfFrameWarning,
          stopUnavailable: controller.outOfFrameStopUnavailable,
        ),
        Expanded(child: stack),
      ],
    );
  }

  Widget? _panel(BuildContext context) {
    final s = ui.strings;
    final skip = controller.canSkipCurrentStep
        ? _PanelAction(s.skipStep, controller.skipStep, icon: ui.icons.skipStep)
        : null;
    return switch (state) {
      Initializing() => _Panel(
          ui: ui,
          busy: true,
          message: s.starting,
          actions: [_PanelAction(s.cancel, onClose)],
        ),
      CameraUnavailable(:final reason) => _Panel(
          ui: ui,
          icon: ui.icons.cameraOff,
          isError: true,
          message: s.cameraFailure(reason),
          actions: [
            _PanelAction(s.cancel, onClose),
            if (reason == CameraFailure.permissionDenied)
              _PanelAction(s.openSettings,
                  () => unawaited(NativeBridge.openAppSettings()))
            else if (controller.cameras.isNotEmpty)
              _PanelAction(s.useAnotherCamera,
                  () => _showCameraSheet(context, controller, ui),
                  icon: ui.icons.switchCamera),
            if (skip != null) skip,
            _PanelAction(s.retry, controller.retryCamera, primary: true),
          ],
        ),
      NeedsOperator(:final lastIssue) => _Panel(
          ui: ui,
          icon: ui.icons.issue(lastIssue),
          isError: true,
          message: '${s.needsOperatorFor(controller.config.mode)}\n\n'
              '${s.issueFor(lastIssue, controller.config.mode)}',
          actions: [
            _PanelAction(s.cancel, onClose),
            if (controller.cameras.length > 1)
              _PanelAction(s.useAnotherCamera,
                  () => _showCameraSheet(context, controller, ui),
                  icon: ui.icons.switchCamera),
            if (skip != null) skip,
            _PanelAction(s.tryAgain, controller.operatorRetry, primary: true),
          ],
        ),
      Finishing(:final progress) => _Panel(
          ui: ui,
          busy: true,
          progress: progress,
          message: s.uploading((progress * 100).round()),
          actions: [_PanelAction(s.cancel, onClose)],
        ),
      FinishFailed() => _Panel(
          ui: ui,
          icon: ui.icons.uploadFailed,
          isError: true,
          message: s.uploadFailed,
          actions: [
            _PanelAction(s.cancel, onClose),
            _PanelAction(s.retry, controller.retryFailedUploads, primary: true),
          ],
        ),
      SessionComplete() => _Panel(
          ui: ui,
          icon: ui.icons.completed,
          message: s.completed,
          extra: SideSummary(steps: controller.results, strings: s),
          actions: [_PanelAction(s.done, onDone, primary: true)],
        ),
      _ => null,
    };
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({
    required this.controller,
    required this.state,
    required this.ui,
  });
  final MovementCaptureController controller;
  final CaptureState state;
  final _Ui ui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = controller.config.mode;
    final textStyle = mode == CaptureMode.selfGuided
        ? theme.textTheme.headlineMedium
        : theme.textTheme.headlineSmall;
    final s = ui.strings;
    final step = controller.currentStep;
    // The step counter is a detail: hidden when config.showDetails is off.
    final progress = controller.config.showDetails
        ? Text(
            s.stepProgress(controller.stepIndex, controller.stepCount, step),
            style: theme.textTheme.titleMedium,
          )
        : null;

    Widget infoRow(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
            ],
          ),
        );

    switch (state) {
      case Checking(
          issue: final issue?,
          :final interrupted,
          :final interruptedOutOfFrame
        ):
        return _BannerCard(
          color: scheme.errorContainer,
          child: Row(
            children: [
              Icon(ui.icons.issue(issue),
                  size: 40, color: scheme.onErrorContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  interruptedOutOfFrame
                      ? s.outOfFrameStopped
                      : interrupted
                          ? '${s.interrupted}\n${s.issueFor(issue, mode)}'
                          : s.issueFor(issue, mode),
                  style: textStyle?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
      case Checking(:final armed):
        final saved = controller.lastSavedStep;
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(ui.icons.step(step), size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: progress ?? Text(s.stepTitle(step))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  armed
                      ? s.hintArmedFor(mode)
                      : step.hasSides &&
                              controller.sideChoiceFor(step) != SideChoice.both
                          ? s.sideInstruction(
                              step, controller.sideChoiceFor(step))
                          : s.stepInstructionFor(step, mode),
                  style: textStyle),
              if (saved != null && !armed)
                infoRow(ui.icons.saved, s.stepSaved(saved)),
              if (controller.usingTabletFallback)
                infoRow(ui.icons.info, s.noUsbCameraNotice),
            ],
          ),
        );
      case CountingDown():
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null) ...[progress, const SizedBox(height: 8)],
              Text(s.getReady, style: textStyle),
            ],
          ),
        );
      case final Recording r:
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null) ...[progress, const SizedBox(height: 8)],
              Row(
                children: [
                  Icon(ui.icons.recordingDot, color: ui.error, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.recording(r.elapsed.inSeconds, r.total.inSeconds),
                      style: textStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: r.progress,
                minHeight: 10,
                color: ui.active,
              ),
              if (!r.liveChecks) infoRow(ui.icons.info, s.noLiveChecksNotice),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      );
}

class _CountdownNumber extends StatelessWidget {
  const _CountdownNumber({required this.seconds, required this.size});
  final int seconds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$seconds',
        style: Theme.of(context)
            .textTheme
            .displayLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.state,
    required this.ui,
    required this.onCancel,
    required this.onChooseCamera,
  });

  final MovementCaptureController controller;
  final CaptureState state;
  final _Ui ui;
  final VoidCallback onCancel;
  final VoidCallback onChooseCamera;

  @override
  Widget build(BuildContext context) {
    final showCancel =
        state is Checking || state is CountingDown || state is Recording;
    if (!showCancel) return const SizedBox.shrink();

    final showStart = switch (state) {
      Checking(armed: false) => true,
      _ => false,
    };
    final selected = controller.selectedCamera;
    const tall = Size(0, 56);

    final cancel = OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: tall),
      onPressed: onCancel,
      child: Text(ui.strings.cancel),
    );
    // `selected != null` inside the condition lets Dart treat it as non-null.
    final cameraButton = controller.canChangeCamera && selected != null
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: tall),
            onPressed: onChooseCamera,
            icon: Icon(ui.icons.switchCamera),
            label: Text(
              ui.strings.cameraLabel(selected),
              overflow: TextOverflow.ellipsis,
            ),
          )
        : null;
    final skip = controller.canSkipCurrentStep
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: tall),
            onPressed: controller.skipStep,
            icon: Icon(ui.icons.skipStep),
            label: Text(ui.strings.skipStep, overflow: TextOverflow.ellipsis),
          )
        : null;
    final start = showStart
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: tall),
            onPressed: controller.startRequested,
            icon: Icon(ui.icons.startRecording),
            label: Text(ui.strings.startRecording),
          )
        : null;

    final secondary = [
      cancel,
      if (cameraButton != null) cameraButton,
      if (skip != null) skip,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < MovementCaptureConfig.tabletShortestSide) {
        // Phones: Start full width on top, the others below.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (start != null) ...[start, const SizedBox(height: 12)],
            Row(
              children: [
                for (var i = 0; i < secondary.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: secondary[i]),
                ],
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 200, child: cancel),
          if (cameraButton != null) ...[
            const SizedBox(width: 16),
            Flexible(child: cameraButton),
          ],
          if (skip != null) ...[
            const SizedBox(width: 16),
            Flexible(child: skip),
          ],
          const Spacer(),
          if (start != null) SizedBox(width: 240, child: start),
        ],
      );
    });
  }
}

class _PanelAction {
  const _PanelAction(this.label, this.onPressed,
      {this.primary = false, this.icon});
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final IconData? icon;
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.ui,
    required this.message,
    this.icon,
    this.busy = false,
    this.isError = false,
    this.progress,
    this.extra,
    this.actions = const [],
  });

  final _Ui ui;
  final String message;
  final IconData? icon;
  final bool busy;
  final bool isError;
  final double? progress;
  final Widget? extra;
  final List<_PanelAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const buttonSize = Size(160, 56);

    Widget button(_PanelAction a) {
      final label = Text(a.label);
      if (a.primary) {
        return a.icon == null
            ? FilledButton(
                style: FilledButton.styleFrom(minimumSize: buttonSize),
                onPressed: a.onPressed,
                child: label)
            : FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: buttonSize),
                onPressed: a.onPressed,
                icon: Icon(a.icon),
                label: label);
      }
      return a.icon == null
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: buttonSize),
              onPressed: a.onPressed,
              child: label)
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: buttonSize),
              onPressed: a.onPressed,
              icon: Icon(a.icon),
              label: label);
    }

    return Positioned.fill(
      child: ColoredBox(
        color: scheme.scrim.withValues(alpha: 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(24),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy && progress == null)
                        const SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(strokeWidth: 5),
                        )
                      else if (icon != null)
                        Icon(icon,
                            size: 64, color: isError ? ui.error : ui.active),
                      if (progress != null)
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          color: ui.active,
                        ),
                      const SizedBox(height: 24),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (extra != null) ...[
                        const SizedBox(height: 24),
                        extra!,
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [for (final a in actions) button(a)],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outline of the safe zone the person (or face, hands, feet) must stay inside.
class _SafeZoneOverlay extends StatelessWidget {
  const _SafeZoneOverlay({required this.inset});
  final double inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _SafeZonePainter(
          inset: inset,
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
        ),
      );
}

class _SafeZonePainter extends CustomPainter {
  _SafeZonePainter({required this.inset, required this.color});
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      size.width * inset,
      size.height * inset,
      size.width * (1 - inset),
      size.height * (1 - inset),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)), paint);
  }

  @override
  bool shouldRepaint(_SafeZonePainter old) =>
      old.inset != inset || old.color != color;
}
