import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/remote/remote_range_parser.dart';

void main() {
  group('RemoteRangeParser', () {
    test('parses explicit byte range', () {
      final range = RemoteRangeParser.parse('bytes=10-20', 100);

      expect(range?.start, 10);
      expect(range?.end, 20);
    });

    test('parses open ended byte range', () {
      final range = RemoteRangeParser.parse('bytes=10-', 100);

      expect(range?.start, 10);
      expect(range?.end, 99);
    });

    test('rejects invalid range', () {
      final range = RemoteRangeParser.parse('items=10-20', 100);

      expect(range, isNull);
    });
  });
}
