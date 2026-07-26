import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

class TranslateCache {
  static const String _boxName = 'translate_cache';
  Box<String>? _box;

  Future<Box<String>> _getBox() async {
    if (_box != null) return _box!;
    _box = await Hive.openBox<String>(_boxName);
    return _box!;
  }

  String _cacheKey(String modelId, String field, String text) {
    final bytes = utf8.encode('$modelId:$field:$text');
    final hash = sha1.convert(bytes);
    return hash.toString();
  }

  Future<String?> get(String modelId, String field, String text) async {
    final box = await _getBox();
    final key = _cacheKey(modelId, field, text);
    return box.get(key);
  }

  Future<void> put(
    String modelId,
    String field,
    String text,
    String translation,
  ) async {
    final box = await _getBox();
    final key = _cacheKey(modelId, field, text);
    await box.put(key, translation);
  }

  Future<void> clear() async {
    final box = await _getBox();
    await box.clear();
  }

  Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}
