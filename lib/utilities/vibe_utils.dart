/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

// Pure helpers behind "Play more like this": they read the metadata YouTube
// exposes for a track (title, channel, tags, description, length) and boil it
// down to a [VibeProfile] (genre, mood, energy), then score how closely
// another track matches that profile. Nothing here touches the network.

import 'dart:math' as math;

/// Canonical genre name -> (family, search patterns). Genres sharing a family
/// are "close cousins" (e.g. dubstep and house are both electronic).
const Map<String, ({String family, List<String> patterns})> _genres = {
  'lofi': (
    family: 'chill',
    patterns: ['lofi', 'lo-fi', 'lo fi', 'chillhop', 'study beats'],
  ),
  'ambient': (
    family: 'chill',
    patterns: ['ambient', 'drone', 'soundscape', 'meditation', 'new age'],
  ),
  'hip hop': (
    family: 'urban',
    patterns: ['hip hop', 'hip-hop', 'hiphop', 'boom bap', 'rap'],
  ),
  'trap': (family: 'urban', patterns: ['trap', 'drill', 'phonk']),
  'r&b': (
    family: 'urban',
    patterns: ['r&b', 'rnb', 'r and b', 'neo soul', 'soul'],
  ),
  'pop': (family: 'pop', patterns: ['pop', 'synthpop', 'dance pop']),
  'k-pop': (family: 'pop', patterns: ['k-pop', 'kpop', 'j-pop', 'jpop']),
  'indie': (
    family: 'rock',
    patterns: ['indie', 'alternative', 'shoegaze', 'dream pop'],
  ),
  'rock': (
    family: 'rock',
    patterns: ['rock', 'grunge', 'post-punk', 'hard rock'],
  ),
  'metal': (
    family: 'rock',
    patterns: ['metal', 'metalcore', 'deathcore', 'hardcore', 'punk'],
  ),
  'edm': (
    family: 'electronic',
    patterns: ['edm', 'electronic', 'electro', 'big room', 'future bass'],
  ),
  'house': (
    family: 'electronic',
    patterns: ['house', 'deep house', 'tech house', 'progressive house'],
  ),
  'techno': (
    family: 'electronic',
    patterns: ['techno', 'trance', 'hardstyle', 'psytrance'],
  ),
  'dubstep': (
    family: 'electronic',
    patterns: ['dubstep', 'drum and bass', 'drum & bass', 'dnb', 'riddim'],
  ),
  'synthwave': (
    family: 'electronic',
    patterns: ['synthwave', 'retrowave', 'vaporwave', 'outrun', 'darksynth'],
  ),
  'jazz': (
    family: 'acoustic',
    patterns: ['jazz', 'bossa nova', 'swing', 'smooth jazz'],
  ),
  'blues': (family: 'acoustic', patterns: ['blues']),
  'classical': (
    family: 'acoustic',
    patterns: ['classical', 'orchestra', 'symphony', 'piano', 'violin'],
  ),
  'acoustic': (
    family: 'acoustic',
    patterns: [
      'acoustic',
      'unplugged',
      'fingerstyle',
      'folk',
      'singer-songwriter',
    ],
  ),
  'country': (family: 'acoustic', patterns: ['country', 'bluegrass']),
  'latin': (
    family: 'latin',
    patterns: ['latin', 'reggaeton', 'salsa', 'bachata', 'cumbia', 'corrido'],
  ),
  'reggae': (family: 'latin', patterns: ['reggae', 'dancehall', 'dub', 'ska']),
  'afrobeats': (
    family: 'latin',
    patterns: ['afrobeat', 'afrobeats', 'amapiano'],
  ),
  'funk': (family: 'groove', patterns: ['funk', 'disco', 'groove', 'boogie']),
  'soundtrack': (
    family: 'cinematic',
    patterns: ['soundtrack', 'ost', 'cinematic', 'film score', 'epic music'],
  ),
};

/// Canonical mood -> words that signal it.
const Map<String, List<String>> _moods = {
  'chill': [
    'chill',
    'relax',
    'calm',
    'mellow',
    'soft',
    'sleep',
    'study',
    'cozy',
    'peaceful',
    'rainy',
    'late night',
    'slowed',
    'reverb',
    'dreamy',
    'lazy',
  ],
  'sad': [
    'sad',
    'heartbreak',
    'melancholy',
    'cry',
    'lonely',
    'broken',
    'pain',
    'miss you',
    'tears',
    'depress',
  ],
  'happy': [
    'happy',
    'upbeat',
    'feel good',
    'feel-good',
    'sunny',
    'summer',
    'fun',
    'joy',
    'good vibes',
    'positive',
  ],
  'romantic': ['love', 'romantic', 'romance', 'valentine', 'kiss'],
  'dark': ['dark', 'creepy', 'haunting', 'horror', 'gothic', 'evil'],
  'energetic': [
    'hype',
    'workout',
    'gym',
    'pump',
    'banger',
    'drop',
    'bass boosted',
    'rage',
    'aggressive',
    'loud',
    'energy',
    'energetic',
    'party',
    'turn up',
    'fast',
    'hard',
    'heavy',
  ],
  'epic': ['epic', 'cinematic', 'orchestral', 'heroic', 'triumph'],
};

