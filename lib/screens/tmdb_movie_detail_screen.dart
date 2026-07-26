import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tmdb_models.dart';
import '../providers/movie_providers.dart';
import '../providers/tmdb_provider.dart';
import '../services/movie_sync_adapter.dart';
import '../widgets/smart_image.dart';

class TmdbMovieDetailScreen extends ConsumerStatefulWidget {
  final String movieId;

  const TmdbMovieDetailScreen({super.key, required this.movieId});

  @override
  ConsumerState<TmdbMovieDetailScreen> createState() =>
      _TmdbMovieDetailScreenState();
}

class _TmdbMovieDetailScreenState extends ConsumerState<TmdbMovieDetailScreen> {
  bool _isSaving = false;
  bool _savedSuccessfully = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tmdbMovieDetailProvider.notifier).loadMovieDetail(widget.movieId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tmdbMovieDetailProvider);

    if (state.isLoading && state.movie == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载中')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && state.movie == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载失败')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref
                      .read(tmdbMovieDetailProvider.notifier)
                      .loadMovieDetail(widget.movieId),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final movie = state.movie!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 360,
            title: Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(movie),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(movie),
                  const SizedBox(height: 18),
                  _buildSaveButton(movie),
                  const SizedBox(height: 24),
                  _buildOverview(movie),
                  _buildInfo(movie),
                  _buildGenres(movie),
                  _buildCast(movie),
                  _buildImages(movie),
                  _buildSimilar(movie),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TmdbMovieDetail movie) {
    final imageUrl = movie.backdropUrl ?? movie.img;
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.movie, size: 72)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        SmartImage(
          url: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(20),
                Colors.black.withAlpha(170),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(TmdbMovieDetail movie) {
    final meta = <String>[
      if (movie.date?.isNotEmpty == true) movie.date!,
      if ((movie.videoLength ?? 0) > 0) '${movie.videoLength} 分钟',
      if (movie.voteAverage != null) '评分 ${movie.voteAverage!.toStringAsFixed(1)}',
      'TMDB ${movie.id}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          movie.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (movie.originalTitle != null && movie.originalTitle != movie.title)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              movie.originalTitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          meta.join('  ·  '),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(TmdbMovieDetail movie) {
    final existsLocally = MovieSyncAdapter.existsLocally(movie.id);
    if (_savedSuccessfully) {
      return Row(
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('已保存到本地片库'),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: _isSaving ? null : () => _saveToLocal(movie),
      icon: _isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save),
      label: Text(existsLocally ? '更新本地资料' : '保存到本地片库'),
    );
  }

  Future<void> _saveToLocal(TmdbMovieDetail movie) async {
    setState(() {
      _isSaving = true;
      _savedSuccessfully = false;
    });

    try {
      final success = await MovieSyncAdapter.saveToLocal(movie);
      if (!mounted) return;
      if (success) {
        setState(() {
          _savedSuccessfully = true;
        });
        ref.invalidate(moviesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('电影资料已保存')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildOverview(TmdbMovieDetail movie) {
    if (movie.overview == null || movie.overview!.isEmpty) {
      return const SizedBox.shrink();
    }
    return _Section(
      title: '简介',
      icon: Icons.subject,
      child: Text(movie.overview!),
    );
  }

  Widget _buildInfo(TmdbMovieDetail movie) {
    final rows = <Widget>[
      if (movie.director != null) _InfoRow(label: '导演', value: movie.director!.name),
      if (movie.producer != null) _InfoRow(label: '制片', value: movie.producer!.name),
      if (movie.publisher != null)
        _InfoRow(label: '制作公司', value: movie.publisher!.name),
      if (movie.series != null) _InfoRow(label: '系列', value: movie.series!.name),
      if (movie.imdbId != null) _InfoRow(label: 'IMDb', value: movie.imdbId!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: '资料',
      icon: Icons.info_outline,
      child: Column(children: rows),
    );
  }

  Widget _buildGenres(TmdbMovieDetail movie) {
    if (movie.genres.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: '类型',
      icon: Icons.local_offer_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: movie.genres
            .map((genre) => Chip(label: Text(genre.name)))
            .toList(),
      ),
    );
  }

  Widget _buildCast(TmdbMovieDetail movie) {
    if (movie.stars.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: '演职员',
      icon: Icons.groups_outlined,
      child: SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: movie.stars.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final person = movie.stars[index];
            return SizedBox(
              width: 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: person.avatar == null || person.avatar!.isEmpty
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Center(child: Icon(Icons.person)),
                            )
                          : SmartImage(
                              url: person.avatar!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (person.character?.isNotEmpty == true)
                    Text(
                      person.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildImages(TmdbMovieDetail movie) {
    if (movie.samples.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: '剧照',
      icon: Icons.photo_library_outlined,
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: movie.samples.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final sample = movie.samples[index];
            return InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ImageGallery(
                    samples: movie.samples,
                    initialIndex: index,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SmartImage(
                  url: sample.thumbnail,
                  width: 230,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSimilar(TmdbMovieDetail movie) {
    if (movie.similarMovies.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: '相似电影',
      icon: Icons.movie_filter_outlined,
      child: SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: movie.similarMovies.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = movie.similarMovies[index];
            return InkWell(
              onTap: () {
                ref.read(tmdbMovieDetailProvider.notifier).clear();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TmdbMovieDetailScreen(movieId: item.id),
                  ),
                );
              },
              child: SizedBox(
                width: 135,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.img.isEmpty
                            ? const Center(child: Icon(Icons.movie))
                            : SmartImage(
                                url: item.img,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ImageGallery extends StatefulWidget {
  final List<Sample> samples;
  final int initialIndex;

  const _ImageGallery({
    required this.samples,
    required this.initialIndex,
  });

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.samples.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.samples.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: SmartImage(
                url: widget.samples[index].src,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
