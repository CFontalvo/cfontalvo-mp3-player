import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/music_playlist.dart';
import 'package:mp3_player/playlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('guarda y restaura listas con sus canciones', () async {
    final repository = PlaylistRepository();
    const playlists = [
      MusicPlaylist(
        id: 'favoritas',
        name: 'Mis favoritas',
        songIds: ['content://song/1', 'content://song/2'],
      ),
      MusicPlaylist(id: 'relajarse', name: 'Para relajarme', songIds: []),
    ];

    await repository.save(playlists);
    final restored = await PlaylistRepository().load();

    expect(restored, hasLength(2));
    expect(restored.first.id, 'favoritas');
    expect(restored.first.name, 'Mis favoritas');
    expect(restored.first.songIds, ['content://song/1', 'content://song/2']);
    expect(restored.last.songIds, isEmpty);
  });

  test(
    'devuelve una lista vacía si los datos guardados están dañados',
    () async {
      SharedPreferences.setMockInitialValues({
        'music_playlists_v1': 'contenido inválido',
      });

      final restored = await PlaylistRepository().load();

      expect(restored, isEmpty);
    },
  );

  test('el modelo conserva nombre, identificador y orden de canciones', () {
    const playlist = MusicPlaylist(
      id: 'viaje',
      name: 'Viaje',
      songIds: ['tercera', 'primera', 'segunda'],
    );

    final restored = MusicPlaylist.fromJson(playlist.toJson());

    expect(restored.id, playlist.id);
    expect(restored.name, playlist.name);
    expect(restored.songIds, playlist.songIds);
  });
}
