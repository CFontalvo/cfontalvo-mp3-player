class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.songIds,
  });

  factory MusicPlaylist.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final songIds = json['songIds'];
    if (id is! String || name is! String || songIds is! List) {
      throw const FormatException('Lista de música inválida.');
    }
    return MusicPlaylist(
      id: id,
      name: name,
      songIds: songIds.whereType<String>().toList(growable: false),
    );
  }

  final String id;
  final String name;
  final List<String> songIds;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'songIds': songIds};
}
