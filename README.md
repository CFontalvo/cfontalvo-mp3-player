# CFontalvo MP3

Reproductor local de música para Android, construido con Flutter. Lee la
biblioteca mediante MediaStore y reproduce sus URI de contenido, por lo que no
depende de rutas privadas o específicas de Samsung/Xiaomi.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

La aplicación soporta Android 5.0 o posterior (`minSdk 21`) y compila/apunta a
Android 16 (`compileSdk`/`targetSdk` 36). Solo solicita acceso de lectura a audio:
`READ_EXTERNAL_STORAGE` hasta Android 12L y `READ_MEDIA_AUDIO` desde Android 13.

Consulta [PLAY_RELEASE.md](PLAY_RELEASE.md) para firma y publicación.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
