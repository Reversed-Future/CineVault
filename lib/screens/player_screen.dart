import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as controls;
import 'package:path/path.dart' as path;
import '../models/movie.dart';
import '../services/database_service.dart';
import '../services/subtitle_cat_service.dart';

class PlayerScreen extends StatefulWidget {
  final Movie movie;
  final String videoPath;
  final String? subtitlePath;

  const PlayerScreen({
    super.key,
    required this.movie,
    required this.videoPath,
    this.subtitlePath,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final Player _player = Player();
  late final VideoController _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _autoSaveTimer;
  bool _subtitlesEnabled = true;
  bool _hasResumed = false; // 是否已经从上次位置续播
  String? _activeSubtitlePath;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _videoController = VideoController(_player);

    final settings = DatabaseService.getSettings();
    setState(() {
      _subtitlesEnabled = settings.showSubtitlesByDefault;
    });

    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    _player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    _activeSubtitlePath = await _resolveSubtitlePath();

    await _player.open(Media(widget.videoPath));
    await _applySubtitleTrack(
      _subtitlesEnabled ? _activeSubtitlePath : null,
    );

    if (widget.movie.safeLastWatchPosition > 0) {
      final settings = DatabaseService.getSettings();
      if (settings.autoResumePlayback) {
        // 等待播放器准备好再 seek
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          final seekPosition = Duration(
            milliseconds: (widget.movie.safeLastWatchPosition * 1000).toInt(),
          );
          print(
              '[PlayerScreen] Resuming playback from: ${widget.movie.safeLastWatchPosition}s (${seekPosition.inMilliseconds}ms)');
          await _player.seek(seekPosition);
          _hasResumed = true;
        } catch (e) {
          print('[PlayerScreen] Error seeking to resume position: $e');
        }
      }
    }

    await _player.play();

    setState(() {
      _isInitialized = true;
    });

    // 启动自动保存进度的定时器，每 5 秒保存一次
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isInitialized && _isPlaying) {
        _saveWatchProgress();
      }
    });
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _seek(Duration position) {
    _player.seek(position);
  }

  void _setVolume(double volume) {
    setState(() {
      _volume = volume;
    });
    _player.setVolume(volume * 100);
  }

  void _setPlaybackRate(double rate) {
    setState(() {
      _playbackRate = rate;
    });
    _player.setRate(rate);
  }

  Future<String?> _resolveSubtitlePath() async {
    final explicitPath = widget.subtitlePath;
    if (explicitPath != null &&
        explicitPath.isNotEmpty &&
        await File(explicitPath).exists()) {
      return explicitPath;
    }

    for (final subtitlePath
        in widget.movie.subtitleFilePaths ?? const <String>[]) {
      if (subtitlePath.isNotEmpty && await File(subtitlePath).exists()) {
        return subtitlePath;
      }
    }

    final localSubtitles =
        await SubtitleCatService.findLocalSubtitleFilesForVideo(
            widget.videoPath);
    return localSubtitles.firstOrNull;
  }

  Future<void> _applySubtitleTrack(String? subtitlePath) async {
    if (subtitlePath == null || subtitlePath.isEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(subtitlePath).toString(),
        title: path.basename(subtitlePath),
        language: 'zh-CN',
      ),
    );
  }

  Future<void> _toggleSubtitlesEnabled() async {
    final enabled = !_subtitlesEnabled;
    setState(() {
      _subtitlesEnabled = enabled;
    });
    await _applySubtitleTrack(enabled ? _activeSubtitlePath : null);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onMouseMove() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  /// 处理点击事件
  /// 如果控件隐藏则显示（保持 3 秒后自动隐藏）
  /// 如果控件已显示则立即隐藏
  void _handleTap() {
    if (_showControls) {
      // 控件已显示，点击则立即隐藏
      setState(() {
        _showControls = false;
      });
      _hideControlsTimer?.cancel();
    } else {
      // 控件隐藏，点击则显示并启动自动隐藏定时器
      setState(() {
        _showControls = true;
      });
      _startHideControlsTimer();
    }
  }

  Future<void> _saveWatchProgress() async {
    final position = _currentPosition.inSeconds.toDouble();
    await DatabaseService.updateWatchProgress(widget.movie.id, position);
  }

  Future<void> _closePlayer() async {
    await _saveWatchProgress();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _seekBackward() async {
    final newPosition = _currentPosition - const Duration(seconds: 10);
    await _player
        .seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  Future<void> _seekForward() async {
    final newPosition = _currentPosition + const Duration(seconds: 10);
    await _player
        .seek(newPosition > _totalDuration ? _totalDuration : newPosition);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    // 先保存当前播放进度
    unawaited(_saveWatchProgress());
    _hideControlsTimer?.cancel();
    _autoSaveTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isInitialized)
              Video(
                controller: _videoController,
                controls: controls.NoVideoControls,
              ),
            if (_showControls) _buildControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildTopBar(),
          const Spacer(),
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              onPressed: _closePlayer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.movie.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.movie.code.isNotEmpty)
                    Text(
                      widget.movie.code,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  if (_activeSubtitlePath != null)
                    Text(
                      path.basename(_activeSubtitlePath!),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
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

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressBar(),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                color: Colors.white,
                onPressed: _seekBackward,
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                iconSize: 32,
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.forward_10),
                color: Colors.white,
                onPressed: _seekForward,
              ),
              const SizedBox(width: 24),
              Text(
                _formatDuration(_currentPosition),
                style: const TextStyle(color: Colors.white),
              ),
              const Text(' / ', style: TextStyle(color: Colors.white)),
              Text(
                _formatDuration(_totalDuration),
                style: const TextStyle(color: Colors.white),
              ),
              const Spacer(),
              _buildSpeedMenu(),
              const SizedBox(width: 16),
              _buildVolumeControl(),
              const SizedBox(width: 16),
              _buildSubtitleToggle(),
              const SizedBox(width: 16),
              _buildFullscreenButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _totalDuration.inSeconds > 0
                  ? _currentPosition.inSeconds / _totalDuration.inSeconds
                  : 0,
              onChanged: (value) {
                final newPosition = Duration(
                  milliseconds: (value * _totalDuration.inMilliseconds).toInt(),
                );
                _seek(newPosition);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _volume == 0 ? Icons.volume_off : Icons.volume_up,
          ),
          color: Colors.white,
          onPressed: () => _setVolume(_volume == 0 ? 1.0 : 0.0),
        ),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _volume,
              min: 0.0,
              max: 1.0,
              onChanged: _setVolume,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedMenu() {
    return PopupMenuButton<double>(
      itemBuilder: (context) => [
        const PopupMenuItem(value: 0.5, child: Text('0.5x')),
        const PopupMenuItem(value: 0.75, child: Text('0.75x')),
        const PopupMenuItem(value: 1.0, child: Text('1.0x')),
        const PopupMenuItem(value: 1.25, child: Text('1.25x')),
        const PopupMenuItem(value: 1.5, child: Text('1.5x')),
        const PopupMenuItem(value: 2.0, child: Text('2.0x')),
      ],
      onSelected: _setPlaybackRate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${_playbackRate.toStringAsFixed(1)}x',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSubtitleToggle() {
    return Tooltip(
      message: _activeSubtitlePath == null
          ? '未匹配字幕'
          : (_subtitlesEnabled ? '关闭字幕' : '开启字幕'),
      child: IconButton(
        icon: Icon(
          _subtitlesEnabled ? Icons.subtitles : Icons.subtitles_off,
        ),
        color: Colors.white,
        onPressed: _activeSubtitlePath == null ? null : _toggleSubtitlesEnabled,
      ),
    );
  }

  Widget _buildFullscreenButton() {
    return IconButton(
      icon: const Icon(Icons.fullscreen),
      color: Colors.white,
      onPressed: () {
        // 全屏功能需要额外实现
      },
    );
  }
}
