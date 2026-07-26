import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tmdb_models.dart';
import '../providers/tmdb_provider.dart';
import '../widgets/smart_image.dart';
import 'tmdb_config_screen.dart';
import 'tmdb_movie_detail_screen.dart';

class TmdbSearchScreen extends ConsumerStatefulWidget {
  final String? initialKeyword;
  final TmdbMovieListFilter? initialFilter;

  const TmdbSearchScreen({
    super.key,
    this.initialKeyword,
    this.initialFilter,
  });

  @override
  ConsumerState<TmdbSearchScreen> createState() => _TmdbSearchScreenState();
}

class _TmdbSearchScreenState extends ConsumerState<TmdbSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loadedInitial = false;

  @override
  void initState() {
    super.initState();
    _searchController.text =
        widget.initialFilter?.label ?? widget.initialKeyword ?? '';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _yearController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(tmdbSearchProvider.notifier).loadMore();
    }
  }

  Future<void> _loadInitialIfNeeded(TmdbConfig config) async {
    if (_loadedInitial || !config.isConfigured) return;
    _loadedInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final movieFilter = widget.initialFilter;
      if (movieFilter != null && movieFilter.isValid) {
        ref.read(tmdbSearchProvider.notifier).loadByFilter(movieFilter);
        return;
      }

      final keyword = _searchController.text.trim();
      if (keyword.isEmpty) {
        ref.read(tmdbSearchProvider.notifier).loadPopular(page: 1);
      } else {
        ref.read(tmdbSearchProvider.notifier).search(keyword, page: 1);
      }
    });
  }

  Future<void> _handleSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      await ref.read(tmdbSearchProvider.notifier).loadPopular(page: 1);
      return;
    }
    await ref.read(tmdbSearchProvider.notifier).search(
          keyword,
          year: _yearController.text.trim(),
          page: 1,
        );
  }

  void _clearSearch() {
    _searchController.clear();
    _yearController.clear();
    ref.read(tmdbSearchProvider.notifier).clear();
    ref.read(tmdbSearchProvider.notifier).loadPopular(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(tmdbConfigProvider);
    final state = ref.watch(tmdbSearchProvider);
    _loadInitialIfNeeded(config);

    if (!config.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('TMDB')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings, size: 56),
              const SizedBox(height: 12),
              const Text('请先配置 TMDB 访问凭据'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TmdbConfigScreen(),
                  ),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('打开配置'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            state.movieFilter?.title ?? widget.initialFilter?.title ?? 'TMDB'),
        actions: [
          IconButton(
            tooltip: '配置',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TmdbConfigScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (state.movieFilter != null) _buildFilterBanner(state.movieFilter!),
          Expanded(child: _buildMovieGrid(state)),
        ],
      ),
    );
  }

  Widget _buildFilterBanner(TmdbMovieListFilter movieFilter) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${movieFilter.title}  ·  ID: ${movieFilter.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索电影标题',
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      ),
              ),
              onSubmitted: (_) => _handleSearch(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _yearController,
              decoration: const InputDecoration(
                hintText: '年份',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _handleSearch(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _handleSearch,
            icon: const Icon(Icons.search),
            label: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieGrid(TmdbSearchState state) {
    if (state.isLoading && state.movies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _handleSearch,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.movies.isEmpty) {
      return const Center(child: Text('暂无电影数据'));
    }

    return RefreshIndicator(
      onRefresh: () {
        if (state.movieFilter != null) {
          return ref
              .read(tmdbSearchProvider.notifier)
              .loadByFilter(state.movieFilter!, page: 1);
        }

        final keyword = state.keyword?.trim() ?? '';
        if (keyword.isEmpty) {
          return ref.read(tmdbSearchProvider.notifier).loadPopular(page: 1);
        }
        return ref.read(tmdbSearchProvider.notifier).search(
              keyword,
              year: state.year,
              page: 1,
            );
      },
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: state.movies.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.movies.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _MovieCard(movie: state.movies[index]);
        },
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  final TmdbMovie movie;

  const _MovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TmdbMovieDetailScreen(movieId: movie.id),
        ),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: movie.img.isEmpty
                  ? const Center(child: Icon(Icons.movie, size: 44))
                  : SmartImage(
                      url: movie.img,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [movie.date, 'TMDB ${movie.id}']
                        .where((text) => text.isNotEmpty)
                        .join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
