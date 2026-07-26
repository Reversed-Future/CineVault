import '../../models/movie.dart';
import '../../models/named_item.dart';
import '../../models/custom_movie_tag.dart';
import '../database_service.dart';

class RemoteMovieSerializer {
  static Map<String, dynamic> toMobileJson(
    Movie movie, {
    String? imageProxyBaseUrl,
  }) {
    final favorite = movie.safeIsFavorite;
    final watchProgress = movie.safeLastWatchPosition.round();
    final hasLocalVideo =
        movie.videoFilePaths != null && movie.videoFilePaths!.isNotEmpty;
    final customTags = _customTagsForMovie(movie.id);
    final coverUrl = _proxyImageUrl(movie.coverUrl, imageProxyBaseUrl);
    final backdropUrl = _proxyImageUrl(movie.backdropUrl, imageProxyBaseUrl);
    final originalCoverUrl = _proxyImageUrl(
      movie.originalCoverUrl,
      imageProxyBaseUrl,
    );

    return {
      'id': movie.id,
      'code': movie.code,
      'title': movie.name,
      'name': movie.name,
      'path': movie.path,
      'size': movie.size,
      'createdAt': movie.createdAt,
      'coverUrl': coverUrl,
      'backdropUrl': backdropUrl,
      'originalCoverUrl': originalCoverUrl,
      'isCoverCropped': movie.safeIsCoverCropped,
      'favorite': favorite,
      'isFavorite': favorite,
      'watchProgress': watchProgress,
      'lastWatchPosition': movie.safeLastWatchPosition,
      'lastWatchedAt': movie.safeLastWatchedAt,
      'playCount': movie.safePlayCount,
      'hasLocalVideo': hasLocalVideo,
      'releaseDate': movie.releaseDate,
      'length': movie.length,
      'summary': movie.translatedPlot,
      'translatedName': movie.translatedName,
      'translatedTags': movie.translatedTags ?? const <String>[],
      'cast': movie.cast
          .map((cast) => {
                'id': cast.id,
                'name': cast.name,
                'imageUrl': _proxyImageUrl(cast.imageUrl, imageProxyBaseUrl),
                'avatarUrl': _proxyImageUrl(cast.imageUrl, imageProxyBaseUrl),
              })
          .toList(),
      'actors': movie.cast
          .map((cast) => {
                'id': cast.id,
                'name': cast.name,
                'imageUrl': _proxyImageUrl(cast.imageUrl, imageProxyBaseUrl),
                'avatarUrl': _proxyImageUrl(cast.imageUrl, imageProxyBaseUrl),
              })
          .toList(),
      'tags': movie.tags
          ?.map((tag) => {
                'id': tag.id,
                'name': tag.name,
              })
          .toList(),
      'director': _namedItemToJson(movie.director),
      'producer': _namedItemToJson(movie.producer),
      'publisher': _namedItemToJson(movie.publisher),
      'series': _namedItemToJson(movie.series),
      'videoFilePaths': movie.videoFilePaths ?? const <String>[],
      'subtitleFilePaths': movie.subtitleFilePaths ?? const <String>[],
      'samples': movie.samples
              ?.map((sample) => {
                    'id': sample.id,
                    'src': _proxyImageUrl(sample.src, imageProxyBaseUrl),
                    'thumbnail': _proxyImageUrl(
                      sample.thumbnail,
                      imageProxyBaseUrl,
                    ),
                    'alt': sample.alt,
                  })
              .toList() ??
          const <Map<String, dynamic>>[],
      'magnets': movie.magnets
              ?.map((magnet) => {
                    'id': magnet.id,
                    'link': magnet.link,
                    'isHD': magnet.isHD,
                    'title': magnet.title,
                    'size': magnet.size,
                    'numberSize': magnet.numberSize,
                    'shareDate': magnet.shareDate,
                    'hasSubtitle': magnet.hasSubtitle,
                  })
              .toList() ??
          const <Map<String, dynamic>>[],
      'customTags': customTags
          .map((tag) => {
                'id': tag.id,
                'name': tag.name,
                'createdAt': tag.createdAt,
              })
          .toList(),
      'movieInfo': {
        'cover': coverUrl,
        'backdrop': backdropUrl,
        'code': movie.code,
        'releaseDate': movie.releaseDate,
        'length': movie.length == null ? null : '${movie.length} 分钟',
      },
    };
  }

  static Map<String, dynamic>? _namedItemToJson(NamedItem? item) {
    if (item == null) {
      return null;
    }
    return {
      'id': item.id,
      'name': item.name,
    };
  }

  static List<CustomMovieTag> _customTagsForMovie(String movieId) {
    try {
      return DatabaseService.getCustomTagsForMovie(movieId);
    } catch (_) {
      return const [];
    }
  }

  static String? _proxyImageUrl(String? url, String? imageProxyBaseUrl) {
    final normalized = _resolveImageUrl(url);
    if (normalized == null || normalized.isEmpty || imageProxyBaseUrl == null) {
      return normalized;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme) {
      return normalized;
    }
    return '$imageProxyBaseUrl${Uri.encodeQueryComponent(normalized)}';
  }

  static String? _resolveImageUrl(String? url) {
    if (url == null) {
      return null;
    }
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    if (normalized.startsWith('//')) {
      return 'https:$normalized';
    }
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme) {
      return normalized;
    }
    return normalized;
  }
}
