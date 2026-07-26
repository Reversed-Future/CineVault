import 'package:hive/hive.dart';

part 'custom_movie_tag.g.dart';

@HiveType(typeId: 10)
class CustomMovieTag extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int createdAt;

  CustomMovieTag({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  CustomMovieTag copyWith({
    String? id,
    String? name,
    int? createdAt,
  }) {
    return CustomMovieTag(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

@HiveType(typeId: 11)
class MovieCustomTagLink extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String movieId;

  @HiveField(2)
  final String tagId;

  @HiveField(3)
  final int createdAt;

  MovieCustomTagLink({
    required this.id,
    required this.movieId,
    required this.tagId,
    required this.createdAt,
  });
}
