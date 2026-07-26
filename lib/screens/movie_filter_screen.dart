import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movie.dart';
import '../providers/movie_providers.dart';
import '../providers/tmdb_provider.dart';
import '../services/database_service.dart';
import '../services/tmdb_api_service.dart';
import '../widgets/movie_card.dart';
import 'movie_detail_screen.dart';
import 'tmdb_search_screen.dart';

enum MovieFilterType {
  cast,
  tag,
  director,
  producer,
  publisher,
  series,
  customTag,
}

class MovieFilterScreen extends ConsumerStatefulWidget {
  final MovieFilterType filterType;
  final String filterValue;
  final String? filterId;

  const MovieFilterScreen({
    super.key,
    required this.filterType,
    required this.filterValue,
    this.filterId,
  });

  @override
  ConsumerState<MovieFilterScreen> createState() => _MovieFilterScreenState();
}

class _MovieFilterScreenState extends ConsumerState<MovieFilterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchKeyword = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moviesAsync = ref.watch(moviesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: '打开 TMDB 搜索',
            icon: const Icon(Icons.manage_search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TmdbSearchScreen(
                  initialKeyword: widget.filterValue,
                  initialFilter: _tmdbMovieListFilter,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索本地影片',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchKeyword.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.clear),
                        onPressed: _searchController.clear,
                      ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
          Expanded(
            child: moviesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('加载失败: $error')),
              data: (movies) {
                final filteredMovies = movies
                    .where(_matchesFilter)
                    .where((movie) =>
                        _searchKeyword.isEmpty || _matchesSearch(movie))
                    .toList();

                if (filteredMovies.isEmpty) {
                  return const Center(child: Text('暂无相关影片'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 24,
                  ),
                  itemCount: filteredMovies.length,
                  itemBuilder: (context, index) {
                    final movie = filteredMovies[index];
                    return MovieCard(
                      movie: movie,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MovieDetailScreen(movie: movie),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String get _title {
    switch (widget.filterType) {
      case MovieFilterType.cast:
        return '演员: ${widget.filterValue}';
      case MovieFilterType.tag:
        return '类型: ${widget.filterValue}';
      case MovieFilterType.director:
        return '导演: ${widget.filterValue}';
      case MovieFilterType.producer:
        return '制片: ${widget.filterValue}';
      case MovieFilterType.publisher:
        return '发行商: ${widget.filterValue}';
      case MovieFilterType.series:
        return '系列: ${widget.filterValue}';
      case MovieFilterType.customTag:
        return '自定义标签: ${widget.filterValue}';
    }
  }

  TmdbMovieListFilter? get _tmdbMovieListFilter {
    final id = widget.filterId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }

    final type = _tmdbFilterType;
    if (type == null) {
      return null;
    }

    return TmdbMovieListFilter(
      type: type,
      id: id,
      label: widget.filterValue,
    );
  }

  TmdbFilterType? get _tmdbFilterType {
    switch (widget.filterType) {
      case MovieFilterType.cast:
        return TmdbFilterType.cast;
      case MovieFilterType.tag:
        return TmdbFilterType.genre;
      case MovieFilterType.director:
        return TmdbFilterType.director;
      case MovieFilterType.producer:
        return TmdbFilterType.producer;
      case MovieFilterType.publisher:
        return TmdbFilterType.company;
      case MovieFilterType.series:
        return TmdbFilterType.collection;
      case MovieFilterType.customTag:
        return null;
    }
  }

  bool _matchesFilter(Movie movie) {
    bool byId(String id) =>
        widget.filterId != null &&
        widget.filterId!.isNotEmpty &&
        id == widget.filterId;
    bool byName(String name) => name == widget.filterValue;

    switch (widget.filterType) {
      case MovieFilterType.cast:
        return movie.cast.any((cast) => byId(cast.id) || byName(cast.name));
      case MovieFilterType.tag:
        return movie.tags?.any((tag) => byId(tag.id) || byName(tag.name)) ??
            false;
      case MovieFilterType.director:
        return movie.director != null &&
            (byId(movie.director!.id) || byName(movie.director!.name));
      case MovieFilterType.producer:
        return movie.producer != null &&
            (byId(movie.producer!.id) || byName(movie.producer!.name));
      case MovieFilterType.publisher:
        return movie.publisher != null &&
            (byId(movie.publisher!.id) || byName(movie.publisher!.name));
      case MovieFilterType.series:
        return movie.series != null &&
            (byId(movie.series!.id) || byName(movie.series!.name));
      case MovieFilterType.customTag:
        final tagIds = DatabaseService.getCustomTagIdsForMovie(movie.id);
        if (widget.filterId != null &&
            widget.filterId!.isNotEmpty &&
            tagIds.contains(widget.filterId)) {
          return true;
        }
        return DatabaseService.getCustomTagsForMovie(movie.id)
            .any((tag) => byId(tag.id) || byName(tag.name));
    }
  }

  bool _matchesSearch(Movie movie) {
    final keyword = _searchKeyword;
    return movie.id.toLowerCase().contains(keyword) ||
        movie.code.toLowerCase().contains(keyword) ||
        movie.name.toLowerCase().contains(keyword) ||
        (movie.translatedName?.toLowerCase().contains(keyword) ?? false);
  }
}
