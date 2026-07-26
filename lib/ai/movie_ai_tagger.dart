import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/ai_tagging_result.dart';
import '../models/custom_movie_tag.dart';
import '../models/movie.dart';
import '../models/named_item.dart';
import '../services/database_service.dart';
import 'local_translator.dart';

abstract class MovieAiTextGenerator {
  Future<String> generate({
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required int maxTokens,
  });
}

class LocalMovieAiTextGenerator implements MovieAiTextGenerator {
  LocalMovieAiTextGenerator({LocalTranslator? translator})
      : _translator = translator ?? LocalTranslator();

  final LocalTranslator _translator;

  @override
  Future<String> generate({
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required int maxTokens,
  }) {
    return _translator.completeText(
      modelId: modelId,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class AiMovieTagRecommendation {
  final String tagId;
  final String tagName;
  final double confidence;
  final String reason;

  AiMovieTagRecommendation({
    required this.tagId,
    required this.tagName,
    required this.confidence,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'tagId': tagId,
      'tagName': tagName,
      'confidence': confidence,
      'reason': reason,
    };
  }
}

class AiMovieTaggingAnalysis {
  final String movieId;
  final String modelId;
  final String inputHash;
  final String titleSegmentsJson;
  final String matchedTagsJson;
  final List<AiMovieTagRecommendation> recommendations;
  final String rawOutput;

  AiMovieTaggingAnalysis({
    required this.movieId,
    required this.modelId,
    required this.inputHash,
    required this.titleSegmentsJson,
    required this.matchedTagsJson,
    required this.recommendations,
    required this.rawOutput,
  });

  AiTaggingResult toResult({required String status, String? errorMessage}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AiTaggingResult(
      id: 'ai_tagging_${movieId}_${DateTime.now().microsecondsSinceEpoch}',
      movieId: movieId,
      modelId: modelId,
      inputHash: inputHash,
      titleSegmentsJson: titleSegmentsJson,
      matchedTagsJson: matchedTagsJson,
      status: status,
      createdAt: now,
      updatedAt: now,
      rawOutput: rawOutput,
      errorMessage: errorMessage,
    );
  }
}

class MovieAiTagger {
  MovieAiTagger({MovieAiTextGenerator? textGenerator})
      : _textGenerator = textGenerator ?? LocalMovieAiTextGenerator();

  static const double defaultMinConfidence = 0.85;
  static const String _systemPrompt = '''
你是影片标题语义切分与用户自定义标签归类助手。
只允许根据输入中的影片信息和用户自定义标签做判断。
不要创建新标签，不要输出未提供的 tagId。
只输出一个 JSON 对象，不要 Markdown，不要解释。
JSON 结构固定为：
{
  "titleSegments": {
    "series": [],
    "scene": [],
    "relationship": [],
    "attributes": [],
    "keywords": [],
    "ambiguousTerms": []
  },
  "summary": "",
  "matchedCustomTags": [
    {"tagId": "", "confidence": 0.0, "reason": ""}
  ]
}
confidence 使用 0 到 1 的小数。证据不足时 matchedCustomTags 返回空数组。
''';

  final MovieAiTextGenerator _textGenerator;

  Future<AiMovieTaggingAnalysis> analyzeMovie({
    required Movie movie,
    required List<CustomMovieTag> customTags,
    required String modelId,
  }) async {
    if (customTags.isEmpty) {
      throw StateError('No custom movie tags configured');
    }

    final input = _buildInputPayload(movie, customTags);
    final userPrompt = const JsonEncoder.withIndent('  ').convert(input);
    final rawOutput = await _textGenerator.generate(
      modelId: modelId,
      systemPrompt: _systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.1,
      maxTokens: 1200,
    );

    final decoded = _decodeObject(rawOutput);
    final knownTags = {for (final tag in customTags) tag.id: tag};
    final recommendations = _parseRecommendations(decoded, knownTags);
    final titleSegments = {
      'titleSegments': decoded['titleSegments'] is Map
          ? decoded['titleSegments']
          : <String, dynamic>{},
      'summary': decoded['summary'] is String ? decoded['summary'] : '',
    };

    return AiMovieTaggingAnalysis(
      movieId: movie.id,
      modelId: modelId,
      inputHash: _hashInput(input),
      titleSegmentsJson: jsonEncode(titleSegments),
      matchedTagsJson:
          jsonEncode(recommendations.map((item) => item.toJson()).toList()),
      recommendations: recommendations,
      rawOutput: rawOutput,
    );
  }

  Future<AiTaggingResult> analyzeStoreAndApply({
    required Movie movie,
    required List<CustomMovieTag> customTags,
    required String modelId,
    double minConfidence = defaultMinConfidence,
  }) async {
    try {
      final analysis = await analyzeMovie(
        movie: movie,
        customTags: customTags,
        modelId: modelId,
      );
      final highConfidenceRecommendations = analysis.recommendations
          .where((item) => item.confidence >= minConfidence)
          .toList();
      if (highConfidenceRecommendations.isNotEmpty) {
        await applyRecommendations(
          movie: movie,
          recommendations: highConfidenceRecommendations,
          minConfidence: minConfidence,
        );
      }
      final result = analysis.toResult(
        status: highConfidenceRecommendations.isEmpty
            ? AiTaggingResult.statusPendingReview
            : AiTaggingResult.statusApplied,
      );
      await DatabaseService.saveAiTaggingResult(result);
      return result;
    } catch (error) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final result = AiTaggingResult(
        id: 'ai_tagging_${movie.id}_${DateTime.now().microsecondsSinceEpoch}',
        movieId: movie.id,
        modelId: modelId,
        inputHash: _hashInput(_buildInputPayload(movie, customTags)),
        titleSegmentsJson: '{}',
        matchedTagsJson: '[]',
        status: AiTaggingResult.statusFailed,
        createdAt: now,
        updatedAt: now,
        rawOutput: '',
        errorMessage: error.toString(),
      );
      await DatabaseService.saveAiTaggingResult(result);
      rethrow;
    }
  }

  Future<int> applyRecommendations({
    required Movie movie,
    required List<AiMovieTagRecommendation> recommendations,
    double minConfidence = defaultMinConfidence,
  }) async {
    final currentTagIds = DatabaseService.getCustomTagIdsForMovie(movie.id);
    final tagIdsToAdd = recommendations
        .where((item) => item.confidence >= minConfidence)
        .map((item) => item.tagId)
        .toSet();
    final newTagIds = tagIdsToAdd.difference(currentTagIds);
    if (newTagIds.isEmpty) {
      return 0;
    }

    await DatabaseService.setMovieCustomTags(
      movie.id,
      {...currentTagIds, ...newTagIds},
    );
    return newTagIds.length;
  }

  Map<String, dynamic> _buildInputPayload(
    Movie movie,
    List<CustomMovieTag> customTags,
  ) {
    return {
      'movie': {
        'id': movie.id,
        'code': movie.code,
        'title': movie.name,
        'translatedTitle': movie.translatedName,
        'officialTags': movie.tags
                ?.map((tag) => {
                      'id': tag.id,
                      'name': tag.name,
                    })
                .toList() ??
            const [],
        'translatedOfficialTags': movie.translatedTags ?? const [],
        'cast': movie.cast
            .map((cast) => {
                  'id': cast.id,
                  'name': cast.name,
                })
            .toList(),
        'director': _namedItemToJson(movie.director),
        'producer': _namedItemToJson(movie.producer),
        'publisher': _namedItemToJson(movie.publisher),
        'series': _namedItemToJson(movie.series),
        'videoFileNames': movie.videoFilePaths
                ?.map((filePath) => p.basename(filePath))
                .toList() ??
            const [],
      },
      'customTags': customTags
          .map((tag) => {
                'tagId': tag.id,
                'name': tag.name,
              })
          .toList(),
      'task':
          '请切分影片标题语义，并从 customTags 中选择匹配的用户自定义标签。不要修改 officialTags。',
    };
  }

  Map<String, String>? _namedItemToJson(NamedItem? item) {
    if (item == null) return null;
    return {
      'id': item.id,
      'name': item.name,
    };
  }

  String _hashInput(Map<String, dynamic> input) {
    return sha256.convert(utf8.encode(jsonEncode(input))).toString();
  }

  Map<String, dynamic> _decodeObject(String rawOutput) {
    final jsonText = _extractJsonObject(rawOutput);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI output is not a JSON object');
    }
    return decoded;
  }

  String _extractJsonObject(String rawOutput) {
    var text = rawOutput.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```json\s*', caseSensitive: false), '');
      text = text.replaceFirst(RegExp(r'^```\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) {
      throw const FormatException('AI output does not contain a JSON object');
    }
    return text.substring(start, end + 1);
  }

  List<AiMovieTagRecommendation> _parseRecommendations(
    Map<String, dynamic> decoded,
    Map<String, CustomMovieTag> knownTags,
  ) {
    final matchedTags = decoded['matchedCustomTags'];
    if (matchedTags is! List) {
      return const [];
    }

    final recommendations = <AiMovieTagRecommendation>[];
    for (final item in matchedTags) {
      if (item is! Map) continue;
      final tagId = item['tagId'];
      if (tagId is! String || !knownTags.containsKey(tagId)) continue;

      final confidence = _parseConfidence(item['confidence']);
      if (confidence <= 0) continue;

      final tag = knownTags[tagId]!;
      recommendations.add(
        AiMovieTagRecommendation(
          tagId: tag.id,
          tagName: tag.name,
          confidence: confidence,
          reason: item['reason'] is String ? item['reason'] as String : '',
        ),
      );
    }

    recommendations.sort((a, b) => b.confidence.compareTo(a.confidence));
    return recommendations;
  }

  double _parseConfidence(Object? value) {
    if (value is num) {
      return value.toDouble().clamp(0.0, 1.0).toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed.clamp(0.0, 1.0).toDouble();
      }
    }
    return 0.0;
  }
}
