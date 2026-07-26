import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/aria2_manager.dart';
import '../services/aria2_service.dart';
import '../services/database_service.dart';
import '../services/tracker_updater.dart';
import '../widgets/add_tracker_source_dialog.dart';

/// 下载设置页面
class DownloadSettingsPage extends ConsumerStatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  ConsumerState<DownloadSettingsPage> createState() =>
      _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends ConsumerState<DownloadSettingsPage> {
  final Aria2Manager _aria2Manager = Aria2Manager();
  final Aria2Service _aria2Service = Aria2Service();
  final TrackerUpdater _trackerUpdater = TrackerUpdater();

  late TextEditingController _rpcPortController;
  late TextEditingController _rpcSecretController;
  late TextEditingController _downloadLimitController;
  late TextEditingController _uploadLimitController;
  late TextEditingController _trackersController;

  bool _isDownloadingAria2 = false;
  int _downloadProgress = 0;
  bool _isUpdatingTrackers = false;
  double _trackersUpdateProgress = 0;
  String _aria2Status = '未检查';

  Future<bool> _persistSettings(
    AppSettings newSettings, {
    String? successMessage,
  }) async {
    try {
      await DatabaseService.saveSettings(newSettings);
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载设置保存失败: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = DatabaseService.getSettings()!;
    _rpcPortController =
        TextEditingController(text: settings.aria2RpcPort.toString());
    _rpcSecretController =
        TextEditingController(text: settings.aria2RpcSecret ?? '');
    _downloadLimitController = TextEditingController(
        text: settings.aria2DownloadSpeedLimitKB.toString());
    _uploadLimitController = TextEditingController(
        text: settings.aria2UploadSpeedLimitKB.toString());
    _trackersController =
        TextEditingController(text: settings.aria2TrackersList ?? '');

    // 配置 Aria2Service
    _aria2Service.configure(
      host: '127.0.0.1',
      port: settings.aria2RpcPort,
      secret: settings.aria2RpcSecret,
    );

    _checkAria2Status();
  }

  @override
  void dispose() {
    _rpcPortController.dispose();
    _rpcSecretController.dispose();
    _downloadLimitController.dispose();
    _uploadLimitController.dispose();
    _trackersController.dispose();
    super.dispose();
  }

  /// 检查 aria2 状态
  Future<void> _checkAria2Status() async {
    final installed = await _aria2Manager.isAria2Installed();
    if (!installed) {
      setState(() {
        _aria2Status = '未安装';
      });
      return;
    }

    // 先检查 RPC 是否可用（最准确的状态判断）
    final available = await _aria2Service.isAvailable();
    if (available) {
      // 同步更新 manager 状态
      setState(() {
        _aria2Status = '运行中';
      });
      return;
    }

    // 如果 RPC 不可用但端口在监听，也认为是运行中（刚启动还没就绪）
    if (await _isPortListening()) {
      setState(() {
        _aria2Status = '启动中...';
      });
      return;
    }

    setState(() {
      _aria2Status = '已安装但未运行';
    });
  }

  /// 检查端口是否在监听
  Future<bool> _isPortListening() async {
    try {
      final socket = await Socket.connect('127.0.0.1', _aria2Service.rpcPort,
          timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 下载并安装 aria2c
  Future<void> _downloadAria2() async {
    setState(() {
      _isDownloadingAria2 = true;
      _downloadProgress = 0;
    });

    final success = await _aria2Manager.downloadAndInstall(
      onProgress: (p) {
        setState(() {
          _downloadProgress = p;
        });
      },
    );

    setState(() {
      _isDownloadingAria2 = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'aria2c 安装成功' : 'aria2c 安装失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    _checkAria2Status();
  }

  /// 启动 aria2
  Future<void> _startAria2() async {
    final settings = DatabaseService.getSettings()!;
    _aria2Manager.configure(rpcSecret: settings.aria2RpcSecret ?? '');
    final success = await _aria2Manager.start();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'aria2 已启动' : '启动失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    _checkAria2Status();
  }

  /// 停止 aria2
  Future<void> _stopAria2() async {
    await _aria2Manager.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('aria2 已停止')),
    );
    _checkAria2Status();
  }

  /// 更新 trackers
  ///
  /// 智能合并：解析所有源（订阅名单 + 默认源），与现有列表去重后追加
  /// 不会覆盖已有内容
  Future<void> _updateTrackers() async {
    setState(() {
      _isUpdatingTrackers = true;
      _trackersUpdateProgress = 0;
    });

    try {
      // 从设置中获取用户订阅的源
      final settings = DatabaseService.getSettings()!;
      final sourceUrlsText = settings.trackersSourceUrls?.trim();
      List<String>? customSources;
      if (sourceUrlsText != null && sourceUrlsText.isNotEmpty) {
        customSources = sourceUrlsText
            .split(RegExp(r'[\n,;\s]+'))
            .where((url) => url.trim().isNotEmpty)
            .toList();
      }

      final newTrackers = await _trackerUpdater.updateTrackers(
        sources: customSources,
        onProgress: (p) {
          setState(() {
            _trackersUpdateProgress = p;
          });
        },
      );

      // 获取现有 trackers 列表
      final existingText = _trackersController.text;
      final existingTrackers = existingText
          .split(RegExp(r'[\n,;\s]+'))
          .where((t) => t.trim().isNotEmpty)
          .toSet();

      // 找出新增的 trackers（去重）
      final addedTrackers =
          newTrackers.where((t) => !existingTrackers.contains(t)).toList();

      if (addedTrackers.isEmpty && newTrackers.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('刷新完成：源中 ${newTrackers.length} 个 trackers 全部已存在，未添加新内容'),
              backgroundColor: Colors.blue,
            ),
          );
        }
        setState(() {
          _isUpdatingTrackers = false;
        });
        return;
      }

      if (newTrackers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未从任何源获取到 trackers，请检查源 URL 是否有效'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isUpdatingTrackers = false;
        });
        return;
      }

      // 合并：保留原有 + 追加新增
      final mergedSet = <String>{...existingTrackers, ...addedTrackers};
      final mergedList = mergedSet.toList()..sort();
      final mergedText = mergedList.join('\n');

      setState(() {
        _trackersController.text = mergedText;
      });

      // 自动保存
      final newSettings = settings.copyWith(
        aria2TrackersList: mergedText,
        lastTrackersUpdateTime: DateTime.now().millisecondsSinceEpoch,
      );
      final saved = await _persistSettings(newSettings);
      if (!saved) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '刷新完成：原有 ${existingTrackers.length} 个，新增 ${addedTrackers.length} 个，共 ${mergedList.length} 个'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUpdatingTrackers = false;
      });
    }
  }

  /// 打开添加 trackers 源弹窗
  ///
  /// 成功导入后：
  /// 1. 更新 trackers 列表
  /// 2. 自动把源 URL 加入订阅名单（trackersSourceUrls）
  Future<void> _showAddTrackerSourceDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AddTrackerSourceDialog(
        currentTrackersText: _trackersController.text,
      ),
    );

    if (result == null || !mounted) return;

    final newTrackersText = result['trackers'];
    final sourceUrl = result['sourceUrl'];

    if (newTrackersText == null) return;

    setState(() {
      _trackersController.text = newTrackersText;
    });

    // 自动保存到设置（包含订阅名单）
    final settings = DatabaseService.getSettings()!;
    final newSettings = settings.copyWith(
      aria2TrackersList: newTrackersText,
      trackersSourceUrls: _appendToSubscriptions(
        settings.trackersSourceUrls,
        sourceUrl,
      ),
      lastTrackersUpdateTime: DateTime.now().millisecondsSinceEpoch,
    );
    final saved = await _persistSettings(newSettings);
    if (!saved) return;

    if (mounted) {
      final subCount = _getSubscriptionCount(newSettings.trackersSourceUrls);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导入并加入订阅名单（共 $subCount 个源）'),
        ),
      );
    }
  }

  /// 把源 URL 追加到订阅名单中（自动去重）
  String _appendToSubscriptions(String? currentSubs, String? newUrl) {
    if (newUrl == null || newUrl.isEmpty) return currentSubs ?? '';
    final existing = (currentSubs ?? '')
        .split(RegExp(r'[\n,;\s]+'))
        .where((u) => u.trim().isNotEmpty)
        .toList();
    if (!existing.contains(newUrl)) {
      existing.add(newUrl);
    }
    return existing.join('\n');
  }

  /// 获取订阅源数量
  int _getSubscriptionCount(String? sourceUrls) {
    if (sourceUrls == null || sourceUrls.isEmpty) return 0;
    return sourceUrls
        .split(RegExp(r'[\n,;\s]+'))
        .where((u) => u.trim().isNotEmpty)
        .length;
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    final settings = DatabaseService.getSettings()!;
    final newSettings = settings.copyWith(
      useAria2ForDownloads: _isUseAria2(),
      aria2RpcPort: int.tryParse(_rpcPortController.text) ?? 6800,
      aria2RpcSecret:
          _rpcSecretController.text.isEmpty ? null : _rpcSecretController.text,
      aria2MaxConcurrentDownloads: _getMaxConcurrent(),
      aria2MaxConnectionPerServer: _getMaxConnectionPerServer(),
      aria2DownloadSpeedLimitKB:
          int.tryParse(_downloadLimitController.text) ?? 0,
      aria2UploadSpeedLimitKB: int.tryParse(_uploadLimitController.text) ?? 0,
      aria2TrackersList: _trackersController.text,
      autoUpdateTrackers: _isAutoUpdateTrackers(),
      lastTrackersUpdateTime: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistSettings(newSettings, successMessage: '设置已保存');
  }

  bool _isUseAria2() {
    final settings = DatabaseService.getSettings()!;
    return settings.useAria2ForDownloads;
  }

  bool _isAutoUpdateTrackers() {
    final settings = DatabaseService.getSettings()!;
    return settings.autoUpdateTrackers;
  }

  int _getMaxConcurrent() {
    final settings = DatabaseService.getSettings()!;
    return settings.aria2MaxConcurrentDownloads;
  }

  int _getMaxConnectionPerServer() {
    final settings = DatabaseService.getSettings()!;
    return settings.aria2MaxConnectionPerServer;
  }

  /// 获取 trackers 数量（从控制器当前文本中统计）
  int _getTrackersCount() {
    final text = _trackersController.text;
    if (text.isEmpty) return 0;
    // 按换行、逗号、分号、空白等分隔符分割
    return text
        .split(RegExp(r'[\n,;\s]+'))
        .where((t) => t.trim().isNotEmpty)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final settings = DatabaseService.getSettings()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: '保存设置',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 状态卡片
          _buildStatusCard(),
          const SizedBox(height: 16),

          // 启用 aria2
          Card(
            child: SwitchListTile(
              title: const Text('启用 aria2 下载'),
              subtitle: const Text('使用 aria2c 替代内置下载器，支持多线程加速、磁力链接、BT等'),
              value: settings.useAria2ForDownloads,
              onChanged: (v) async {
                final newSettings = settings.copyWith(useAria2ForDownloads: v);
                final saved = await _persistSettings(newSettings);
                if (saved && mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 8),

          // RPC 配置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RPC 配置',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rpcPortController,
                    decoration: const InputDecoration(
                      labelText: 'RPC 端口',
                      hintText: '6800',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rpcSecretController,
                    decoration: const InputDecoration(
                      labelText: 'RPC 密钥（可选）',
                      hintText: '留空表示无密钥',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 限速设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('限速设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('单位：KB/s，0 表示不限速',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _downloadLimitController,
                    decoration: const InputDecoration(
                      labelText: '下载限速',
                      hintText: '0',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _uploadLimitController,
                    decoration: const InputDecoration(
                      labelText: '上传限速',
                      hintText: '0',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 并发设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('并发设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text('最大并发下载数: ${settings.aria2MaxConcurrentDownloads}'),
                  Slider(
                    value: settings.aria2MaxConcurrentDownloads.toDouble(),
                    min: 1,
                    max: 16,
                    divisions: 15,
                    label: settings.aria2MaxConcurrentDownloads.toString(),
                    onChanged: (v) async {
                      final newSettings = settings.copyWith(
                          aria2MaxConcurrentDownloads: v.toInt());
                      final saved = await _persistSettings(newSettings);
                      if (saved && mounted) setState(() {});
                    },
                  ),
                  Text('每服务器最大连接数: ${settings.aria2MaxConnectionPerServer}'),
                  Slider(
                    value: settings.aria2MaxConnectionPerServer.toDouble(),
                    min: 1,
                    max: 64,
                    divisions: 63,
                    label: settings.aria2MaxConnectionPerServer.toString(),
                    onChanged: (v) async {
                      final newSettings = settings.copyWith(
                          aria2MaxConnectionPerServer: v.toInt());
                      final saved = await _persistSettings(newSettings);
                      if (saved && mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Trackers 设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BT Trackers',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              '当前共 ${_getTrackersCount()} 个',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 添加源按钮
                      IconButton(
                        icon: const Icon(Icons.add_link),
                        onPressed: _showAddTrackerSourceDialog,
                        tooltip: '从 URL 添加 trackers 源',
                      ),
                      if (_isUpdatingTrackers)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            value: _trackersUpdateProgress > 0
                                ? _trackersUpdateProgress
                                : null,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _updateTrackers,
                          tooltip: '立即更新 trackers',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Trackers 列表输入框
                  TextField(
                    controller: _trackersController,
                    decoration: InputDecoration(
                      labelText: 'Trackers 列表（每行一个）',
                      hintText:
                          'udp://tracker.opentrackr.org:1337/announce\nudp://tracker.openbittorrent.com:6969/announce\n...',
                      border: const OutlineInputBorder(),
                      helperText: '使用换行分隔，自动转 aria2 格式',
                      suffixIcon: _trackersController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: '清空',
                              onPressed: () {
                                setState(() {
                                  _trackersController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    maxLines: 10,
                    minLines: 5,
                    onChanged: (_) {
                      // 仅刷新计数器，不保存（点击保存按钮或刷新时统一保存）
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('自动更新 trackers'),
                    subtitle: const Text('启动时自动从公开源更新 trackers'),
                    value: settings.autoUpdateTrackers,
                    onChanged: (v) async {
                      final newSettings =
                          settings.copyWith(autoUpdateTrackers: v);
                      final saved = await _persistSettings(newSettings);
                      if (saved && mounted) setState(() {});
                    },
                  ),
                  if (settings.lastTrackersUpdateTime != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '上次更新: ${DateTime.fromMillisecondsSinceEpoch(settings.lastTrackersUpdateTime!).toLocal().toString().split('.').first}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: _getStatusColor(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'aria2 状态: $_aria2Status',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isDownloadingAria2) ...[
              LinearProgressIndicator(value: _downloadProgress / 100),
              const SizedBox(height: 8),
              Text('下载中: $_downloadProgress%',
                  style: const TextStyle(color: Colors.white)),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_aria2Status == '未安装')
                    ElevatedButton.icon(
                      onPressed: _downloadAria2,
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: const Text('下载并安装 aria2c'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (_aria2Status == '已安装但未运行' || _aria2Status == '运行异常')
                    ElevatedButton.icon(
                      onPressed: _startAria2,
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text('启动 aria2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (_aria2Status == '运行中')
                    ElevatedButton.icon(
                      onPressed: _stopAria2,
                      icon: const Icon(Icons.stop, color: Colors.white),
                      label: const Text('停止 aria2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _checkAria2Status,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('刷新状态'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (_aria2Status) {
      case '运行中':
        return Colors.green.shade700;
      case '未安装':
        return Colors.orange.shade700;
      case '已安装但未运行':
        return Colors.blue.shade700;
      case '运行异常':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}
