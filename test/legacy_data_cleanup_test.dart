import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cine_vault/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('database initialization removes legacy person detail box', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('cine_vault_legacy_cleanup_');

    Hive.init(tempDir.path);
    final legacyBox = await Hive.openBox('stars');
    await legacyBox.put('person-id', {'name': 'legacy'});
    await legacyBox.close();
    await Hive.close();

    await DatabaseService.init(customPath: tempDir.path);

    expect(await Hive.boxExists('stars'), isFalse);
  });
}
