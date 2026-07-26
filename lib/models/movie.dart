import 'package:hive/hive.dart';
import 'cast.dart';
import 'named_item.dart';

part 'movie.g.dart';

@HiveType(typeId: 0)
class Movie extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? path;

  @HiveField(3)
  final double? size;

  @HiveField(4)
  final int createdAt; // milliseconds since epoch

  @HiveField(5)
  final List<Cast> cast;

  @HiveField(6)
  final List<NamedItem>? tags; // 标签（包含ID和名称）

  @HiveField(7)
  final String? coverUrl;

  @HiveField(21)
  final String? originalCoverUrl; // 原始封面URL，保存用户修改前的封面

  @HiveField(22)
  final bool? isCoverCropped; // 封面是否被裁剪过

  @HiveField(28)
  final String? backdropUrl;

  @HiveField(8)
  final String code;

  @HiveField(9)
  final String? releaseDate; // ISO 8601 string

  @HiveField(10)
  final int? length; // in minutes

  @HiveField(11)
  final List<String>? videoFilePaths;

  @HiveField(12)
  final bool? isFavorite;

  @HiveField(13)
  final double? lastWatchPosition; // in seconds

  @HiveField(14)
  final int? lastWatchedAt; // milliseconds since epoch

  @HiveField(15)
  final int? playCount;

  @HiveField(16)
  final String? translatedName;

  @HiveField(17)
  final List<String>? translatedTags;

  @HiveField(18)
  final String? translatedPlot;

  @HiveField(19)
  final List<SampleInfo>? samples;

  @HiveField(20)
  final List<MagnetInfo>? magnets;

  @HiveField(23)
  final NamedItem? director; // 导演

  @HiveField(24)
  final NamedItem? producer; // 制造商

  @HiveField(25)
  final NamedItem? publisher; // 发行商

  @HiveField(26)
  final NamedItem? series; // 系列

  @HiveField(27)
  final List<String>? subtitleFilePaths;

  Movie({
    required this.id,
    required this.name,
    this.path,
    this.size,
    required this.createdAt,
    required this.cast,
    this.tags,
    this.coverUrl,
    this.originalCoverUrl,
    this.isCoverCropped,
    this.backdropUrl,
    required this.code,
    this.releaseDate,
    this.length,
    this.videoFilePaths,
    this.isFavorite,
    this.lastWatchPosition,
    this.lastWatchedAt,
    this.playCount,
    this.translatedName,
    this.translatedTags,
    this.translatedPlot,
    this.samples,
    this.magnets,
    this.director,
    this.producer,
    this.publisher,
    this.series,
    this.subtitleFilePaths,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    final movieInfo = json['movieInfo'] as Map<String, dynamic>? ?? {};

    return Movie(
      id: json['id'].toString(),
      name: json['name'] as String,
      path: json['path'] as String?,
      size: (json['size'] as num?)?.toDouble(),
      createdAt: _parseDateTimeToInt(json['createdAt'] as String?),
      cast: (json['cast'] as List<dynamic>?)
              ?.map((e) => Cast.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tags: (json['tags'] as List<dynamic>?)?.map((e) {
        if (e is Map<String, dynamic>) {
          return NamedItem(
            id: e['id'] as String? ?? '',
            name: e['name'] as String? ?? '',
          );
        } else {
          return NamedItem(
            id: '',
            name: e.toString(),
          );
        }
      }).toList(),
      coverUrl:
          (movieInfo['cover'] as String?) ?? (json['coverUrl'] as String?),
      backdropUrl: (movieInfo['backdrop'] as String?) ??
          (json['backdropUrl'] as String?),
      code: movieInfo['code'] as String? ?? '',
      releaseDate: movieInfo['releaseDate'] as String?,
      length: _parseLengthToMinutes(movieInfo['length'] as String?),
      subtitleFilePaths: (json['subtitleFilePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'createdAt': _intToIso8601(createdAt),
      'cast': cast.map((e) => e.toJson()).toList(),
      'tags': tags?.map((e) => {'id': e.id, 'name': e.name}).toList(),
      'coverUrl': coverUrl,
      'backdropUrl': backdropUrl,
      'movieInfo': {
        'cover': coverUrl,
        'backdrop': backdropUrl,
        'code': code,
        'releaseDate': releaseDate,
        'length': _minutesToLengthString(length ?? 0),
      },
      'videoFilePaths': videoFilePaths,
      'subtitleFilePaths': subtitleFilePaths,
      'isFavorite': isFavorite ?? false,
      'lastWatchPosition': lastWatchPosition ?? 0.0,
      'lastWatchedAt': _intToIso8601(lastWatchedAt),
      'playCount': playCount ?? 0,
    };
  }

  Movie copyWith({
    String? id,
    String? name,
    String? path,
    double? size,
    int? createdAt,
    List<Cast>? cast,
    List<NamedItem>? tags,
    String? coverUrl,
    String? originalCoverUrl,
    bool? isCoverCropped,
    String? backdropUrl,
    String? code,
    String? releaseDate,
    int? length,
    List<String>? videoFilePaths,
    bool? isFavorite,
    double? lastWatchPosition,
    int? lastWatchedAt,
    int? playCount,
    String? translatedName,
    List<String>? translatedTags,
    String? translatedPlot,
    List<SampleInfo>? samples,
    List<MagnetInfo>? magnets,
    NamedItem? director,
    NamedItem? producer,
    NamedItem? publisher,
    NamedItem? series,
    List<String>? subtitleFilePaths,
    bool clearTranslated = false,
  }) {
    return Movie(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      cast: cast ?? this.cast,
      tags: tags ?? this.tags,
      coverUrl: coverUrl ?? this.coverUrl,
      originalCoverUrl: originalCoverUrl ?? this.originalCoverUrl,
      isCoverCropped: isCoverCropped ?? this.isCoverCropped,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      code: code ?? this.code,
      releaseDate: releaseDate ?? this.releaseDate,
      length: length ?? this.length,
      videoFilePaths: videoFilePaths ?? this.videoFilePaths,
      isFavorite: isFavorite ?? this.isFavorite,
      lastWatchPosition: lastWatchPosition ?? this.lastWatchPosition,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      playCount: playCount ?? this.playCount,
      translatedName:
          clearTranslated ? null : (translatedName ?? this.translatedName),
      translatedTags:
          clearTranslated ? null : (translatedTags ?? this.translatedTags),
      translatedPlot:
          clearTranslated ? null : (translatedPlot ?? this.translatedPlot),
      samples: samples ?? this.samples,
      magnets: magnets ?? this.magnets,
      director: director ?? this.director,
      producer: producer ?? this.producer,
      publisher: publisher ?? this.publisher,
      series: series ?? this.series,
      subtitleFilePaths: subtitleFilePaths ?? this.subtitleFilePaths,
    );
  }

  // 便捷 getters 用于处理 null 值
  bool get safeIsCoverCropped => isCoverCropped ?? false;
  int get safeLength => length ?? 0;
  bool get safeIsFavorite => isFavorite ?? false;
  double get safeLastWatchPosition => lastWatchPosition ?? 0.0;
  int get safeLastWatchedAt => lastWatchedAt ?? 0;
  int get safePlayCount => playCount ?? 0;

  // Helper methods
  static int _parseDateTimeToInt(String? dateTimeStr) {
    if (dateTimeStr == null) return DateTime.now().millisecondsSinceEpoch;
    try {
      return DateTime.parse(dateTimeStr).millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  static String _intToIso8601(int? milliseconds) {
    if (milliseconds == null) return '';
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds)
          .toIso8601String();
    } catch (_) {
      return '';
    }
  }

  static int _parseLengthToMinutes(String? lengthStr) {
    if (lengthStr == null) return 0;
    try {
      // Handle formats like "120" or "120 min" or "2:00:00"
      final cleanStr = lengthStr.replaceAll(RegExp(r'[^0-9:]'), '');
      if (cleanStr.contains(':')) {
        final parts = cleanStr.split(':');
        if (parts.length == 3) {
          return int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
        } else if (parts.length == 2) {
          return int.tryParse(parts[0])!;
        }
      }
      return int.tryParse(cleanStr) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _minutesToLengthString(int minutes) {
    return '$minutes 分钟';
  }

  DateTime? get createdAtDateTime =>
      createdAt > 0 ? DateTime.fromMillisecondsSinceEpoch(createdAt) : null;

  DateTime? get lastWatchedAtDateTime => safeLastWatchedAt > 0
      ? DateTime.fromMillisecondsSinceEpoch(safeLastWatchedAt)
      : null;
}

/// 预览图信息类
@HiveType(typeId: 6)
class SampleInfo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String src;

  @HiveField(2)
  final String thumbnail;

  @HiveField(3)
  final String alt;

  SampleInfo({
    required this.id,
    required this.src,
    required this.thumbnail,
    required this.alt,
  });

  factory SampleInfo.fromJson(Map<String, dynamic> json) {
    return SampleInfo(
      id: json['id'] as String? ?? '',
      src: json['src'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      alt: json['alt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'src': src,
      'thumbnail': thumbnail,
      'alt': alt,
    };
  }
}

/// 磁力链接信息类
@HiveType(typeId: 7)
class MagnetInfo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String link;

  @HiveField(2)
  final bool isHD;

  @HiveField(3)
  final String title;

  @HiveField(4)
  final String size;

  @HiveField(5)
  final int numberSize;

  @HiveField(6)
  final String shareDate;

  @HiveField(7)
  final bool hasSubtitle;

  MagnetInfo({
    required this.id,
    required this.link,
    required this.isHD,
    required this.title,
    required this.size,
    required this.numberSize,
    required this.shareDate,
    required this.hasSubtitle,
  });

  factory MagnetInfo.fromJson(Map<String, dynamic> json) {
    return MagnetInfo(
      id: json['id'] as String? ?? '',
      link: json['link'] as String? ?? '',
      isHD: json['isHD'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      size: json['size'] as String? ?? '',
      numberSize: json['numberSize'] as int? ?? 0,
      shareDate: json['shareDate'] as String? ?? '',
      hasSubtitle: json['hasSubtitle'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'link': link,
      'isHD': isHD,
      'title': title,
      'size': size,
      'numberSize': numberSize,
      'shareDate': shareDate,
      'hasSubtitle': hasSubtitle,
    };
  }
}
