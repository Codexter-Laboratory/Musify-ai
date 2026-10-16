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

import 'dart:async';

import 'package:musify/main.dart';
import 'package:musify/services/proxy_manager.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:musify/utilities/vibe_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// How many of the best pre-ranked candidates get a full metadata lookup
/// (tags + description) before the final ranking.
const _detailLookups = 14;
const _requestTimeout = Duration(seconds: 8);

VibeProfile _profileOf(Video video) => buildVibeProfile(
  ytid: video.id.value,
  title: video.title,
  author: video.author,
  keywords: video.keywords,
  description: video.description,
  durationSeconds: video.duration?.inSeconds,
);

/// Pairs a candidate with the video it was built from.
class _Entry {
  _Entry(this.video, int? relatedRank)
    : candidate = VibeCandidate(
        profile: _profileOf(video),
        title: video.title,
        relatedRank: relatedRank,
      );

  Video video;
  final VibeCandidate candidate;

  /// Re-reads the profile once the full video details are known.
  void update(Video detailed) {
    video = detailed;
    candidate
      ..profile = _profileOf(detailed)
      ..title = detailed.title;
  }
}

/// The vibe of the song with id [ytid], or null when it cannot be looked up.
Future<VibeProfile?> fetchVibeProfile(String ytid) async {
  try {
    final video = await ytClient.videos.get(ytid).timeout(_requestTimeout);
    return _profileOf(video);
  } catch (e, stackTrace) {
    logger.log('Error building vibe profile', error: e, stackTrace: stackTrace);
    return null;
  }
}

/// Finds up to [limit] songs that match [seed]'s genre, mood and energy,
/// best match first, skipping every id in [excludedYtIds].
///
/// Candidates come from YouTube's related videos for the seed plus searches
/// built from its genre and mood. They are ranked cheaply from their titles,
/// then the strongest ones are looked up in full (tags, description) and
/// ranked again, so the final order rests on real metadata.
Future<List<Map<String, dynamic>>> fetchVibeMatches(
  VibeProfile seed, {
  Set<String> excludedYtIds = const {},
  int limit = 10,
}) async {
  try {
    final pool = <String, _Entry>{};

    void add(Video video, {int? relatedRank}) {
      final id = video.id.value;
      if (id == seed.ytid || excludedYtIds.contains(id) || video.isLive) return;
      pool.putIfAbsent(id, () => _Entry(video, relatedRank));
    }

    var relatedCount = 0;
    await Future.wait([
      () async {
        try {
          final seedVideo = await ytClient.videos
              .get(seed.ytid)
              .timeout(_requestTimeout);
          final related =
              await ytClient.videos.getRelatedVideos(seedVideo) ?? [];
          relatedCount = related.length;
          for (var i = 0; i < related.length; i++) {
            add(related[i], relatedRank: i);
          }
        } catch (e, stackTrace) {
          logger.log(
            'Vibe: related videos failed',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }(),
      for (final query in buildVibeSearchQueries(seed))
        () async {
          try {
            final results = await ytClient.search
                .search(query)
                .timeout(_requestTimeout);
            for (final video in results.take(12)) {
              add(video);
            }
          } catch (e, stackTrace) {
            logger.log(
              'Vibe: search "$query" failed',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }(),
    ]);

    if (pool.isEmpty) return [];

    // First pass: rank on titles alone, since search and related results
    // carry no tags or description.
    final entries = pool.values.toList();
    final firstPass = selectVibeMatches(
      seed,
      [for (final e in entries) e.candidate],
      relatedCount: relatedCount,
      limit: _detailLookups,
      floorScore: double.negativeInfinity,
    );

    // Second pass: look the front-runners up in full and rank again.
    final shortlist = entries
        .where((e) => firstPass.contains(e.candidate))
        .toList();
    await Future.wait(
      shortlist.map((e) async {
        try {
          e.update(
            await ytClient.videos
                .get(e.video.id.value)
                .timeout(_requestTimeout),
          );
        } catch (_) {
          // Keep the title-only candidate; it was still ranked.
        }
      }),
    );

    final byCandidate = {for (final e in entries) e.candidate: e};
    final finalists = selectVibeMatches(
      seed,
      [for (final e in shortlist) e.candidate],
      relatedCount: relatedCount,
      limit: limit,
    );
    return [
      for (final c in finalists) returnSongLayout(0, byCandidate[c]!.video),
    ];
  } catch (e, stackTrace) {
    logger.log('Error fetching vibe matches', error: e, stackTrace: stackTrace);
    return [];
  }
}
