import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/image_cache_service.dart';

void main() {
  test('generateMD5Hash keeps query parameters in the cache key', () {
    final firstHash = ImageCacheService.generateMD5Hash(
      'http://127.0.0.1:53287/api/images/proxy?token=one&url=a.jpg',
    );
    final secondHash = ImageCacheService.generateMD5Hash(
      'http://127.0.0.1:53287/api/images/proxy?token=one&url=b.jpg',
    );

    expect(firstHash, isNot(secondHash));
  });
}
