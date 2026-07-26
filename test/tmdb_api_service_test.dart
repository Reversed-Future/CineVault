import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/tmdb_api_service.dart';

void main() {
  test('testConnection reports a readable timeout message', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {});
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final service = TmdbApiService(
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.close);

    service.configure(
      baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
      apiKey: 'test-key',
    );

    await expectLater(
      service.testConnection(),
      throwsA(
        isA<TmdbConnectionException>().having(
          (error) => error.message,
          'message',
          contains('连接 TMDB 超时'),
        ),
      ),
    );
  });

  test('testConnection rejects unsupported socks5 proxy for TMDB requests',
      () async {
    final service = TmdbApiService(
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.close);

    service.configure(
      baseUrl: 'http://127.0.0.1:1',
      apiKey: 'test-key',
    );
    service.configureProxy(
      enabled: true,
      type: 'socks5',
      host: '127.0.0.1',
      port: 1080,
    );

    await expectLater(
      service.testConnection(),
      throwsA(
        isA<TmdbConnectionException>().having(
          (error) => error.message,
          'message',
          contains('仅支持 HTTP 代理'),
        ),
      ),
    );
  });
}
