import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class DataStoragePathChangeResult {
  final String storagePath;
  final bool migrationSnapshotCreated;

  const DataStoragePathChangeResult({
    required this.storagePath,
    required this.migrationSnapshotCreated,
  });
}

class DataStoragePathService {
  static const String _pointerFileName = 'data_path.json';
  static const String _pathKey = 'dataStoragePath';
  static const String _pendingImportFileName = 'pending_data_import.json';

  static String getApplicationExecutableDirectory() {
    return path.dirname(Platform.resolvedExecutable);
  }

  static Future<String> getDefaultDataPath() async {
    final dataDir = Directory(
      path.join(getApplicationExecutableDirectory(), 'data'),
    );
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir.path;
  }

  static Future<String> resolveInitialDataPath() async {
    final defaultPath = await getDefaultDataPath();
    final pointerFile = File(
      path.join(getApplicationExecutableDirectory(), _pointerFileName),
    );

    if (!await pointerFile.exists()) {
      return defaultPath;
    }

    try {
      final rawJson = await pointerFile.readAsString(encoding: utf8);
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      final configuredPath = (data[_pathKey] as String?)?.trim();
      if (configuredPath == null || configuredPath.isEmpty) {
        return defaultPath;
      }

      final dir = Directory(configuredPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } catch (_) {
      return defaultPath;
    }
  }

  static Future<DataStoragePathChangeResult> prepareDataPathChange({
    required String newPath,
    required Future<void> Function(String filePath) exportData,
  }) async {
    final trimmedPath = newPath.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(newPath, 'newPath', 'Data path is empty');
    }

    final storagePath = path.normalize(path.absolute(trimmedPath));
    final targetDir = Directory(storagePath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    var migrationSnapshotCreated = false;
    if (!await _hasHiveDataFiles(targetDir)) {
      await exportData(getPendingImportPath(storagePath));
      migrationSnapshotCreated = true;
    }

    await _writePointer(storagePath);
    return DataStoragePathChangeResult(
      storagePath: storagePath,
      migrationSnapshotCreated: migrationSnapshotCreated,
    );
  }

  static String getPendingImportPath(String storagePath) {
    return path.join(storagePath, _pendingImportFileName);
  }

  static Future<void> consumePendingImport({
    required String storagePath,
    required Future<void> Function(String filePath) importData,
  }) async {
    final importFile = File(getPendingImportPath(storagePath));
    if (!await importFile.exists()) {
      return;
    }

    await importData(importFile.path);

    try {
      if (await importFile.exists()) {
        await importFile.delete();
      }
    } catch (_) {}
  }

  static Future<void> _writePointer(String storagePath) async {
    final pointerFile = File(
      path.join(getApplicationExecutableDirectory(), _pointerFileName),
    );
    if (!await pointerFile.parent.exists()) {
      await pointerFile.parent.create(recursive: true);
    }
    await pointerFile.writeAsString(
      jsonEncode(<String, String>{_pathKey: storagePath}),
      encoding: utf8,
    );
  }

  static Future<bool> _hasHiveDataFiles(Directory dir) async {
    if (!await dir.exists()) {
      return false;
    }

    await for (final entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final name = path.basename(entity.path).toLowerCase();
      if (name.endsWith('.hive') ||
          name.endsWith('.hivec') ||
          name.endsWith('.lock')) {
        return true;
      }
    }

    return false;
  }
}
