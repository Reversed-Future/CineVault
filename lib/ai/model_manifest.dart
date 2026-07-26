class ModelManifest {
  final int schemaVersion;
  final List<ModelInfo> models;

  ModelManifest({
    required this.schemaVersion,
    required this.models,
  });

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    return ModelManifest(
      schemaVersion: json['schema_version'] as int,
      models: (json['models'] as List<dynamic>)
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'models': models.map((e) => e.toJson()).toList(),
    };
  }

  static ModelManifest defaultManifest() {
    return ModelManifest(
      schemaVersion: 1,
      models: [
        ModelInfo(
          id: 'qwen2.5-1.5b-q4km',
          name: 'Qwen2.5 1.5B（轻量・推荐）',
          description: '约 1.05GB，适合大多数设备，翻译影片标题/简介/标签',
          tier: 'lite',
          ggufUrl:
              'https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
          fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          fileSizeBytes: 1127283200,
          sha256: '',
          minFreeStorageMb: 1500,
          estimatedRamMb: 1800,
          defaultCtx: 2048,
          defaultThreads: 4,
          nGpuLayers: -1,
        ),
        ModelInfo(
          id: 'qwen2.5-3b-q4km',
          name: 'Qwen2.5 3B（高质量）',
          description: '约 2.1GB，翻译更准确，建议 6GB+ 内存设备',
          tier: 'quality',
          ggufUrl:
              'https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf',
          fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
          fileSizeBytes: 2254566400,
          sha256: '',
          minFreeStorageMb: 2800,
          estimatedRamMb: 3200,
          defaultCtx: 2048,
          defaultThreads: 4,
          nGpuLayers: -1,
        ),
      ],
    );
  }
}

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String tier;
  final String ggufUrl;
  final String fileName;
  final int fileSizeBytes;
  final String? sha256;
  final int minFreeStorageMb;
  final int estimatedRamMb;
  final int defaultCtx;
  final int defaultThreads;
  final int nGpuLayers;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.ggufUrl,
    required this.fileName,
    required this.fileSizeBytes,
    this.sha256,
    required this.minFreeStorageMb,
    required this.estimatedRamMb,
    required this.defaultCtx,
    required this.defaultThreads,
    required this.nGpuLayers,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      tier: json['tier'] as String,
      ggufUrl: json['ggufUrl'] as String,
      fileName: json['fileName'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int,
      sha256: json['sha256'] as String?,
      minFreeStorageMb: json['minFreeStorageMb'] as int,
      estimatedRamMb: json['estimatedRamMb'] as int,
      defaultCtx: json['defaultCtx'] as int,
      defaultThreads: json['defaultThreads'] as int,
      nGpuLayers: json['nGpuLayers'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'tier': tier,
      'ggufUrl': ggufUrl,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'sha256': sha256,
      'minFreeStorageMb': minFreeStorageMb,
      'estimatedRamMb': estimatedRamMb,
      'defaultCtx': defaultCtx,
      'defaultThreads': defaultThreads,
      'nGpuLayers': nGpuLayers,
    };
  }
}
