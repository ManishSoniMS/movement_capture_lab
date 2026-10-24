import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/camera_choice.dart';
import '../domain/capture_state.dart';
import '../domain/config.dart';
import '../domain/uploader.dart';
import 'controller.dart';
import 'customization.dart';
import 'debug_overlay.dart';

/// Pops with the analysis id on success, or null on cancel.
class MovementCaptureScreen extends StatefulWidget {
  const MovementCaptureScreen({
    super.key,
    required this.config,
    required this.uploader,
    this.strings = const MovementCaptureStrings(),
    this.icons = const MovementCaptureIcons(),
    this.style = const MovementCaptureStyle(),
    this.showDebugOverlay = false,
    this.onCameraChanged,
  });

  final MovementCaptureConfig config;
  final MovementUploader uploader;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final MovementCaptureStyle style;
  final bool showDebugOverlay;
  final void Function(CameraDescription camera)? onCameraChanged;

  @override
  State<MovementCaptureScreen> createState() => _MovementCaptureScreenState();
}

class _MovementCaptureScreenState extends State<MovementCaptureScreen>
    with WidgetsBindingObserver {
  late final MovementCaptureController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortestSide =
        (view.physicalSize / view.devicePixelRatio).shortestSide;
    SystemChrome.setPreferredOrientations(
        widget.config.orientationsFor(shortestSide));
    _controller = MovementCaptureController(
      config: widget.config,
      uploader: widget.uploader,
      onCameraChanged: widget.onCameraChanged,
    );
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
    _controller.dispose(); // stops recording, cancels upload, deletes files
    super.dispose();
  }

  void _close([String? analysisId]) => Navigator.of(context).pop(analysisId);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ui = _Ui(
      strings: widget.strings,
      icons: widget.icons,
      error: widget.style.errorColor ?? scheme.error,
      active: widget.style.activeColor ?? scheme.primary,
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return PopScope(
          canPop: state is! Uploading,
          child: Scaffold(
            backgroundColor: scheme.scrim,
            body: SafeArea(
              child: _CaptureBody(
                controller: _controller,
                state: state,
                ui: ui,
                showDebug: widget.showDebugOverlay,
                onClose: _close,
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
  });
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final Color error;
  final Color active;
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
  });

  final MovementCaptureController controller;
  final CaptureState state;
  final _Ui ui;
  final bool showDebug;
  final void Function([String? analysisId]) onClose;

  bool _mirror(CameraChoice? c) => c == null
      ? false
      : controller.config.mirrorPreviewFor(c.kind, defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
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

    return Stack(
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
                    if (showDebug)
                      LandmarkLayer(
                        metrics: controller.metrics,
                        okColor: ui.active,
                        badColor: ui.error,
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
          right: 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final banner = _TopBanner(
                state: state,
                ui: ui,
                showFallbackNotice: controller.usingTabletFallback,
              );
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
          Center(child: _CountdownNumber(seconds: secondsLeft)),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _BottomBar(
            controller: controller,
            state: state,
            ui: ui,
            onStart: controller.startRequested,
            onCancel: () => onClose(),
            onChooseCamera: () => _showCameraSheet(context, controller, ui),
          ),
        ),
        if (_panel(context) case final Widget panel) panel,
      ],
    );
  }

  Widget? _panel(BuildContext context) {
    final s = ui.strings;
    return switch (state) {
      Initializing() => _Panel(ui: ui, busy: true, message: s.starting),
      CameraUnavailable(:final reason) => _Panel(
          ui: ui,
          icon: ui.icons.cameraOff,
          isError: true,
          message: s.cameraFailure(reason),
          primaryLabel: s.retry,
          onPrimary: controller.retryCamera,
          secondaryLabel: s.cancel,
          onSecondary: () => onClose(),
          tertiaryLabel:
              controller.cameras.isNotEmpty ? s.useAnotherCamera : null,
          onTertiary: () => _showCameraSheet(context, controller, ui),
        ),
      NeedsOperator(:final lastIssue) => _Panel(
          ui: ui,
          icon: ui.icons.issue(lastIssue),
          isError: true,
          message: '${s.needsOperator}\n\n${s.issue(lastIssue)}',
          primaryLabel: s.tryAgain,
          onPrimary: controller.operatorRetry,
          secondaryLabel: s.cancel,
          onSecondary: () => onClose(),
          tertiaryLabel:
              controller.cameras.length > 1 ? s.useAnotherCamera : null,
          onTertiary: () => _showCameraSheet(context, controller, ui),
        ),
      Uploading(:final progress) => _Panel(
          ui: ui,
          busy: true,
          progress: progress,
          message: s.uploading((progress * 100).round()),
        ),
      UploadFailed() => _Panel(
          ui: ui,
          icon: ui.icons.uploadFailed,
          isError: true,
          message: s.uploadFailed,
          primaryLabel: s.retry,
          onPrimary: controller.retryUpload,
          secondaryLabel: s.cancel,
          onSecondary: () => onClose(),
        ),
      Completed(:final analysisId) => _Panel(
          ui: ui,
          icon: ui.icons.completed,
          message: s.completed,
          primaryLabel: s.done,
          onPrimary: () => onClose(analysisId),
        ),
      _ => null,
    };
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({
    required this.state,
    required this.ui,
    required this.showFallbackNotice,
  });
  final CaptureState state;
  final _Ui ui;
  final bool showFallbackNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.headlineSmall;
    final s = ui.strings;

    switch (state) {
      case Checking(issue: final issue?, :final interrupted):
        return _BannerCard(
          color: scheme.errorContainer,
          child: Row(
            children: [
              Icon(ui.icons.issue(issue),
                  size: 40, color: scheme.onErrorContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  interrupted
                      ? '${s.interrupted}\n${s.issue(issue)}'
                      : s.issue(issue),
                  style: textStyle?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
      case Checking(:final armed):
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(armed ? s.hintArmed : s.hintIdle, style: textStyle),
              if (showFallbackNotice) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(ui.icons.info, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.noUsbCameraNotice,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      case CountingDown():
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Text(s.getReady, style: textStyle),
        );
      case final Recording r:
        return _BannerCard(
          color: scheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
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
              if (!r.liveChecks) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(ui.icons.info, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.noLiveChecksNotice,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
              ],
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
  const _CountdownNumber({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 180,
      height: 180,
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
    required this.onStart,
    required this.onCancel,
    required this.onChooseCamera,
  });

  final MovementCaptureController controller;
  final CaptureState state;
  final _Ui ui;
  final VoidCallback onStart;
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
    final start = showStart
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: tall),
            onPressed: onStart,
            icon: Icon(ui.icons.startRecording),
            label: Text(ui.strings.startRecording),
          )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < MovementCaptureConfig.tabletShortestSide) {
        // Phones: Start full width on top, the other two below.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (start != null) ...[start, const SizedBox(height: 12)],
            Row(
              children: [
                Expanded(child: cancel),
                if (cameraButton != null) ...[
                  const SizedBox(width: 12),
                  Expanded(child: cameraButton),
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
          const Spacer(),
          if (start != null) SizedBox(width: 240, child: start),
        ],
      );
    });
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.ui,
    required this.message,
    this.icon,
    this.busy = false,
    this.isError = false,
    this.progress,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
  });

  final _Ui ui;
  final String message;
  final IconData? icon;
  final bool busy;
  final bool isError;
  final double? progress;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const buttonSize = Size(160, 56);
    return Positioned.fill(
      child: ColoredBox(
        color: scheme.scrim.withValues(alpha: 0.6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
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
                    if (primaryLabel != null ||
                        secondaryLabel != null ||
                        tertiaryLabel != null) ...[
                      const SizedBox(height: 32),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          if (secondaryLabel != null)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: buttonSize),
                              onPressed: onSecondary,
                              child: Text(secondaryLabel!),
                            ),
                          if (tertiaryLabel != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: buttonSize),
                              onPressed: onTertiary,
                              icon: Icon(ui.icons.switchCamera),
                              label: Text(tertiaryLabel!),
                            ),
                          if (primaryLabel != null)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  minimumSize: buttonSize),
                              onPressed: onPrimary,
                              child: Text(primaryLabel!),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outline of the safe zone the patient must stay inside.
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
