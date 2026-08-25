# CFontalvo MP3

Reproductor local de música para Android, construido con Flutter. Usa el
selector de carpetas del sistema (Storage Access Framework) y reproduce URI de
contenido, por lo que no depende de rutas privadas ni de comportamientos
específicos de Samsung/Xiaomi.

El usuario elige explícitamente la carpeta que contiene su música. La aplicación
solo puede leer esa carpeta y sus subcarpetas, conserva el permiso entre
aperturas y permite cambiar la selección o actualizar las canciones desde el
botón de ajustes. No escanea grabaciones, tonos ni otras ubicaciones del
dispositivo.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

La aplicación soporta Android 5.0 o posterior (`minSdk 21`) y compila/apunta a
Android 16 (`compileSdk`/`targetSdk` 36). No declara permisos generales de
almacenamiento o audio; Android concede acceso de lectura únicamente a la
carpeta elegida.

Consulta [PLAY_RELEASE.md](PLAY_RELEASE.md) para firma y publicación.
