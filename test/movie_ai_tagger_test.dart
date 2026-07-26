import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/ai/movie_ai_tagger.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/custom_movie_tag.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/models/named_item.dart';
import 'package:cine_vault/services/database_service.dart';

class _FakeMovieAiTextGenerator implements MovieAiTextGenerator {
  _FakeMovieAiTextGenerator(this.output);

  final String output;
  String? lastSystemPrompt;
  String? lastUserPrompt;

  @override
  Future<String> generate({
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required int maxTokens,
  }) async {
    lastSystemPrompt = systemPrompt;
    lastUserPrompt = userPrompt;
    return output;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI tagger parses JSON and ignores unknown custom tag ids', () async {
    final generator = _FakeMovieAiTextGenerator('''
```json
{
  "titleSegments": {
    "series": ["Alpha"],
    "scene": ["office"],
    "relationship": ["friend"],
    "attributes": ["calm"],
    "keywords": ["story"],
    "ambiguousTerms": ["SP"]
  },
  "summary": "story focused title",
  "matchedCustomTags": [
    {"tagId": "tag_story", "confidence": 0.92, "reason": "story keyword"},
    {"tagId": "tag_missing", "confidence": 0.99, "reason": "not stored"},
    {"tagId": "tag_low", "confidence": 0.44, "reason": "weak signal"}
  ]
}
```
''');

    final tagger = MovieAiTagger(textGenerator: generator);
    final movie = Movie(
      id: 'AI-001',
      name: 'Alpha office story',
      code: 'AI-001',
      createdAt: 1000,
      cast: const <Cast>[],
      tags: [NamedItem(id: 'official', name: 'Official')],
      videoFilePaths: const ['D:\\videos\\AI-001.mp4'],
    );
    final tags = [
      CustomMovieTag(id: 'tag_story', name: '剧情向', createdAt: 1),
      CustomMovieTag(id: 'tag_low', name: '低置信度', createdAt: 2),
    ];

    final analysis = await tagger.analyzeMovie(
      movie: movie,
      customTags: tags,
      modelId: 'local-model',
    );

    expect(analysis.movieId, 'AI-001');
    expect(analysis.recommendations.map((item) => item.tagId), [
      'tag_story',
      'tag_low',
    ]);
    expect(analysis.recommendations.first.tagName, '剧情向');
    expect(analysis.recommendations.first.confidence, 0.92);

    final titleSegments =
        jsonDecode(analysis.titleSegmentsJson) as Map<String, dynamic>;
    expect(titleSegments['summary'], 'story focused title');
    expect(titleSegments['titleSegments']['keywords'], ['story']);
    expect(generator.lastUserPrompt, contains('AI-001'));
  });

  test('AI tagger applies custom links without changing source tags', () async {
    final tempDir = await Directory.systemTemp.createTemp('cine_vault_ai_');
    await DatabaseService.init(customPath: tempDir.path);

    final unique = DateTime.now().microsecondsSinceEpoch.toString();
    final movie = Movie(
      id: 'AI-APPLY-$unique',
      name: 'AI apply movie',
      code: 'AI-APPLY-$unique',
      createdAt: 1000,
      cast: const <Cast>[],
      tags: [NamedItem(id: 'official-$unique', name: 'Official')],
    );
    await DatabaseService.addMovie(movie);

    final storedTag =
        await DatabaseService.createCustomMovieTag('AI 自动分类 $unique');
    final recommendation = AiMovieTagRecommendation(
      tagId: storedTag.id,
      tagName: storedTag.name,
      confidence: 0.93,
      reason: 'matches title',
    );

    final tagger = MovieAiTagger(
      textGenerator: _FakeMovieAiTextGenerator('{}'),
    );
    final addedCount = await tagger.applyRecommendations(
      movie: movie,
      recommendations: [recommendation],
      minConfidence: 0.8,
    );

    expect(addedCount, 1);
    expect(DatabaseService.getCustomTagIdsForMovie(movie.id), {storedTag.id});

    final savedMovie = DatabaseService.getMovie(movie.id)!;
    expect(savedMovie.tags!.single.id, 'official-$unique');
    expect(savedMovie.tags!.single.name, 'Official');
  });
}
