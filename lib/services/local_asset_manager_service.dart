
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/movie.dart';

class LocalAssetManagerService {
  static Future<List<Movie>> importMovies(String assetsJsonPath) async {
    try {
      final file = File(assetsJsonPath);
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final assets = json['assets'] as List<dynamic>? ?? [];

      final movies = <Movie>[];
      for (final asset in assets) {
        try {
          movies.add(Movie.fromJson(asset as Map<String, dynamic>));
        } catch (e) {
          // Skip invalid entries
        }
      }

      return movies;
    } catch (e) {
      return [];
    }
  }

  static String? findLocalAssetManagerPath() {
    final possiblePaths = [
      path.join(Directory.current.path, 'local-asset-manager', 'data', 'assets.json'),
      path.join(Directory.current.parent.path, 'local-asset-manager', 'data', 'assets.json'),
    ];

    for (final p in possiblePaths) {
      if (File(p).existsSync()) {
        return path.dirname(p);
      }
    }
    return null;
  }
}
