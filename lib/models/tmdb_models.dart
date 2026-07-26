import 'package:flutter/foundation.dart';

@immutable
class TmdbMovie {
  final String id;
  final String title;
  final String img;
  final String date;
  final List<String> tags;
  final String? overview;
  final String? backdropUrl;
  final double? voteAverage;

  const TmdbMovie({
    required this.id,
    required this.title,
    required this.img,
    required this.date,
    required this.tags,
    this.overview,
    this.backdropUrl,
    this.voteAverage,
  });

  factory TmdbMovie.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
    required String posterSize,
    required String backdropSize,
    Map<int, String> genreNames = const {},
  }) {
    final genreIds = (json['genre_ids'] as List<dynamic>? ?? const [])
        .whereType<int>()
        .toList();
    final title = _readString(json['title']).isNotEmpty
        ? _readString(json['title'])
        : _readString(json['name']);

    return TmdbMovie(
      id: _readString(json['id']),
      title: title,
      img:
          _buildImageUrl(imageBaseUrl, posterSize, _readString(json['poster_path'])) ?? '',
      date: _readString(json['release_date']),
      tags: genreIds
          .map((id) => genreNames[id] ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      overview: _readNullableString(json['overview']),
      backdropUrl:
          _buildImageUrl(imageBaseUrl, backdropSize, _readString(json['backdrop_path'])),
      voteAverage: _readDouble(json['vote_average']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'img': img,
      'date': date,
      'tags': tags,
      'overview': overview,
      'backdropUrl': backdropUrl,
      'voteAverage': voteAverage,
    };
  }
}

@immutable
class TmdbMovieDetail {
  final String id;
  final String title;
  final String? img;
  final ImageSize? imageSize;
  final String? date;
  final int? videoLength;
  final Person? director;
  final Person? producer;
  final Person? publisher;
  final Person? series;
  final List<Genre> genres;
  final List<Star> stars;
  final List<Sample> samples;
  final List<TmdbMovie> similarMovies;
  final String? overview;
  final String? backdropUrl;
  final String? imdbId;
  final String? originalTitle;
  final String? tagline;
  final double? voteAverage;
  final String? gid;
  final String? uc;

  const TmdbMovieDetail({
    required this.id,
    required this.title,
    this.img,
    this.imageSize,
    this.date,
    this.videoLength,
    this.director,
    this.producer,
    this.publisher,
    this.series,
    required this.genres,
    required this.stars,
    required this.samples,
    required this.similarMovies,
    this.overview,
    this.backdropUrl,
    this.imdbId,
    this.originalTitle,
    this.tagline,
    this.voteAverage,
    this.gid,
    this.uc,
  });

  factory TmdbMovieDetail.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
    required String posterSize,
    required String backdropSize,
    required String profileSize,
  }) {
    final credits = json['credits'] as Map<String, dynamic>? ?? const {};
    final crew = (credits['crew'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final cast = (credits['cast'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(12)
        .map((json) => Star.fromJson(
              json,
              imageBaseUrl: imageBaseUrl,
              profileSize: profileSize,
            ))
        .where((star) => star.name.isNotEmpty)
        .toList();

    final productionCompanies =
        (json['production_companies'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
    final collection = json['belongs_to_collection'] as Map<String, dynamic>?;
    final recommendations = json['recommendations'] as Map<String, dynamic>?;
    final externalIds = json['external_ids'] as Map<String, dynamic>?;

    return TmdbMovieDetail(
      id: _readString(json['id']),
      title: _readString(json['title']),
      img: _buildImageUrl(imageBaseUrl, posterSize, _readString(json['poster_path'])),
      imageSize: const ImageSize(width: 0, height: 0),
      date: _readNullableString(json['release_date']),
      videoLength: _readInt(json['runtime']),
      director: _firstCrewPerson(crew, 'Director'),
      producer: _firstCrewPerson(crew, 'Producer'),
      publisher: productionCompanies.isNotEmpty
          ? Person.fromJson(productionCompanies.first)
          : null,
      series: collection == null ? null : Person.fromJson(collection),
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Genre.fromJson)
          .where((genre) => genre.name.isNotEmpty)
          .toList(),
      stars: cast,
      samples: _readSamples(
        json,
        imageBaseUrl: imageBaseUrl,
        backdropSize: backdropSize,
      ),
      similarMovies: (recommendations?['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((json) => json['adult'] != true)
          .take(12)
          .map((json) => TmdbMovie.fromJson(
                json,
                imageBaseUrl: imageBaseUrl,
                posterSize: posterSize,
                backdropSize: backdropSize,
              ))
          .toList(),
      overview: _readNullableString(json['overview']),
      backdropUrl:
          _buildImageUrl(imageBaseUrl, backdropSize, _readString(json['backdrop_path'])),
      imdbId: _readNullableString(externalIds?['imdb_id']),
      originalTitle: _readNullableString(json['original_title']),
      tagline: _readNullableString(json['tagline']),
      voteAverage: _readDouble(json['vote_average']),
    );
  }
}

@immutable
class ImageSize {
  final int width;
  final int height;

  const ImageSize({required this.width, required this.height});
}

@immutable
class Person {
  final String id;
  final String name;

  const Person({required this.id, required this.name});

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: _readString(json['id']),
      name: _readString(json['name']),
    );
  }
}

@immutable
class Genre {
  final String id;
  final String name;

  const Genre({required this.id, required this.name});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: _readString(json['id']),
      name: _readString(json['name']),
    );
  }
}

@immutable
class Star {
  final String id;
  final String name;
  final String? avatar;
  final String? character;

  const Star({
    required this.id,
    required this.name,
    this.avatar,
    this.character,
  });

  factory Star.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
    required String profileSize,
  }) {
    return Star(
      id: _readString(json['id']),
      name: _readString(json['name']),
      avatar:
          _buildImageUrl(imageBaseUrl, profileSize, _readString(json['profile_path'])),
      character: _readNullableString(json['character']),
    );
  }
}

