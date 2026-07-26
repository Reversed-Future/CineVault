import 'package:flutter_test/flutter_test.dart';
import 'package:cine_vault/services/movie_lookup_resolver.dart';

void main() {
  test('normalizeMovieLookupId trims whitespace', () {
    expect(normalizeMovieLookupId(' 550 '), '550');
    expect(normalizeMovieLookupId('\nmovie-1\t'), 'movie-1');
  });
}
