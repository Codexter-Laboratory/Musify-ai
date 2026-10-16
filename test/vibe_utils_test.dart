import 'package:flutter_test/flutter_test.dart';
import 'package:musify/utilities/vibe_utils.dart';

VibeProfile profile(
  String title, {
  String author = 'Someone',
  List<String> keywords = const [],
  String description = '',
  int? seconds = 200,
}) => buildVibeProfile(
  ytid: title,
  title: title,
  author: author,
  keywords: keywords,
  description: description,
  durationSeconds: seconds,
);

void main() {
  group('buildVibeProfile', () {
    test('reads genre and mood from title and tags', () {
      final p = profile(
        'rainy night chill lofi hip hop beat',
        keywords: ['lofi', 'study beats'],
      );
      expect(p.genres, contains('lofi'));
      expect(p.moods, contains('chill'));
      expect(p.energy, lessThan(0.35));
    });

    test('high-energy genres and words raise energy', () {
      final p = profile('Insane dubstep drop bass boosted workout');
      expect(p.genres, contains('dubstep'));
      expect(p.moods, contains('energetic'));
      expect(p.energy, greaterThan(0.8));
    });

    test('matches whole words only', () {
      // "wrapped" must not count as rap, "most" must not count as ost.
      final p = profile('Wrapped up in the most beautiful way');
      expect(p.genres, isEmpty);
    });

    test('hyphenated spellings match', () {
      expect(profile('lo-fi beats to relax to').genres, contains('lofi'));
      expect(profile('Best K-pop dance 2024').genres, contains('k-pop'));
    });

    test('unknown metadata gives a neutral, label-less profile', () {
      final p = profile('Untitled 7');
      expect(p.genres, isEmpty);
      expect(p.moods, isEmpty);
      expect(p.energy, 0.5);
      expect(p.label, isEmpty);
    });
  });

  group('scoreVibeMatch', () {
    final seed = profile(
      'chill lofi hip hop beats to study',
      keywords: ['lofi', 'chill'],
    );

    double score(String title, {int? rank, int? seconds = 200}) =>
        scoreVibeMatch(
          seed,
          profile(title, seconds: seconds),
          title,
          relatedRank: rank,
          relatedCount: rank == null ? 0 : 10,
        );

    test('same genre and mood beats a different vibe', () {
      expect(
        score('relaxing lofi chill beat'),
        greaterThan(score('hardstyle dubstep rage drop')),
      );
    });

    test('same family beats an unrelated genre', () {
      expect(
        score('ambient peaceful soundscape'),
        greaterThan(score('heavy metal aggressive')),
      );
    });

    test('opposite energy is penalised', () {
      expect(score('calm soft lofi'), greaterThan(score('loud hype lofi')));
    });

    test('mixes and compilations are penalised', () {
      expect(
        score('lofi chill beat'),
        greaterThan(score('lofi chill beat 3 hours mix')),
      );
    });

    test('very long tracks are penalised', () {
      expect(
        score('lofi chill beat'),
        greaterThan(score('lofi chill beat', seconds: 3 * 3600)),
      );
    });

    test('a better related rank scores higher', () {
      expect(
        score('lofi chill beat', rank: 0),
        greaterThan(score('lofi chill beat', rank: 9)),
      );
    });
  });

  test('buildVibeSearchQueries uses genre, mood and artist', () {
    final seed = profile(
      'chill lofi beat',
      author: 'Jinsang',
      keywords: ['lofi'],
    );
    final queries = buildVibeSearchQueries(seed);
    expect(queries, isNotEmpty);
    expect(queries.first, contains('lofi'));
    expect(queries.any((q) => q.contains('Jinsang')), isTrue);
    expect(buildVibeSearchQueries(profile('Untitled 7', author: '')), isEmpty);
  });

  test('limitPerArtist caps songs per artist and keeps order', () {
    final out = limitPerArtist<String>([
      'a1',
      'a2',
      'b1',
      'a3',
      'b2',
    ], (s) => s[0]);
    expect(out, ['a1', 'a2', 'b1', 'b2']);
  });
}
