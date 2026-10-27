import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'music_playlist.dart';

class PlaylistRepository {
  PlaylistRepository({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _storageKey = 'music_playlists_v1';
  final Future<SharedPreferences> _preferences;

  Future<List<MusicPlaylist>> load() async {
    final preferences = await _preferences;
    final storedValue = preferences.getString(_storageKey);
    if (storedValue == null || storedValue.isEmpty) return const [];

    try {
      final decoded = jsonDecode(storedValue);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => MusicPlaylist.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<MusicPlaylist> playlists) async {
    final preferences = await _preferences;
    final encoded = jsonEncode(
      playlists.map((playlist) => playlist.toJson()).toList(growable: false),
    );
    final saved = await preferences.setString(_storageKey, encoded);
    if (!saved) {
      throw StateError('No se pudieron guardar las listas de música.');
    }
  }
}
