import 'package:flutter_test/flutter_test.dart';

import 'package:cine_vault/models/app_settings.dart';

void main() {
  test('AppSettings defaults are usable', () {
    final settings = AppSettings();

    expect(settings.playbackSpeed, 1.0);
    expect(settings.autoResumePlayback, isTrue);
    expect(settings.videoFolders, isEmpty);
  });
}
