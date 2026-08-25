import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

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
  static const MethodChannel _mediaChannel = MethodChannel(
    'com.christianfontalvo.mp3player/media',
  );
  StreamSubscription<PlayerState>? _playerSubscription;
  StreamSubscription<int?>? _indexSubscription;
  List<LibrarySong> _songs = [];
  String? _selectedFolderName;
  int? _currentIndex;
  bool _playlistConfigured = false;
  bool _loading = true;
  String? _error;

  LibrarySong? get _currentSong =>
      _currentIndex == null ? null : _songs[_currentIndex!];

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!mounted || index == null || index >= _songs.length) return;
      setState(() => _currentIndex = index);
    });
    unawaited(_initializeLibrary());
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
          _currentIndex = null;
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
      final currentSongId = _currentSong?.id;
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
        final currentIndex = libraryChanged || currentSongId == null
            ? -1
            : allSongs.indexWhere((song) => song.id == currentSongId);
        setState(() {
          _songs = allSongs;
          _currentIndex = currentIndex < 0 ? null : currentIndex;
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
            _currentIndex = null;
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

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    try {
      if (!_playlistConfigured) {
        await _player.setAudioSources(
          _songs.map(_audioSourceFor).toList(growable: false),
          initialIndex: index,
          initialPosition: Duration.zero,
        );
        _playlistConfigured = true;
      } else {
        await _player.seek(Duration.zero, index: index);
      }
      if (mounted) setState(() => _currentIndex = index);
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

  AudioSource _audioSourceFor(LibrarySong song) => AudioSource.uri(
    Uri.parse(song.uri),
    tag: MediaItem(
      id: song.id,
      title: song.title.isEmpty ? song.displayName : song.title,
      artist: song.artist,
      album: song.folder ?? _selectedFolderName,
    ),
  );

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
          onPressed: _showLibrarySettings,
          icon: const Icon(Icons.settings),
          tooltip: 'Carpeta de música',
        ),
      ],
    ),
    bottomNavigationBar: _currentSong == null ? null : _buildPlayer(),
    body: Column(
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
    ),
  );

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
            selected: index == _currentIndex,
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
                      ? () => _playSong(_currentIndex! - 1)
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
                  onPressed: _currentIndex! < _songs.length - 1
                      ? () => _playSong(_currentIndex! + 1)
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
