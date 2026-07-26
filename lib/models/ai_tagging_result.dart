import 'package:hive/hive.dart';

part 'ai_tagging_result.g.dart';

@HiveType(typeId: 12)
class AiTaggingResult extends HiveObject {
  static const String statusPendingReview = 'pending_review';
  static const String statusApplied = 'applied';
  static const String statusFailed = 'failed';

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String movieId;

  @HiveField(2)
  final String modelId;

  @HiveField(3)
  final String inputHash;

  @HiveField(4)
  final String titleSegmentsJson;

  @HiveField(5)
  final String matchedTagsJson;

  @HiveField(6)
  final String status;

  @HiveField(7)
  final int createdAt;

  @HiveField(8)
  final int updatedAt;

  @HiveField(9)
  final String rawOutput;

  @HiveField(10)
  final String? errorMessage;

  AiTaggingResult({
    required this.id,
    required this.movieId,
    required this.modelId,
    required this.inputHash,
    required this.titleSegmentsJson,
    required this.matchedTagsJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.rawOutput,
    this.errorMessage,
  });

  AiTaggingResult copyWith({
    String? id,
    String? movieId,
    String? modelId,
    String? inputHash,
    String? titleSegmentsJson,
    String? matchedTagsJson,
    String? status,
    int? createdAt,
    int? updatedAt,
    String? rawOutput,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AiTaggingResult(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      modelId: modelId ?? this.modelId,
      inputHash: inputHash ?? this.inputHash,
      titleSegmentsJson: titleSegmentsJson ?? this.titleSegmentsJson,
      matchedTagsJson: matchedTagsJson ?? this.matchedTagsJson,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rawOutput: rawOutput ?? this.rawOutput,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
