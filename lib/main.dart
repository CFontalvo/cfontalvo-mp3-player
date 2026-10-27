import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'music_playlist.dart';
import 'playlist_playback.dart';
import 'playlist_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.christianfontalvo.mp3player.playback',
    androidNotificationChannelName: 'Reproducción de música',
    androidNotificationChannelDescription:
        'Controles del reproductor mientras la música está sonando.',
    androidNotificationIcon: 'drawable/ic_stat_music_note',
    androidShowNotificationBadge: false,
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  runApp(const Mp3PlayerApp());
}

class Mp3PlayerApp extends StatelessWidget {
  const Mp3PlayerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'CFontalvo MP3',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF050805),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00FF66),
        brightness: Brightness.dark,
      ),
    ),
    home: const MusicPage(),
  );
}

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class LibrarySong {
  const LibrarySong({
    required this.id,
    required this.title,
    required this.displayName,
    required this.uri,
    required this.folder,
    this.artist,
  });

  factory LibrarySong.fromMap(Map<Object?, Object?> map) => LibrarySong(
    id: map['id']! as String,
    title: map['title']! as String,
    displayName: map['displayName']! as String,
    uri: map['uri']! as String,
    folder: map['folder'] as String?,
    artist: map['artist'] as String?,
  );

  final String id;
  final String title;
  final String displayName;
  final String uri;
  final String? folder;
  final String? artist;
}

class _MusicPageState extends State<MusicPage> {
  final AudioPlayer _player = AudioPlayer();
  final PlaylistRepository _playlistRepository = PlaylistRepository();
  final Map<String, ExpansibleController> _playlistControllers = {};
  static const MethodChannel _mediaChannel = MethodChannel(
    'com.christianfontalvo.mp3player/media',
  );
  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<int?>? _indexSubscription;
  List<LibrarySong> _songs = [];
  List<LibrarySong> _playbackQueue = [];
  List<MusicPlaylist> _playlists = [];
  String? _selectedFolderName;
  int? _currentIndex;
  bool _playlistConfigured = false;
  bool _playlistsLoading = true;
  bool _loading = true;
  String? _error;