/// Moods that cancel each other out when comparing two tracks.
const List<(String, String)> _opposingMoods = [
  ('chill', 'energetic'),
  ('sad', 'happy'),
  ('chill', 'epic'),
  ('romantic', 'dark'),
];

/// Typical energy (0 calm .. 1 intense) of a genre, used as a prior when the
/// metadata has no explicit mood words.
const Map<String, double> _genreEnergy = {
  'lofi': 0.2,
  'ambient': 0.1,
  'classical': 0.25,
  'jazz': 0.35,
  'blues': 0.35,
  'acoustic': 0.3,
  'r&b': 0.45,
  'indie': 0.5,
  'soundtrack': 0.5,
  'country': 0.5,
  'hip hop': 0.6,
  'pop': 0.6,
  'k-pop': 0.7,
  'funk': 0.65,
  'latin': 0.7,
  'reggae': 0.5,
  'afrobeats': 0.7,
  'synthwave': 0.6,
  'rock': 0.7,
  'house': 0.75,
  'edm': 0.85,
  'trap': 0.8,
  'techno': 0.85,
  'dubstep': 0.95,
  'metal': 0.95,
};

const List<String> _lowEnergyWords = [
  'slow',
  'slowed',
  'calm',
  'relax',
  'soft',
  'gentle',
  'sleep',
  'mellow',
  'quiet',
  'lullaby',
  'peaceful',
  'acoustic',
  'ambient',
  'study',
  'chill',
];

const List<String> _highEnergyWords = [
  'hype',
  'workout',
  'gym',
  'bass boosted',
  'rage',
  'aggressive',
  'loud',
  'energy',
  'banger',
  'drop',
  'party',
  'fast',
  'hard',
  'heavy',
  'turn up',
  'pump',
  'extreme',
];

/// Words that mark a result as something other than a single track, so it
/// should not be queued as "more like this".
const List<String> _notASongWords = [
  'mix',
  'playlist',
  'hours',
  'hour',
  'compilation',
  'full album',
  'reaction',
  'tutorial',
  'podcast',
  'interview',
  'trailer',
  'live stream',
  'livestream',
  '24/7',
  'nonstop',
  'non-stop',
  'megamix',
  'top 10',
  'top 50',
];

/// What a track sounds like, as far as its metadata says.
class VibeProfile {
  const VibeProfile({
    required this.ytid,
    required this.artist,
    required this.genres,
    required this.moods,
    required this.energy,
    this.durationSeconds,
    this.hasRichMetadata = false,
  });

  final String ytid;
  final String artist;

  /// Canonical genre names, best match first.
  final List<String> genres;

  /// Canonical mood names, best match first.
  final List<String> moods;

  /// 0 (very calm) .. 1 (very intense).
  final double energy;
  final int? durationSeconds;

  /// False when the profile came from a title alone (search/related results
  /// carry no tags or description), so its genre/mood read is weaker.
  final bool hasRichMetadata;

  /// Short human label such as "chill lofi", for toasts and search queries.
  String get label {
    final parts = <String>[
      if (moods.isNotEmpty) moods.first,
      if (genres.isNotEmpty) genres.first,
    ];
    return parts.join(' ');
  }

  /// How calm / intense the track is, as a word.
  String get energyLabel => energy < 0.35
      ? 'low'
      : energy < 0.65
      ? 'medium'
      : 'high';
}

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[_\-]+(?=\w)'), ' ');

/// Counts occurrences of [pattern] in [text] as a whole word or phrase, so
/// "rap" does not match "wrapped" and "ost" does not match "most".
int _countWord(String text, String pattern) {
  if (text.isEmpty) return 0;
  final p = RegExp.escape(_normalize(pattern));
  return RegExp('(?<![a-z0-9])$p(?![a-z0-9])').allMatches(text).length;
}

