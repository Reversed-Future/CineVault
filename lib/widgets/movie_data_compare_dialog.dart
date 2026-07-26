import 'package:flutter/material.dart';

import '../models/cast.dart';
import '../models/movie.dart';
import '../models/named_item.dart';
import '../models/tmdb_models.dart';
import '../services/image_cache_service.dart';
import 'smart_image.dart';

class MovieDataCompareDialog extends StatefulWidget {
  final Movie existingMovie;
  final TmdbMovieDetail newData;

  const MovieDataCompareDialog({
    super.key,
    required this.existingMovie,
    required this.newData,
  });

  @override
  State<MovieDataCompareDialog> createState() => _MovieDataCompareDialogState();
}

class _MovieDataCompareDialogState extends State<MovieDataCompareDialog> {
  bool _updateTitle = false;
  bool _updateCover = false;
  bool _updateDate = false;
  bool _updateLength = false;
  bool _updateDirector = false;
  bool _updateProducer = false;
  bool _updatePublisher = false;
  bool _updateSeries = false;
  bool _updateTags = false;
  bool _updateCast = false;
  bool _updateSamples = false;
  bool _updateOverview = false;

  @override
  void initState() {
    super.initState();
    _updateTitle = widget.existingMovie.name != widget.newData.title;
    _updateCover = widget.existingMovie.coverUrl != widget.newData.img ||
        widget.existingMovie.backdropUrl != widget.newData.backdropUrl;
    _updateDate = widget.existingMovie.releaseDate != widget.newData.date;
    _updateLength = widget.existingMovie.length != widget.newData.videoLength;
    _updateDirector =
        _personChanged(widget.existingMovie.director, widget.newData.director);
    _updateProducer =
        _personChanged(widget.existingMovie.producer, widget.newData.producer);
    _updatePublisher = _personChanged(
        widget.existingMovie.publisher, widget.newData.publisher);
    _updateSeries =
        _personChanged(widget.existingMovie.series, widget.newData.series);
    _updateTags =
        _tagsChanged(widget.existingMovie.tags, widget.newData.genres);
    _updateCast = _castChanged(widget.existingMovie.cast, widget.newData.stars);
    _updateSamples =
        _samplesChanged(widget.existingMovie.samples, widget.newData.samples);
    _updateOverview = widget.newData.overview != null &&
        widget.newData.overview!.isNotEmpty &&
        widget.existingMovie.translatedPlot != widget.newData.overview;
  }

  bool _personChanged(NamedItem? existing, Person? next) {
    if (existing == null && next == null) return false;
    if (existing == null || next == null) return true;
    return existing.id != next.id || existing.name != next.name;
  }

  bool _tagsChanged(List<NamedItem>? existing, List<Genre> next) {
    final existingList = existing ?? const <NamedItem>[];
    if (existingList.length != next.length) return true;
    for (var i = 0; i < existingList.length; i++) {
      if (existingList[i].id != next[i].id ||
          existingList[i].name != next[i].name) {
        return true;
      }
    }
    return false;
  }

  bool _castChanged(List<Cast> existing, List<Star> next) {
    if (existing.length != next.length) return true;
    for (var i = 0; i < existing.length; i++) {
      if (existing[i].id != next[i].id || existing[i].name != next[i].name) {
        return true;
      }
    }
    return false;
  }

  bool _samplesChanged(List<SampleInfo>? existing, List<Sample> next) {
    final existingList = existing ?? const <SampleInfo>[];
    if (existingList.length != next.length) return true;
    for (var i = 0; i < existingList.length; i++) {
      if (existingList[i].id != next[i].id) return true;
    }
    return false;
  }

  bool get _hasAnySelection =>
      _updateTitle ||
      _updateCover ||
      _updateDate ||
      _updateLength ||
      _updateDirector ||
      _updateProducer ||
      _updatePublisher ||
      _updateSeries ||
      _updateTags ||
      _updateCast ||
      _updateSamples ||
      _updateOverview;

