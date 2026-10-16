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

  group('regressions', () {
    test('"Daft Punk" is not classified as punk/metal', () {
      expect(profile('Daft Punk - Something').genres, isEmpty);
      expect(profile('Green Day pop punk anthem').genres, contains('rock'));
    });

    test('unknown energy is not held against a candidate', () {
      final seed = profile('heavy metal aggressive riff', keywords: ['metal']);
      final unknown = profile('Untitled 7');
      expect(unknown.energyKnown, isFalse);
      final calm = profile('calm soft mellow song');
      expect(
        scoreVibeMatch(
          seed,
          unknown,
          'Untitled 7',
          relatedRank: 0,
          relatedCount: 5,
        ),
        greaterThan(
          scoreVibeMatch(
            seed,
            calm,
            'calm soft mellow song',
            relatedRank: 0,
            relatedCount: 5,
          ),
        ),
      );
    });

    test('a two hour video is not queued as a song', () {
      final seed = profile('chill lofi beat', keywords: ['lofi']);
      final long = profile('chill lofi beat', seconds: 7200);
      final normal = profile('chill lofi beat');
      expect(
        scoreVibeMatch(seed, long, 'x', relatedRank: 0, relatedCount: 5),
        lessThan(
          scoreVibeMatch(seed, normal, 'x', relatedRank: 0, relatedCount: 5) -
              5,
        ),
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

  group('selectVibeMatches', () {
    final seed = profile(
      'chill lofi hip hop beats to study',
      keywords: ['lofi', 'chill'],
    );

    VibeCandidate cand(String title, {String artist = 'x', int? rank}) =>
        VibeCandidate(
          profile: profile(title, author: artist),
          title: title,
          relatedRank: rank,
        );

    List<String> pick(List<VibeCandidate> c, {int limit = 10}) =>
        selectVibeMatches(
          seed,
          c,
          relatedCount: 10,
          limit: limit,
        ).map((e) => e.title).toList();

    test('orders best match first', () {
      final result = pick([
        cand('hardstyle rage drop', artist: 'a'),
        cand('relaxing lofi chill beat', artist: 'b'),
        cand('soft ambient soundscape', artist: 'c'),
      ]);
      expect(result.first, 'relaxing lofi chill beat');
    });

    test('drops songs that clash when enough good ones exist', () {
      final good = [
        for (var i = 0; i < 6; i++) cand('chill lofi beat $i', artist: 'g$i'),
      ];
      final result = pick([
        ...good,
        cand('metal rage aggressive', artist: 'z'),
      ]);
      expect(result, isNot(contains('metal rage aggressive')));
      expect(result, hasLength(6));
    });

    test('backfills with near matches when few good ones exist', () {
      final result = pick([
        cand('relaxing lofi chill beat', artist: 'a'),
        cand('Untitled 7', artist: 'b'),
        cand('Untitled 8', artist: 'c'),
      ]);
      expect(result, hasLength(3));
    });

    test('never returns a hard clash, even when short of songs', () {
      final result = pick([
        cand('dubstep rage drop bass boosted hardstyle', artist: 'a'),
      ]);
      expect(result, isEmpty);
    });

    test('caps songs per artist and respects the limit', () {
      final result = pick([
        for (var i = 0; i < 5; i++) cand('chill lofi beat $i', artist: 'same'),
        for (var i = 0; i < 5; i++) cand('chill lofi tune $i', artist: 'o$i'),
      ], limit: 4);
      expect(result, hasLength(4));
      expect(result.where((t) => t.startsWith('chill lofi beat')).length, 2);
    });

    test('returns nothing for no candidates', () {
      expect(pick([]), isEmpty);
    });
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
