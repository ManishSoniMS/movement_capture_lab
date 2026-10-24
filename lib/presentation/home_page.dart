import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movement_capture/movement_capture.dart';

import 'camera_info_page.dart';
import '../domain/lab_settings.dart';
import '../data/uploaders.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LabSettings _s = LabSettings();
  final List<String> _log = [];
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  MovementUploader _uploader() => switch (_s.uploaderMode) {
        UploaderMode.mock => MockUploader(),
        UploaderMode.mockFail => MockUploader(fail: true),
        UploaderMode.inspection => InspectionUploader(),
        UploaderMode.http => HttpUploader(
            endpointUrl: _url.text.trim(),
            bearerToken: _token.text.trim(),
          ),
      };

  Future<void> _start() async {
    if (_s.uploaderMode == UploaderMode.http &&
        Uri.tryParse(_url.text.trim())?.hasScheme != true) {
      _snack('Enter a full endpoint URL first');
      return;
    }
    final settings = _s.summary();
    final id = await MovementCapture.open(
      context,
      config: _s.toConfig(),
      uploader: _uploader(),
      showDebugOverlay: _s.debugOverlay,
    );
    if (!mounted) return;
    setState(() => _log.insert(0,
        '${TimeOfDay.now().format(context)}  ${id ?? 'cancelled'}\n$settings'));
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    String Function(double) format,
    void Function(double) apply,
  ) {
    return ListTile(
      title: Text('$label: ${format(value)}'),
      subtitle: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => setState(() => apply(v)),
      ),
    );
  }

  String _int(double v) => v.round().toString();
  String _dec(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movement Capture Lab'),
        actions: [
          IconButton(
            tooltip: 'Cameras',
            icon: const Icon(Icons.usb),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CameraInfoPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const _Section('Timing'),
          _slider('Max duration (s, values above 30 are clamped)',
              _s.maxDurationS, 5, 45, 40, _int, (v) => _s.maxDurationS = v),
          _slider('Countdown (s)', _s.countdownS, 1, 5, 4, _int,
              (v) => _s.countdownS = v),
          _slider('Stable before start (ms)', _s.stableMs, 500, 3000, 25, _int,
              (v) => _s.stableMs = v),
          _slider('Failure grace (ms)', _s.graceMs, 100, 1500, 28, _int,
              (v) => _s.graceMs = v),
          _slider('Auto restarts before operator', _s.maxRestarts, 0, 6, 6,
              _int, (v) => _s.maxRestarts = v),
          _slider('Analysis interval (ms)', _s.analysisIntervalMs, 50, 500, 18,
              _int, (v) => _s.analysisIntervalMs = v),
          const _Section('Camera'),
          ListTile(
            title: const Text('Rotation for analysis'),
            trailing: DropdownButton<int>(
              value: _s.rotation,
              items: const [0, 90, 180, 270]
                  .map((d) => DropdownMenuItem(value: d, child: Text('$d°')))
                  .toList(),
              onChanged: (v) => setState(() => _s.rotation = v ?? 0),
            ),
          ),
          ListTile(
            title: const Text('Resolution'),
            trailing: DropdownButton<ResolutionPreset>(
              value: _s.resolution,
              items: const [
                ResolutionPreset.medium,
                ResolutionPreset.high,
                ResolutionPreset.veryHigh,
              ]
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _s.resolution = v ?? ResolutionPreset.high),
            ),
          ),
          const _Section('Framing'),
          _slider('Safe-zone inset', _s.safeZoneInset, 0, 0.2, 40,
              (v) => v.toStringAsFixed(3), (v) => _s.safeZoneInset = v),
          _slider('Min body-point likelihood', _s.minLikelihood, 0.1, 0.95, 17,
              _dec, (v) => _s.minLikelihood = v),
          const _Section('Lighting'),
          _slider('Too dark below', _s.minLuma, 20, 120, 100, _int,
              (v) => _s.minLuma = v),
          _slider('Too bright above', _s.maxLuma, 150, 250, 100, _int,
              (v) => _s.maxLuma = v),
          _slider('Max clipped share', _s.maxClipped, 0.05, 0.6, 55, _dec,
              (v) => _s.maxClipped = v),
          _slider('Backlit below centre/border', _s.minCenterToBorder, 0.3,
              0.95, 65, _dec, (v) => _s.minCenterToBorder = v),
          const _Section('Upload'),
          for (final mode in UploaderMode.values)
            RadioListTile<UploaderMode>(
              value: mode,
              groupValue: _s.uploaderMode,
              onChanged: (v) => setState(() => _s.uploaderMode = v!),
              title: Text(switch (mode) {
                UploaderMode.mock => 'Mock (succeeds)',
                UploaderMode.mockFail => 'Mock (always fails)',
                UploaderMode.inspection =>
                  'Keep clip for inspection (lab only)',
                UploaderMode.http => 'Real HTTP endpoint',
              }),
            ),
          if (_s.uploaderMode == UploaderMode.http) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'https://api.example.com/movement-analysis/videos',
                ),
                keyboardType: TextInputType.url,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _token,
                decoration:
                    const InputDecoration(labelText: 'Bearer token (optional)'),
                obscureText: true,
              ),
            ),
          ],
          const _Section('Tools'),
          SwitchListTile(
            title: const Text('Debug overlay'),
            value: _s.debugOverlay,
            onChanged: (v) => setState(() => _s.debugOverlay = v),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy current settings'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _s.summary()));
              _snack('Settings copied');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Purge capture cache now'),
            onTap: () async {
              await MovementCapture.purgeAll();
              _snack('Capture cache purged');
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_delete_outlined),
            title: const Text('Delete inspection clips'),
            onTap: () async {
              final n = await InspectionUploader.clear();
              _snack('Deleted $n inspection clip(s)');
            },
          ),
          const _Section('Results'),
          if (_log.isEmpty)
            const ListTile(title: Text('No runs yet'))
          else
            for (final line in _log) ListTile(title: Text(line)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _start,
        icon: const Icon(Icons.videocam),
        label: const Text('Start capture'),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}
