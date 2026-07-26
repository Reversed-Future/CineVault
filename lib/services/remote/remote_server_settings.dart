import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

class RemoteServerSettings {
  const RemoteServerSettings({
    required this.enabled,
    required this.port,
    required this.token,
  });

  final bool enabled;
  final int port;
  final String token;

  RemoteServerSettings copyWith({
    bool? enabled,
    int? port,
    String? token,
  }) {
    return RemoteServerSettings(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      token: token ?? this.token,
    );
  }
}

class RemoteServerSettingsService {
  static const String boxName = 'remote_server_settings';
  static const int defaultPort = 53287;
  static const String _enabledKey = 'enabled';
  static const String _portKey = 'port';
  static const String _tokenKey = 'token';

  Future<RemoteServerSettings> load() async {
    final box = await Hive.openBox<dynamic>(boxName);
    final token = (box.get(_tokenKey) as String?)?.trim();
    if (token == null || token.isEmpty) {
      final generatedToken = _generateToken();
      final settings = RemoteServerSettings(
        enabled: box.get(_enabledKey) as bool? ?? true,
        port: box.get(_portKey) as int? ?? defaultPort,
        token: generatedToken,
      );
      await save(settings);
      return settings;
    }

    return RemoteServerSettings(
      enabled: box.get(_enabledKey) as bool? ?? true,
      port: box.get(_portKey) as int? ?? defaultPort,
      token: token,
    );
  }

  Future<void> save(RemoteServerSettings settings) async {
    final box = await Hive.openBox<dynamic>(boxName);
    await box.put(_enabledKey, settings.enabled);
    await box.put(_portKey, settings.port);
    await box.put(_tokenKey, settings.token.trim());
  }

  Future<RemoteServerSettings> regenerateToken() async {
    final settings = await load();
    final updated = settings.copyWith(token: _generateToken());
    await save(updated);
    return updated;
  }

  String _generateToken() {
    final random = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
