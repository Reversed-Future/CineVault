import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/movie.dart';
import '../providers/translation_provider.dart';

class TranslationListScreen extends StatefulWidget {
  const TranslationListScreen({super.key});

  @override
  State<TranslationListScreen> createState() => _TranslationListScreenState();
}

class _TranslationListScreenState extends State<TranslationListScreen> {
  List<Movie> _movies = [];
  List<Movie> _filteredMovies = [];
  String _codeSearch = '';
  String _contentSearch = '';
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  String? _retranslatingMovieId;
  String _currentTranslationOutput = '';
  int _currentTokenCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
    });

    final allMovies = DatabaseService.getAllMovies();
    _movies = allMovies
        .where((m) => m.translatedName != null && m.translatedName!.isNotEmpty)
        .toList();
    _filteredMovies = List.from(_movies);

    setState(() {
      _isLoading = false;
    });
  }

  void _filterMovies() {
    if (_codeSearch.isEmpty && _contentSearch.isEmpty) {
      _filteredMovies = List.from(_movies);
    } else {
      _filteredMovies = _movies.where((movie) {
        final codeMatch = _codeSearch.isEmpty ||
            movie.code.toLowerCase().contains(_codeSearch.toLowerCase());

        final contentMatch = _contentSearch.isEmpty ||
            movie.name.toLowerCase().contains(_contentSearch.toLowerCase()) ||
            (movie.translatedName != null &&
                movie.translatedName!
                    .toLowerCase()
                    .contains(_contentSearch.toLowerCase()));

        return codeMatch && contentMatch;
      }).toList();
    }
    setState(() {});
  }

  Future<void> _retranslateMovie(Movie movie) async {
    if (_retranslatingMovieId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有翻译正在进行中，请稍候')),
      );
      return;
    }

    // 重置翻译状态
    setState(() {
      _retranslatingMovieId = movie.id;
      _currentTranslationOutput = '';
      _currentTokenCount = 0;
    });

    // 用于存储临时 token，等下一个事件循环更新 UI
    String pendingOutput = '';
    int pendingTokenCount = 0;
    Timer? uiRefreshTimer;

    try {
      final translationService = TranslationService();
      final translatedMovie = await translationService.translateMovie(
        movie,
        forceTranslate: true, // 强制重新翻译
        onToken: (token, index) {
          // 累积到临时变量，不立即更新 UI
          pendingOutput += token;
          pendingTokenCount = index;
        },
      );

      // 翻译完成后，最后一次更新 UI
      if (mounted) {
        setState(() {
          _currentTranslationOutput = pendingOutput;
          _currentTokenCount = pendingTokenCount;
        });
      }

      await DatabaseService.updateMovieWithLatest(
        movie.id,
        (latestMovie) => latestMovie.copyWith(
          translatedName: translatedMovie.translatedName,
          translatedTags: translatedMovie.translatedTags,
          translatedPlot: translatedMovie.translatedPlot,
        ),
      );

      if (mounted) {
        setState(() {
          _currentTranslationOutput = '';
          _currentTokenCount = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重新翻译成功: ${translatedMovie.translatedName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentTranslationOutput = '';
          _currentTokenCount = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重新翻译失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      uiRefreshTimer?.cancel();
      if (mounted) {
        setState(() {
          _retranslatingMovieId = null;
        });
        await _loadMovies();
      }
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.qr_code, color: Colors.blue),
              hintText: '搜索资料 ID',
              suffixIcon: _codeSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _codeSearch = '';
                        _filterMovies();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              _codeSearch = value;
              _filterMovies();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Colors.green),
              hintText: '搜索原文或译文内容',
              suffixIcon: _contentSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _contentSearch = '';
                        _filterMovies();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              _contentSearch = value;
              _filterMovies();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('没有找到匹配的翻译记录'),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(Movie movie, int index) {
    final hasTranslation =
        movie.translatedName != null && movie.translatedName!.isNotEmpty;
    final isTranslated = hasTranslation && movie.translatedName != movie.name;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (movie.code.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      movie.code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isTranslated
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isTranslated ? '已翻译' : '未翻译',
                    style: TextStyle(
                      color: isTranslated ? Colors.green : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '原文',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              movie.name,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                height: 1.5,
              ),
              softWrap: true,
            ),
            const SizedBox(height: 12),
            const Text(
              '译文',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              movie.translatedName ?? '-',
              style: TextStyle(
                fontSize: 14,
                color: isTranslated
                    ? const Color.fromRGBO(102, 102, 102, 1.0)
                    : Colors.black87,
                height: 1.5,
              ),
              softWrap: true,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_retranslatingMovieId == movie.id)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('正在翻译...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () => _retranslateMovie(movie),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新翻译'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_filteredMovies.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredMovies.length,
      itemBuilder: (context, index) {
        return _buildMovieCard(_filteredMovies[index], index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译列表'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                const Divider(height: 1),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 8,
                    radius: const Radius.circular(4),
                    child: _buildList(),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '共 ${_filteredMovies.length} 条翻译记录',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
