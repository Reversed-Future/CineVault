import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/movie.dart';
import '../services/local_asset_manager_service.dart';
import '../services/database_service.dart';
import '../providers/movie_providers.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  List<Movie> _importCandidates = [];
  Set<String> _selectedIds = {};
  bool _isLoading = false;
  String? _assetsJsonPath;

  @override
  void initState() {
    super.initState();
    _autoDetectAssets();
  }

  Future<void> _autoDetectAssets() async {
    final autoPath = LocalAssetManagerService.findLocalAssetManagerPath();
    if (autoPath != null) {
      final assetsJsonPath = path.join(autoPath, 'assets.json');
      if (File(assetsJsonPath).existsSync()) {
        setState(() {
          _assetsJsonPath = assetsJsonPath;
        });
        await _loadAssets(assetsJsonPath);
      }
    }
  }

  Future<void> _pickAssetsJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _assetsJsonPath = result.files.single.path;
      });
      await _loadAssets(result.files.single.path!);
    }
  }

  Future<void> _loadAssets(String filePath) async {
    setState(() {
      _isLoading = true;
      _importCandidates = [];
      _selectedIds = {};
    });

    try {
      final movies = await LocalAssetManagerService.importMovies(filePath);
      
      final existingMovies = DatabaseService.getAllMovies();
      final existingIds = existingMovies.map((m) => m.id).toSet();
      
      final newMovies = movies.where((m) => !existingIds.contains(m.id)).toList();
      
      setState(() {
        _importCandidates = newMovies;
        _selectedIds = newMovies.map((m) => m.id).toSet();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _importSelected() async {
    if (_selectedIds.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final moviesToImport = _importCandidates
          .where((m) => _selectedIds.contains(m.id))
          .toList();

      await DatabaseService.addMovies(moviesToImport);
      
      if (mounted) {
        ref.refresh(moviesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入 ${moviesToImport.length} 部影片'),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleSelectAll(bool? value) {
    if (value == true) {
      setState(() {
        _selectedIds = _importCandidates.map((m) => m.id).toSet();
      });
    } else {
      setState(() {
        _selectedIds = {};
      });
    }
  }

  void _toggleMovie(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('导入影片'),
        actions: [
          if (_importCandidates.isNotEmpty)
            TextButton.icon(
              onPressed: _isLoading ? null : _importSelected,
              icon: const Icon(Icons.download),
              label: Text('导入 ${_selectedIds.length} 项'),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_importCandidates.isNotEmpty)
            _buildSelectAllBar(),
          Expanded(
            child: _isLoading && _importCandidates.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _importCandidates.isEmpty
                    ? _buildEmptyState()
                    : _buildMovieList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '从 Local Asset Manager 导入',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '选择 assets.json 文件以导入影片元数据',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            if (_assetsJsonPath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _assetsJsonPath!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickAssetsJson,
              icon: const Icon(Icons.folder_open),
              label: Text(_assetsJsonPath == null ? '选择文件' : '更换文件'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAllBar() {
    final allSelected = _selectedIds.length == _importCandidates.length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: _toggleSelectAll,
          ),
          Text('全选 (${_importCandidates.length})'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '没有可导入的影片',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '选择 assets.json 文件开始导入，或所有影片都已导入',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMovieList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _importCandidates.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final movie = _importCandidates[index];
        final isSelected = _selectedIds.contains(movie.id);
        
        return ListTile(
          leading: Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleMovie(movie.id),
          ),
          title: Text(movie.name),
          subtitle: Text(
            movie.code.isNotEmpty ? movie.code : '无资料 ID',
          ),
          trailing: movie.cast.isNotEmpty
              ? Text(
                  movie.cast.map((c) => c.name).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          onTap: () => _toggleMovie(movie.id),
        );
      },
    );
  }
}
