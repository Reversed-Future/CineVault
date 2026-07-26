import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/remote/remote_auth.dart';

void main() {
  group('RemoteAuth', () {
    test('accepts matching bearer token', () {
      expect(
        RemoteAuth.isAuthorized(
          authorizationHeader: 'Bearer abc123',
          expectedToken: 'abc123',
        ),
        isTrue,
      );
    });

    test('rejects missing bearer prefix', () {
      expect(
        RemoteAuth.isAuthorized(
          authorizationHeader: 'abc123',
          expectedToken: 'abc123',
        ),
        isFalse,
      );
    });

    test('rejects wrong bearer token', () {
      expect(
        RemoteAuth.isAuthorized(
          authorizationHeader: 'Bearer wrong',
          expectedToken: 'abc123',
        ),
        isFalse,
      );
    });
  });
}
