import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture_lab/data/prefs_settings_store.dart';
import 'package:movement_capture_lab/domain/lab_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('show camera details defaults to on', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PrefsSettingsStore().loadShowCameraDetails(), isTrue);
    expect(LabSettings().showCameraDetails, isTrue);
  });

  test('the switch survives a restart (new store instance, same storage)',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PrefsSettingsStore().saveShowCameraDetails(false);
    expect(await PrefsSettingsStore().loadShowCameraDetails(), isFalse);
    await PrefsSettingsStore().saveShowCameraDetails(true);
    expect(await PrefsSettingsStore().loadShowCameraDetails(), isTrue);
  });

  test('the setting reaches the capture config', () {
    final s = LabSettings()..showCameraDetails = false;
    expect(s.toConfig().showDetails, isFalse);
  });

  test('one scan type per session, none pre-selected', () {
    final s = LabSettings();
    expect(s.scan.selected, isNull);
    s.scan.select(CaptureStep.hands);
    expect(s.toConfig().steps, [CaptureStep.hands]);
  });
}