  void _toggleAll(bool value) {
    setState(() {
      _updateTitle = value;
      _updateCover = value;
      _updateDate = value;
      _updateLength = value;
      _updateDirector = value;
      _updateProducer = value;
      _updatePublisher = value;
      _updateSeries = value;
      _updateTags = value;
      _updateCast = value;
      _updateSamples = value;
      _updateOverview = value;
    });
  }

  void _confirmUpdate() {
    Navigator.of(context).pop({
      'updateTitle': _updateTitle,
      'updateCover': _updateCover,
      'updateDate': _updateDate,
      'updateLength': _updateLength,
      'updateDirector': _updateDirector,
      'updateProducer': _updateProducer,
      'updatePublisher': _updatePublisher,
      'updateSeries': _updateSeries,
      'updateTags': _updateTags,
      'updateStars': _updateCast,
      'updateSamples': _updateSamples,
      'updateOverview': _updateOverview,
      'updateMagnets': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 8),
                  const Text(
                    '电影资料对比',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Checkbox(
                    value: _hasAnySelection,
                    onChanged: (value) => _toggleAll(value ?? false),
                  ),
                  const Text('全选'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCompareItem(
                    label: 'TMDB ID',
                    existing: Text(widget.existingMovie.code),
                    newData: Text(widget.newData.id),
                    selected: null,
                    onChanged: (_) {},
                  ),
                  _buildCompareItem(
                    label: '标题',
                    existing: Text(widget.existingMovie.name),
                    newData: Text(widget.newData.title),
                    selected: _updateTitle,
                    onChanged: (value) =>
                        setState(() => _updateTitle = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '封面',
                    existing: _coverMediaPreview(
                      widget.existingMovie.coverUrl,
                      widget.existingMovie.backdropUrl,
                      useCache: true,
                    ),
                    newData: _coverMediaPreview(
                      widget.newData.img,
                      widget.newData.backdropUrl,
                    ),
                    selected: _updateCover,
                    onChanged: (value) =>
                        setState(() => _updateCover = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '上映日期',
                    existing: Text(widget.existingMovie.releaseDate ?? '无'),
                    newData: Text(widget.newData.date ?? '无'),
                    selected: _updateDate,
                    onChanged: (value) =>
                        setState(() => _updateDate = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '片长',
                    existing: Text('${widget.existingMovie.length ?? 0} 分钟'),
                    newData: Text(widget.newData.videoLength == null
                        ? '无'
                        : '${widget.newData.videoLength} 分钟'),
                    selected: _updateLength,
                    onChanged: (value) =>
                        setState(() => _updateLength = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '导演',
                    existing: _namedItemPreview(widget.existingMovie.director),
                    newData: _personPreview(widget.newData.director),
                    selected: _updateDirector,
                    onChanged: (value) =>
                        setState(() => _updateDirector = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '制片',
                    existing: _namedItemPreview(widget.existingMovie.producer),
                    newData: _personPreview(widget.newData.producer),
                    selected: _updateProducer,
                    onChanged: (value) =>
                        setState(() => _updateProducer = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '制作公司',
                    existing: _namedItemPreview(widget.existingMovie.publisher),
                    newData: _personPreview(widget.newData.publisher),
                    selected: _updatePublisher,
                    onChanged: (value) =>
                        setState(() => _updatePublisher = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '系列',
                    existing: _namedItemPreview(widget.existingMovie.series),
                    newData: _personPreview(widget.newData.series),
                    selected: _updateSeries,
                    onChanged: (value) =>
                        setState(() => _updateSeries = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '类型',
                    existing: _namedItemsPreview(widget.existingMovie.tags),
                    newData: _genresPreview(widget.newData.genres),
                    selected: _updateTags,
                    onChanged: (value) =>
                        setState(() => _updateTags = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '演职员',
                    existing: _castPreview(widget.existingMovie.cast),
                    newData: _starsPreview(widget.newData.stars),
                    selected: _updateCast,
                    onChanged: (value) =>
                        setState(() => _updateCast = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '剧照',
                    existing: _sampleInfoPreview(widget.existingMovie.samples),
                    newData: _samplesPreview(widget.newData.samples),
                    selected: _updateSamples,
                    onChanged: (value) =>
                        setState(() => _updateSamples = value ?? false),
                  ),
                  _buildCompareItem(
                    label: '简介',
                    existing: Text(widget.existingMovie.translatedPlot ?? '无'),
                    newData: Text(widget.newData.overview ?? '无'),
                    selected: _updateOverview,
                    onChanged: (value) =>
                        setState(() => _updateOverview = value ?? false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _hasAnySelection ? _confirmUpdate : null,
                    child: const Text('确认更新'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareItem({
    required String label,
    required Widget existing,
    required Widget newData,
    required bool? selected,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            tristate: selected == null,
            onChanged: selected == null ? null : onChanged,
          ),
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: _CompareColumn(title: '本地', child: existing)),
          const SizedBox(width: 16),
          Expanded(child: _CompareColumn(title: 'TMDB', child: newData)),
        ],
      ),
    );
  }

  Widget _imagePreview(String? url, {bool useCache = false}) {
    if (url == null || url.isEmpty) return const Text('无');
    return SizedBox(
      height: 110,
      child: SmartImage(
        url: url,
        fit: BoxFit.contain,
        useCache: useCache,
        cacheCategory: CacheCategory.covers,
      ),
    );
  }

  Widget _coverMediaPreview(
    String? posterUrl,
    String? backdropUrl, {
    bool useCache = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('竖版海报'),
        _imagePreview(posterUrl, useCache: useCache),
        const SizedBox(height: 8),
        const Text('横版海报'),
        _imagePreview(backdropUrl, useCache: useCache),
      ],
    );
  }

  Widget _namedItemPreview(NamedItem? item) {
    if (item == null) return const Text('无');
    return Text('${item.name}\nID: ${item.id}');
  }

  Widget _personPreview(Person? person) {
    if (person == null) return const Text('无');
    return Text('${person.name}\nID: ${person.id}');
  }

  Widget _namedItemsPreview(List<NamedItem>? items) {
    final list = items ?? const <NamedItem>[];
    if (list.isEmpty) return const Text('无');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: list.map((item) => Chip(label: Text(item.name))).toList(),
    );
  }

  Widget _genresPreview(List<Genre> genres) {
    if (genres.isEmpty) return const Text('无');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: genres.map((item) => Chip(label: Text(item.name))).toList(),
    );
  }

  Widget _castPreview(List<Cast> cast) {
    if (cast.isEmpty) return const Text('无');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cast.take(8).map((item) => Text(item.name)).toList(),
    );
  }

  Widget _starsPreview(List<Star> cast) {
    if (cast.isEmpty) return const Text('无');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cast.take(8).map((item) => Text(item.name)).toList(),
    );
  }

  Widget _sampleInfoPreview(List<SampleInfo>? samples) {
    final list = samples ?? const <SampleInfo>[];
    if (list.isEmpty) return const Text('无');
    return Wrap(
      spacing: 6,
      children: list
          .take(5)
          .map((sample) => SizedBox(
                width: 72,
                height: 48,
                child: SmartImage(url: sample.thumbnail, fit: BoxFit.cover),
              ))
          .toList(),
    );
  }

  Widget _samplesPreview(List<Sample> samples) {
    if (samples.isEmpty) return const Text('无');
    return Wrap(
      spacing: 6,
      children: samples
          .take(5)
          .map((sample) => SizedBox(
                width: 72,
                height: 48,
                child: SmartImage(url: sample.thumbnail, fit: BoxFit.cover),
              ))
          .toList(),
    );
  }
}

class _CompareColumn extends StatelessWidget {
  final String title;
  final Widget child;

  const _CompareColumn({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
