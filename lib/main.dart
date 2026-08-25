import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class _MusicPageState extends State<MusicPage> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  List<SongModel> _songs = [];
  List<String> _folders = [];
  String? _selectedFolder;
  int? _currentIndex;
  bool _loading = true;
  bool _permissionDenied = false;
  String? _error;

  SongModel? get _currentSong =>
      _currentIndex == null ? null : _songs[_currentIndex!];

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_initializeLibrary());
  }

  Future<void> _initializeLibrary() async {
    final preferences = await SharedPreferences.getInstance();
    _selectedFolder = preferences.getString('music_folder');
    await _loadSongs();
  }

  Future<void> _loadSongs({bool retryPermission = false}) async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _error = null;
    });
    try {
      final allowed = await _audioQuery.checkAndRequest(
        retryRequest: retryPermission,
      );
      if (!allowed) {
        if (mounted) {
          setState(() {
            _loading = false;
            _permissionDenied = true;
          });
        }
        return;
      }
      final folders = await _audioQuery.queryAllPath();
      folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (_selectedFolder != null && !folders.contains(_selectedFolder)) {
        _selectedFolder = null;
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove('music_folder');
      }

      final currentSongId = _currentSong?.id;
      final result = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
        path: _selectedFolder,
      );
      final songs = result
          .where((song) => song.isMusic != false && song.uri != null)
          .toList(growable: false);
      if (mounted) {
        final currentIndex = currentSongId == null
            ? -1
            : songs.indexWhere((song) => song.id == currentSongId);
        setState(() {
          _folders = folders;
          _songs = songs;
          _currentIndex = currentIndex < 0 ? null : currentIndex;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Error al consultar MediaStore: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo leer la biblioteca de audio.';
        });
      }
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(song.uri!)));
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

  Future<void> _selectFolder(String? folder) async {
    if (folder == _selectedFolder) return;
    await _player.stop();
    final preferences = await SharedPreferences.getInstance();
    if (folder == null) {
      await preferences.remove('music_folder');
    } else {
      await preferences.setString('music_folder', folder);
    }
    if (!mounted) return;
    setState(() {
      _selectedFolder = folder;
      _currentIndex = null;
    });
    await _loadSongs();
  }

  Future<void> _showLibrarySettings() async {
    final choice = await showModalBottomSheet<_LibraryChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.folder),
                title: Text('Carpeta de música'),
                subtitle: Text('Elige qué canciones quieres mostrar'),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.library_music),
                      title: const Text('Toda la música'),
                      trailing: _selectedFolder == null
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(
                        context,
                        const _LibraryChoice(folder: null),
                      ),
                    ),
                    for (final folder in _folders)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(_folderName(folder)),
                        subtitle: Text(
                          folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: folder == _selectedFolder
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                          context,
                          _LibraryChoice(folder: folder),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Actualizar biblioteca'),
                onTap: () =>
                    Navigator.pop(context, const _LibraryChoice(refresh: true)),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (choice.refresh) {
      await _loadSongs();
    } else {
      await _selectFolder(choice.folder);
    }
  }

  String _folderName(String folder) {
    final normalized = folder.replaceAll('\\', '/');
    return normalized.split('/').where((part) => part.isNotEmpty).lastOrNull ??
        folder;
  }

  @override
  void dispose() {
    unawaited(_playerSubscription?.cancel());
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
          onPressed: _loading ? null : _showLibrarySettings,
          icon: const Icon(Icons.settings),
          tooltip: 'Ajustes y carpetas',
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
        if (_selectedFolder != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Carpeta: ${_folderName(_selectedFolder!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(child: _buildLibrary()),
      ],
    ),
  );

  Widget _buildLibrary() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_permissionDenied) {
      return _EmptyState(
        message:
            'Permite el acceso a música y audio para mostrar tus canciones.',
        buttonLabel: 'Conceder permiso',
        onPressed: () => _loadSongs(retryPermission: true),
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
        message: 'No se encontró música en la biblioteca del dispositivo.',
        buttonLabel: 'Actualizar',
        onPressed: _loadSongs,
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
              song.title.isEmpty ? song.displayNameWOExt : song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: song.artist == null ? null : Text(song.artist!),
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
                  onPressed: () =>
                      _player.playing ? _player.pause() : _player.play(),
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

class _LibraryChoice {
  const _LibraryChoice({this.folder, this.refresh = false});

  final String? folder;
  final bool refresh;
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
