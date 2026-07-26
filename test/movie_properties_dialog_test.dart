import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/models/cast.dart';
import 'package:cine_vault/models/movie.dart';
import 'package:cine_vault/widgets/movie_context_menu.dart';

void main() {
  testWidgets('movie properties dialog shows local video file paths',
      (tester) async {
    const videoPath = 'D:\\Videos\\ABC-123.mp4';
    const subtitlePath = 'D:\\Videos\\ABC-123.srt';
    final movie = Movie(
      id: 'ABC-123',
      name: 'ABC-123',
      code: 'ABC-123',
      createdAt: 1000,
      cast: const <Cast>[],
      videoFilePaths: const [videoPath],
      subtitleFilePaths: const [subtitlePath],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MoviePropertiesDialog(movie: movie),
          ),
        ),
      ),
    );

    expect(find.text(videoPath), findsOneWidget);
    expect(find.text(subtitlePath), findsOneWidget);
  });
}