/// Builds a [VibeProfile] from a track's metadata.
///
/// [title], [author] and [keywords] are weighted double against
/// [description], which tends to hold links and unrelated text.
VibeProfile buildVibeProfile({
  required String ytid,
  required String title,
  required String author,
  Iterable<String> keywords = const [],
  String description = '',
  int? durationSeconds,
}) {
  final primary = _normalize('$title $author ${keywords.join(' ')}');
  final secondary = _normalize(
    description.length > 600 ? description.substring(0, 600) : description,
  );
  final hasRich = keywords.isNotEmpty || description.isNotEmpty;

  int score(List<String> patterns) {
    var total = 0;
    for (final p in patterns) {
      total += 2 * _countWord(primary, p) + _countWord(secondary, p);
    }
    return total;
  }

  List<String> rank(Map<String, int> scores, int minScore, int limit) {
    final hits = scores.entries.where((e) => e.value >= minScore).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return hits.take(limit).map((e) => e.key).toList();
  }

  final genreScores = {
    for (final e in _genres.entries) e.key: score(e.value.patterns),
  };
  final moodScores = {for (final e in _moods.entries) e.key: score(e.value)};

  final genres = rank(genreScores, 2, 3);
  final moods = rank(moodScores, 2, 2);

  // Explicit words move the needle; the genre prior sets the starting point.
  final priors = genres
      .map((g) => _genreEnergy[g])
      .whereType<double>()
      .toList();
  final prior = priors.isEmpty
      ? 0.5
      : priors.reduce((a, b) => a + b) / priors.length;
  final low = score(_lowEnergyWords);
  final high = score(_highEnergyWords);
  final energy = (prior + 0.08 * (high - low)).clamp(0.0, 1.0);

  return VibeProfile(
    ytid: ytid,
    artist: author,
    genres: genres,
    moods: moods,
    energy: energy,
    durationSeconds: durationSeconds,
    hasRichMetadata: hasRich,
  );
}

/// True when [title] looks like a mix, playlist, stream or other non-track.
bool looksLikeNonSong(String title) {
  final t = _normalize(title);
  return _notASongWords.any((w) => _countWord(t, w) > 0);
}

/// How well [candidate] matches [seed]; higher is closer. Roughly -10..+10.
///
/// [relatedRank] is the 0-based position YouTube gave the candidate in the
/// seed's related list (null when it came from elsewhere), [relatedCount]
/// the length of that list.
double scoreVibeMatch(
  VibeProfile seed,
  VibeProfile candidate,
  String candidateTitle, {
  int? relatedRank,
  int relatedCount = 0,
}) {
  var score = 0.0;

  // Genre: sharing the exact genre counts most, a neighbouring one less.
  if (seed.genres.isNotEmpty && candidate.genres.isNotEmpty) {
    var best = -2.0;
    for (final cg in candidate.genres) {
      for (final sg in seed.genres) {
        if (cg == sg) {
          best = math.max(best, 3);
        } else if (_genres[cg]?.family == _genres[sg]?.family) {
          best = math.max(best, 1);
        }
      }
    }
    score += best;
  }

  // Mood: shared moods help, opposite ones hurt.
  final shared = candidate.moods.where(seed.moods.contains).length;
  score += math.min(shared, 2) * 1.5;
  for (final (a, b) in _opposingMoods) {
    final clash =
        (seed.moods.contains(a) && candidate.moods.contains(b)) ||
        (seed.moods.contains(b) && candidate.moods.contains(a));
    if (clash) score -= 2;
  }

  // Energy: staying close keeps the same loudness / tempo feel.
  score -= 5 * (seed.energy - candidate.energy).abs();

  // A little same-artist bonus, but not enough to turn it into an artist radio.
  if (candidate.artist.isNotEmpty &&
      candidate.artist.toLowerCase() == seed.artist.toLowerCase()) {
    score += 0.5;
  }

  // Length: skip anything far longer or shorter than the seed.
  final sd = seed.durationSeconds;
  final cd = candidate.durationSeconds;
  if (sd != null && cd != null && sd > 0) {
    final ratio = cd / sd;
    if (ratio < 0.4 || ratio > 2.5) score -= 1.5;
  }
  if (cd != null && cd > 15 * 60 && (sd ?? 0) <= 15 * 60) score -= 3;

  if (looksLikeNonSong(candidateTitle)) score -= 3;

  if (relatedRank != null && relatedCount > 0) {
    score += 1.5 * (1 - relatedRank / relatedCount);
  }

  return score;
}

/// Search phrases that reach tracks with the same vibe as [seed].
List<String> buildVibeSearchQueries(VibeProfile seed) {
  final genre = seed.genres.isNotEmpty ? seed.genres.first : '';
  final mood = seed.moods.isNotEmpty ? seed.moods.first : '';
  final queries = <String>[];

  if (genre.isNotEmpty || mood.isNotEmpty) {
    queries.add('$mood $genre songs'.trim());
  }
  if (seed.genres.length > 1) {
    queries.add('${seed.genres[0]} ${seed.genres[1]} $mood'.trim());
  }
  if (seed.artist.isNotEmpty && (genre.isNotEmpty || mood.isNotEmpty)) {
    queries.add('songs like ${seed.artist} $genre'.trim());
  }
  return queries.take(3).toList();
}

/// Keeps at most [perArtist] songs per artist so a batch does not collapse
/// into one artist's catalogue. Order is preserved.
List<T> limitPerArtist<T>(
  Iterable<T> items,
  String Function(T) artistOf, {
  int perArtist = 2,
}) {
  final counts = <String, int>{};
  final out = <T>[];
  for (final item in items) {
    final key = artistOf(item).toLowerCase();
    final n = counts[key] ?? 0;
    if (n < perArtist) {
      counts[key] = n + 1;
      out.add(item);
    }
  }
  return out;
}
