import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/playlist_playback.dart';

void main() {
  test('mantiene el orden de la lista en el modo normal', () {
    final queue = buildPlaybackQueue(['uno', 'dos', 'tres'], shuffled: false);

    expect(queue, ['uno', 'dos', 'tres']);
  });

  test('el modo aleatorio conserva canciones y cambia el orden', () {
    const songs = ['uno', 'dos', 'tres', 'cuatro'];

    final queue = buildPlaybackQueue(songs, shuffled: true, random: Random(7));

    expect(queue, isNot(songs));
    expect(queue.toSet(), songs.toSet());
  });

  test('el modo aleatorio funciona con listas de una canción', () {
    final queue = buildPlaybackQueue(['única'], shuffled: true);

    expect(queue, ['única']);
  });
}