@immutable
class Sample {
  final String alt;
  final String id;
  final String src;
  final String thumbnail;

  const Sample({
    required this.alt,
    required this.id,
    required this.src,
    required this.thumbnail,
  });
}

@immutable
class Magnet {
  final String id;
  final String link;
  final bool isHD;
  final String title;
  final String size;
  final int numberSize;
  final String shareDate;
  final bool hasSubtitle;

  const Magnet({
    required this.id,
    required this.link,
    required this.isHD,
    required this.title,
    required this.size,
    required this.numberSize,
    required this.shareDate,
    required this.hasSubtitle,
  });
}

@immutable
class Pagination {
  final int currentPage;
  final bool hasNextPage;
  final int? nextPage;
  final List<int> pages;

  const Pagination({
    required this.currentPage,
    required this.hasNextPage,
    this.nextPage,
    required this.pages,
  });

  factory Pagination.fromTmdbJson(Map<String, dynamic> json) {
    final currentPage = _readInt(json['page']) ?? 1;
    final totalPages = _readInt(json['total_pages']) ?? currentPage;
    final visibleLastPage = totalPages > 10 ? 10 : totalPages;

    return Pagination(
      currentPage: currentPage,
      hasNextPage: currentPage < totalPages,
      nextPage: currentPage < totalPages ? currentPage + 1 : null,
      pages: List<int>.generate(visibleLastPage, (index) => index + 1),
    );
  }
}

@immutable
class MovieListResponse {
  final List<TmdbMovie> movies;
  final Pagination pagination;

  const MovieListResponse({
    required this.movies,
    required this.pagination,
  });

  factory MovieListResponse.fromTmdbJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
    required String posterSize,
    required String backdropSize,
    Map<int, String> genreNames = const {},
  }) {
    return MovieListResponse(
      movies: (json['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((json) => json['adult'] != true)
          .map((json) => TmdbMovie.fromJson(
                json,
                imageBaseUrl: imageBaseUrl,
                posterSize: posterSize,
                backdropSize: backdropSize,
                genreNames: genreNames,
              ))
          .toList(),
      pagination: Pagination.fromTmdbJson(json),
    );
  }
}

@immutable
class SearchResponse {
  final List<TmdbMovie> movies;
  final Pagination pagination;
  final String keyword;

  const SearchResponse({
    required this.movies,
    required this.pagination,
    required this.keyword,
  });

  factory SearchResponse.fromTmdbJson(
    Map<String, dynamic> json, {
    required String keyword,
    required String imageBaseUrl,
    required String posterSize,
    required String backdropSize,
    Map<int, String> genreNames = const {},
  }) {
    final list = MovieListResponse.fromTmdbJson(
      json,
      imageBaseUrl: imageBaseUrl,
      posterSize: posterSize,
      backdropSize: backdropSize,
      genreNames: genreNames,
    );

    return SearchResponse(
      movies: list.movies,
      pagination: list.pagination,
      keyword: keyword,
    );
  }
}

Person? _firstCrewPerson(List<Map<String, dynamic>> crew, String job) {
  for (final item in crew) {
    if (_readString(item['job']) == job) {
      return Person.fromJson(item);
    }
  }
  return null;
}

List<Sample> _readSamples(
  Map<String, dynamic> json, {
  required String imageBaseUrl,
  required String backdropSize,
}) {
  final images = json['images'] as Map<String, dynamic>?;
  final backdrops = (images?['backdrops'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .take(12)
      .toList();

  return backdrops.map((item) {
    final path = _readString(item['file_path']);
    final url = _buildImageUrl(imageBaseUrl, backdropSize, path) ?? '';
    return Sample(
      id: path,
      alt: _readString(json['title']),
      src: url,
      thumbnail: url,
    );
  }).toList();
}

String? _buildImageUrl(String baseUrl, String size, String path) {
  if (path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
  return '$normalizedBase$size/$normalizedPath';
}

String _readString(Object? value) {
  if (value == null) return '';
  return value.toString();
}

String? _readNullableString(Object? value) {
  final text = _readString(value).trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _readDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
