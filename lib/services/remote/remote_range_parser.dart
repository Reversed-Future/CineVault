class RemoteByteRange {
  const RemoteByteRange({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;

  int get length => end - start + 1;
}

class RemoteRangeParser {
  static RemoteByteRange? parse(String? rangeHeader, int fileLength) {
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
      return null;
    }
    if (fileLength <= 0) {
      return null;
    }

    final value = rangeHeader.substring('bytes='.length);
    final parts = value.split('-');
    if (parts.length != 2) {
      return null;
    }

    final start = int.tryParse(parts[0]);
    final end = parts[1].isEmpty ? fileLength - 1 : int.tryParse(parts[1]);
    if (start == null || end == null) {
      return null;
    }
    if (start < 0 || end < start || start >= fileLength) {
      return null;
    }

    return RemoteByteRange(
      start: start,
      end: end >= fileLength ? fileLength - 1 : end,
    );
  }
}
