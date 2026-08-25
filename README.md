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

La reproducción continúa de forma confiable en segundo plano mediante un
servicio multimedia. Android muestra controles de reproducir, pausar, detener,
anterior y siguiente en la notificación, la pantalla bloqueada y dispositivos
compatibles como audífonos.

## Descargar

La versión beta más reciente puede descargarse desde
[GitHub Releases](https://github.com/CFontalvo/cfontalvo-mp3-player/releases/latest).
En Android puede ser necesario autorizar temporalmente la instalación desde el
navegador o administrador de archivos utilizado para abrir el APK.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

La aplicación soporta Android 7.0 o posterior (`minSdk 24`) y compila/apunta a
Android 16 (`compileSdk`/`targetSdk` 36). No declara permisos generales de
almacenamiento o audio; Android concede acceso de lectura únicamente a la
carpeta elegida.

## Versiones instalables

Los APK de prueba se publican como archivos de las versiones de GitHub y no se
guardan dentro del historial del código. Una beta firmada con la clave local de
desarrollo sirve para pruebas y distribución privada, pero no reemplaza el AAB
firmado con la clave de carga requerido por Google Play.

Consulta [PLAY_RELEASE.md](PLAY_RELEASE.md) para firma y publicación.

## Licencia y seguridad

El código se distribuye bajo la [GNU General Public License v3.0](LICENSE).
Consulta [SECURITY.md](SECURITY.md) para informar una vulnerabilidad sin
publicar detalles sensibles.
