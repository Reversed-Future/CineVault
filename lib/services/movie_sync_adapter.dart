import '../models/cast.dart';
import '../models/movie.dart';
import '../models/named_item.dart';
import '../models/tmdb_models.dart';
import '../services/database_service.dart';

class MovieSyncAdapter {
  static Movie convertAndMerge(TmdbMovieDetail tmdbMovie) {
    final localMovie = DatabaseService.getMovie(tmdbMovie.id) ??
        DatabaseService.findMovieByCode(tmdbMovie.id);

    if (localMovie == null) {
      return _convertFromTmdb(tmdbMovie);
    }
    return _mergeMovies(localMovie, tmdbMovie);
  }

  static Movie _convertFromTmdb(TmdbMovieDetail tmdbMovie) {
    return Movie(
      id: tmdbMovie.id,
      name: tmdbMovie.title,
      path: null,
      size: null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      cast: _convertCast(tmdbMovie.stars),
      tags: _convertGenres(tmdbMovie.genres),
      coverUrl: tmdbMovie.img,
      backdropUrl: tmdbMovie.backdropUrl,
      code: tmdbMovie.id,
      releaseDate: tmdbMovie.date,
      length: tmdbMovie.videoLength ?? 0,
      videoFilePaths: null,
      isFavorite: false,
      lastWatchPosition: 0.0,
      lastWatchedAt: 0,
      playCount: 0,
      translatedName: null,
      translatedTags: null,
      translatedPlot: tmdbMovie.overview,
      samples: _convertSamples(tmdbMovie.samples),
      magnets: null,
      director: _convertPerson(tmdbMovie.director),
      producer: _convertPerson(tmdbMovie.producer),
      publisher: _convertPerson(tmdbMovie.publisher),
      series: _convertPerson(tmdbMovie.series),
    );
  }

  static Movie _mergeMovies(Movie localMovie, TmdbMovieDetail tmdbMovie) {
    return localMovie.copyWith(
      name: localMovie.name.isNotEmpty ? localMovie.name : tmdbMovie.title,
      coverUrl: tmdbMovie.img ?? localMovie.coverUrl,
      backdropUrl: tmdbMovie.backdropUrl ?? localMovie.backdropUrl,
      releaseDate: localMovie.releaseDate ?? tmdbMovie.date,
      length: localMovie.safeLength > 0
          ? localMovie.safeLength
          : (tmdbMovie.videoLength ?? 0),
      code: localMovie.code.isNotEmpty ? localMovie.code : tmdbMovie.id,
      cast: _mergeCast(localMovie.cast, tmdbMovie.stars),
      tags: _mergeGenres(localMovie.tags, tmdbMovie.genres),
      translatedPlot: localMovie.translatedPlot ?? tmdbMovie.overview,
      samples: localMovie.samples?.isNotEmpty == true
          ? localMovie.samples
          : _convertSamples(tmdbMovie.samples),
      director: localMovie.director ?? _convertPerson(tmdbMovie.director),
      producer: localMovie.producer ?? _convertPerson(tmdbMovie.producer),
      publisher: localMovie.publisher ?? _convertPerson(tmdbMovie.publisher),
      series: localMovie.series ?? _convertPerson(tmdbMovie.series),
    );
  }

  static List<Cast> _convertCast(List<Star> stars) {
    return stars
        .where((star) => star.id.isNotEmpty && star.name.isNotEmpty)
        .map((star) => Cast(
              id: star.id,
              name: star.name,
              imageUrl: star.avatar,
            ))
        .toList();
  }

  static List<Cast> _mergeCast(List<Cast> localCast, List<Star> tmdbCast) {
    final byId = <String, Cast>{
      for (final cast in localCast)
        if (cast.id.isNotEmpty) cast.id: cast,
    };

    for (final star in tmdbCast) {
      if (star.id.isEmpty || byId.containsKey(star.id)) continue;
      byId[star.id] = Cast(
        id: star.id,
        name: star.name,
        imageUrl: star.avatar,
      );
    }
    return byId.values.toList();
  }

  static List<NamedItem>? _convertGenres(List<Genre> genres) {
    if (genres.isEmpty) return null;
    return genres
        .where((genre) => genre.id.isNotEmpty && genre.name.isNotEmpty)
        .map((genre) => NamedItem(id: genre.id, name: genre.name))
        .toList();
  }

  static List<NamedItem>? _mergeGenres(
    List<NamedItem>? localTags,
    List<Genre> tmdbGenres,
  ) {
    final byId = <String, NamedItem>{};
    for (final tag in localTags ?? const <NamedItem>[]) {
      final key = tag.id.isNotEmpty ? tag.id : tag.name;
      if (key.isNotEmpty) byId[key] = tag;
    }
    for (final genre in tmdbGenres) {
      if (genre.id.isEmpty || byId.containsKey(genre.id)) continue;
      byId[genre.id] = NamedItem(id: genre.id, name: genre.name);
    }
    return byId.values.toList();
  }

  static NamedItem? _convertPerson(Person? person) {
    if (person == null || person.id.isEmpty || person.name.isEmpty) {
      return null;
    }
    return NamedItem(id: person.id, name: person.name);
  }

  static List<SampleInfo>? _convertSamples(List<Sample> samples) {
    if (samples.isEmpty) return null;
    return samples
        .where((sample) => sample.src.isNotEmpty)
        .map((sample) => SampleInfo(
              id: sample.id,
              src: sample.src,
              thumbnail: sample.thumbnail,
              alt: sample.alt,
            ))
        .toList();
  }

  static Future<bool> saveToLocal(TmdbMovieDetail tmdbMovie) async {
    try {
      final mergedMovie = convertAndMerge(tmdbMovie);
      await DatabaseService.addMovie(mergedMovie);
      return true;
    } catch (error) {
      print('[MovieSyncAdapter] Error saving movie: $error');
      return false;
    }
  }

  static bool existsLocally(String movieId) {
    return DatabaseService.getMovie(movieId) != null ||
        DatabaseService.findMovieByCode(movieId) != null;
  }

  static Movie? getLocalMovie(String movieId) {
    return DatabaseService.getMovie(movieId) ??
        DatabaseService.findMovieByCode(movieId);
  }
}