  LibrarySong? get _currentSong {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _playbackQueue.length) {
      return null;
    }
    return _playbackQueue[index];
  }

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!mounted || index == null || index >= _playbackQueue.length) return;
      setState(() => _currentIndex = index);
    });
    unawaited(_initializeLibrary());
    unawaited(_loadPlaylists());
  }

  Future<void> _loadPlaylists() async {
    try {
      final playlists = await _playlistRepository.load();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _playlistsLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Error al cargar las listas: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _playlistsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar tus listas.')),
      );
    }
  }

  Future<void> _initializeLibrary() async {
    try {
      final folder = await _mediaChannel.invokeMapMethod<Object?, Object?>(
        'getSelectedFolder',
      );
      if (!mounted) return;
      if (folder == null) {
        setState(() => _loading = false);
        return;
      }
      _selectedFolderName = folder['name']! as String;
      await _loadSongs();
    } catch (error, stackTrace) {
      debugPrint('Error al restaurar la carpeta: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo restaurar la carpeta seleccionada.';
        });
      }
    }
  }

  Future<void> _loadSongs() async {
    if (_selectedFolderName == null) {
      if (mounted) {
        setState(() {
          _songs = [];
          _playbackQueue = [];
          _currentIndex = null;
          _playlistConfigured = false;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _mediaChannel.invokeListMethod<Object?>(
        'querySongs',
      );
      final allSongs = (result ?? const <Object?>[])
          .map((item) => LibrarySong.fromMap(item! as Map<Object?, Object?>))
          .toList(growable: false);
      if (mounted) {
        final libraryChanged = !listEquals(
          _songs.map((song) => song.uri).toList(growable: false),
          allSongs.map((song) => song.uri).toList(growable: false),
        );
        if (libraryChanged) {
          await _player.stop();
          _playlistConfigured = false;
        }
        if (!mounted) return;
        setState(() {
          _songs = allSongs;
          if (libraryChanged) {
            _playbackQueue = [];
            _currentIndex = null;
          }
          _loading = false;
        });
      }
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Error al consultar la carpeta: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          if (error.code == 'FOLDER_ACCESS_LOST') {
            _selectedFolderName = null;
            _songs = [];
            _playbackQueue = [];
            _currentIndex = null;
            _playlistConfigured = false;
            _error = null;
          } else {
            _error = 'No se pudo leer la carpeta seleccionada.';
          }
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Error al consultar la carpeta: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo leer la biblioteca de audio.';
        });
      }
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final folder = await _mediaChannel.invokeMapMethod<Object?, Object?>(
        'chooseFolder',
      );
      if (!mounted || folder == null) return;
      await _player.stop();
      _playlistConfigured = false;
      setState(() {
        _selectedFolderName = folder['name']! as String;
        _songs = [];
        _playbackQueue = [];
        _currentIndex = null;
      });
      await _loadSongs();
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Error al seleccionar la carpeta: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conceder acceso a esa carpeta.'),
          ),
        );
      }
    }
  }

  Future<void> _playSong(int index) => _playQueue(_songs, index);

  Future<void> _playQueue(List<LibrarySong> queue, int index) async {
    if (index < 0 || index >= queue.length) return;
    final song = queue[index];
    try {
      final queueChanged = !listEquals(
        _playbackQueue.map((song) => song.id).toList(growable: false),
        queue.map((song) => song.id).toList(growable: false),
      );
      if (!_playlistConfigured || queueChanged) {
        _playbackQueue = List<LibrarySong>.unmodifiable(queue);
        await _player.setAudioSources(
          _playbackQueue.map(_audioSourceFor).toList(growable: false),
          initialIndex: index,
          initialPosition: Duration.zero,
        );
        _playlistConfigured = true;
      } else {
        await _player.seek(Duration.zero, index: index);
      }
      if (mounted) {
        setState(() {
          _currentIndex = index;
          _playbackQueue = List<LibrarySong>.unmodifiable(queue);
        });
      }
      await _player.play();
    } catch (error, stackTrace) {
      debugPrint('Error al reproducir ${song.uri}: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo reproducir esta canción.')),
        );
      }
    }
  }

  Future<void> _startPlaylist(
    MusicPlaylist playlist, {
    required bool shuffled,
  }) async {
    final availableSongs = _songsForPlaylist(playlist);
    if (availableSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta lista no tiene canciones disponibles.'),
        ),
      );
      return;
    }
    final queue = buildPlaybackQueue(availableSongs, shuffled: shuffled);
    await _playQueue(queue, 0);
  }

  AudioSource _audioSourceFor(LibrarySong song) => AudioSource.uri(
    Uri.parse(song.uri),
    tag: MediaItem(
      id: song.id,
      title: song.title.isEmpty ? song.displayName : song.title,
      artist: song.artist,
      album: song.folder ?? _selectedFolderName,
    ),
  );

  List<LibrarySong> _songsForPlaylist(MusicPlaylist playlist) {
    final songsById = {for (final song in _songs) song.id: song};
    return playlist.songIds
        .map((id) => songsById[id])
        .whereType<LibrarySong>()
        .toList(growable: false);
  }

  bool _playlistNameExists(String name, {String? exceptId}) => _playlists.any(
    (playlist) =>
        playlist.id != exceptId &&
        playlist.name.toLowerCase() == name.toLowerCase(),
  );

  ExpansibleController _playlistControllerFor(String playlistId) =>
      _playlistControllers.putIfAbsent(playlistId, ExpansibleController.new);

  void _handlePlaylistExpansion(String playlistId, bool expanded) {
    if (!expanded) return;
    for (final entry in _playlistControllers.entries) {
      if (entry.key != playlistId && entry.value.isExpanded) {
        entry.value.collapse();
      }
    }
  }

  Future<bool> _persistPlaylists(List<MusicPlaylist> playlists) async {
    try {
      await _playlistRepository.save(playlists);
      if (!mounted) return false;
      setState(() => _playlists = playlists);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Error al guardar las listas: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron guardar los cambios.')),
        );
      }
      return false;
    }
  }

  Future<void> _editPlaylist([MusicPlaylist? playlist]) async {
    final nameController = TextEditingController(text: playlist?.name);
    final selectedSongIds = Set<String>.of(playlist?.songIds ?? const []);
    String? nameError;

    final draft = await showDialog<_PlaylistDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(playlist == null ? 'Nueva lista' : 'Editar lista'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: playlist == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Nombre de la lista',
                    errorText: nameError,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (nameError != null) {
                      setDialogState(() => nameError = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Canciones (${selectedSongIds.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: _songs.isEmpty
                      ? Center(
                          child: Text(
                            _selectedFolderName == null
                                ? 'Selecciona primero una carpeta de música.'
                                : 'La carpeta seleccionada no contiene canciones.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                            final song = _songs[index];
                            return CheckboxListTile(
                              dense: true,
                              value: selectedSongIds.contains(song.id),
                              title: Text(
                                song.title.isEmpty
                                    ? song.displayName
                                    : song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: song.artist == null
                                  ? null
                                  : Text(song.artist!),
                              onChanged: (selected) {
                                setDialogState(() {
                                  if (selected ?? false) {
                                    selectedSongIds.add(song.id);
                                  } else {
                                    selectedSongIds.remove(song.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(
                    () => nameError = 'Escribe un nombre para la lista.',
                  );
                  return;
                }
                if (_playlistNameExists(name, exceptId: playlist?.id)) {
                  setDialogState(
                    () => nameError = 'Ya existe una lista con ese nombre.',
                  );
                  return;
                }
                final libraryIds = _songs.map((song) => song.id).toSet();
                final unavailableIds = selectedSongIds.where(
                  (id) => !libraryIds.contains(id),
                );
                final orderedAvailableIds = _songs
                    .where((song) => selectedSongIds.contains(song.id))
                    .map((song) => song.id);
                Navigator.pop(
                  dialogContext,
                  _PlaylistDraft(
                    name: name,
                    songIds: [...unavailableIds, ...orderedAvailableIds],
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (draft == null || !mounted) return;

    final updated = List<MusicPlaylist>.of(_playlists);
    if (playlist == null) {
      updated.add(
        MusicPlaylist(
          id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
          name: draft.name,
          songIds: draft.songIds,
        ),
      );
    } else {
      final index = updated.indexWhere((item) => item.id == playlist.id);
      if (index < 0) return;
      updated[index] = MusicPlaylist(
        id: playlist.id,
        name: draft.name,
        songIds: draft.songIds,
      );
    }

    if (await _persistPlaylists(updated) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            playlist == null ? 'Lista creada.' : 'Lista actualizada.',
          ),
        ),
      );
    }
  }

  Future<void> _deletePlaylist(MusicPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text(
          '¿Quieres eliminar "${playlist.name}"? Las canciones no se borrarán '
          'del teléfono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = _playlists
        .where((item) => item.id != playlist.id)
        .toList(growable: false);
    if (await _persistPlaylists(updated) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lista eliminada.')));
    }
  }

  Future<void> _showLibrarySettings() async {
    final choice = await showModalBottomSheet<_LibraryAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Carpeta de música'),
              subtitle: Text(_selectedFolderName ?? 'Ninguna seleccionada'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(
                _selectedFolderName == null
                    ? 'Seleccionar carpeta'
                    : 'Cambiar carpeta',
              ),
              subtitle: const Text(
                'Android dará acceso únicamente a la carpeta elegida',
              ),
              onTap: () => Navigator.pop(context, _LibraryAction.chooseFolder),
            ),
            if (_selectedFolderName != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Actualizar canciones'),
                onTap: () => Navigator.pop(context, _LibraryAction.refresh),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case _LibraryAction.chooseFolder:
        await _chooseFolder();
        break;
      case _LibraryAction.refresh:
        await _loadSongs();
        break;
    }
  }

  @override
  void dispose() {
    unawaited(_playerSubscription?.cancel());
    unawaited(_indexSubscription?.cancel());
    unawaited(_player.dispose());
    for (final controller in _playlistControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF050805),
        centerTitle: true,
        title: const Text(
          'CFONTALVO MP3',
          style: TextStyle(
            color: Color(0xFF00FF66),
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _playlistsLoading ? null : () => _editPlaylist(),
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Nueva lista',
          ),
          IconButton(
            onPressed: _showLibrarySettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Carpeta de música',
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.library_music), text: 'Canciones'),
            Tab(icon: Icon(Icons.queue_music), text: 'Mis listas'),
          ],
        ),
      ),
      bottomNavigationBar: _currentSong == null ? null : _buildPlayer(),
      body: TabBarView(children: [_buildLibraryTab(), _buildPlaylists()]),
    ),
  );

  Widget _buildLibraryTab() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Image.asset(
          'assets/cfontalvo_logo_250.png',
          height: 110,
          fit: BoxFit.contain,
        ),
      ),
      if (_selectedFolderName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Carpeta: $_selectedFolderName',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      Expanded(child: _buildLibrary()),
    ],
  );

  Widget _buildPlaylists() {
    if (_playlistsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_playlists.isEmpty) {
      return _EmptyState(
        message:
            'Crea listas con tus canciones favoritas. Puedes cambiar su '
            'nombre, agregar o quitar canciones cuando quieras.',
        buttonLabel: 'Crear mi primera lista',
        onPressed: () => _editPlaylist(),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      itemCount: _playlists.length,
      itemBuilder: (context, index) => _buildPlaylistCard(_playlists[index]),
    );
  }

  Widget _buildPlaylistCard(MusicPlaylist playlist) {
    final availableSongs = _songsForPlaylist(playlist);
    final unavailableCount = playlist.songIds.length - availableSongs.length;
    final countLabel = playlist.songIds.length == 1
        ? '1 canción'
        : '${playlist.songIds.length} canciones';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey(playlist.id),
        controller: _playlistControllerFor(playlist.id),
        onExpansionChanged: (expanded) =>
            _handlePlaylistExpansion(playlist.id, expanded),
        leading: const Icon(Icons.queue_music, color: Color(0xFF00FF66)),
        title: Text(playlist.name),
        subtitle: Text(
          unavailableCount == 0
              ? countLabel
              : '$countLabel · $unavailableCount no disponibles',
        ),
        trailing: PopupMenuButton<_PlaylistAction>(
          tooltip: 'Opciones de la lista',
          onSelected: (action) {
            switch (action) {
              case _PlaylistAction.edit:
                unawaited(_editPlaylist(playlist));
                break;
              case _PlaylistAction.delete:
                unawaited(_deletePlaylist(playlist));
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _PlaylistAction.edit,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit),
                title: Text('Modificar'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.delete,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('Eliminar'),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: availableSongs.isEmpty
                      ? null
                      : () => _startPlaylist(playlist, shuffled: false),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Reproducir en orden'),
                ),
                OutlinedButton.icon(
                  onPressed: availableSongs.isEmpty
                      ? null
                      : () => _startPlaylist(playlist, shuffled: true),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Reproducción aleatoria'),
                ),
              ],
            ),
          ),
          if (availableSongs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text(
                playlist.songIds.isEmpty
                    ? 'Esta lista está vacía. Usa Modificar para agregar canciones.'
                    : 'Las canciones de esta lista no están en la carpeta actual.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (var index = 0; index < availableSongs.length; index++)
              ListTile(
                dense: true,
                selected: _currentSong?.id == availableSongs[index].id,
                leading: const Icon(Icons.music_note),
                title: Text(
                  availableSongs[index].title.isEmpty
                      ? availableSongs[index].displayName
                      : availableSongs[index].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: availableSongs[index].artist == null
                    ? null
                    : Text(availableSongs[index].artist!),
                onTap: () => _playQueue(availableSongs, index),
              ),
        ],
      ),
    );
  }

  Widget _buildLibrary() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_selectedFolderName == null) {
      return _EmptyState(
        message:
            _error ??
            'Selecciona la carpeta donde guardas tu música. La aplicación '
                'solo podrá leer esa carpeta y sus subcarpetas.',
        buttonLabel: 'Seleccionar carpeta',
        onPressed: _chooseFolder,
      );
    }
    if (_error != null) {
      return _EmptyState(
        message: _error!,
        buttonLabel: 'Reintentar',
        onPressed: _loadSongs,
      );
    }
    if (_songs.isEmpty) {
      return _EmptyState(
        message:
            'No se encontraron archivos de audio en '
            '"$_selectedFolderName".',
        buttonLabel: 'Elegir otra carpeta',
        onPressed: _chooseFolder,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSongs,
      child: ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (context, index) {
          final song = _songs[index];
          return ListTile(
            selected: song.id == _currentSong?.id,
            leading: const Icon(Icons.music_note, size: 40),
            title: Text(
              song.title.isEmpty ? song.displayName : song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: switch ((song.artist, song.folder)) {
              (final artist?, _) => Text(artist),
              (_, final folder?) => Text(folder),
              _ => null,
            },
            onTap: () => _playSong(index),
          );
        },
      ),
    );
  }

  Widget _buildPlayer() {
    final song = _currentSong!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final duration = _player.duration ?? Duration.zero;
                final position = snapshot.data ?? Duration.zero;
                final maximum = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                return Slider(
                  max: maximum,
                  value: position.inMilliseconds
                      .clamp(0, maximum.toInt())
                      .toDouble(),
                  onChanged: duration == Duration.zero
                      ? null
                      : (value) =>
                            _player.seek(Duration(milliseconds: value.toInt())),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentIndex! > 0
                      ? () => _playQueue(_playbackQueue, _currentIndex! - 1)
                      : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  onPressed: () async {
                    if (_player.playing) {
                      await _player.pause();
                    } else {
                      if (_player.processingState ==
                          ProcessingState.completed) {
                        await _player.seek(Duration.zero);
                      }
                      await _player.play();
                    }
                  },
                  icon: Icon(
                    _player.playing ? Icons.pause_circle : Icons.play_circle,
                    size: 48,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    await _player.stop();
                    await _player.seek(Duration.zero);
                  },
                  icon: const Icon(Icons.stop),
                ),
                IconButton(
                  onPressed: _currentIndex! < _playbackQueue.length - 1
                      ? () => _playQueue(_playbackQueue, _currentIndex! + 1)
                      : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _LibraryAction { chooseFolder, refresh }

enum _PlaylistAction { edit, delete }

class _PlaylistDraft {
  const _PlaylistDraft({required this.name, required this.songIds});

  final String name;
  final List<String> songIds;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    ),
  );
}
