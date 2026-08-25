# Preparación para Google Play

## Estado técnico

- ID de aplicación definitivo: `com.christianfontalvo.mp3player`, basado en `christianfontalvo.com`.
- Versión actual: `1.1.0+2`. Incrementar el número después de `+` en cada carga.
- Android: mínimo API 24; objetivo y compilación API 36.
- Formato de publicación: Android App Bundle (`.aab`).
- Datos: procesamiento local; la app no transmite ni comparte datos.
- Acceso: el usuario concede lectura solamente a la carpeta que selecciona con
  el selector de Android; el acceso se conserva para poder usarla al reabrir.
- No se declaran `READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE` ni permisos de
  fotos, videos o grabaciones.
- No se solicita acceso amplio a archivos (`MANAGE_EXTERNAL_STORAGE`).

## Clave de carga y Play App Signing

1. Generar una clave de carga fuera del repositorio:
   `keytool -genkeypair -v -keystore cfontalvo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Guardar el `.jks` y sus contraseñas en un gestor seguro con copia de respaldo.
3. Copiar `android/key.properties.example` a `android/key.properties` y completar los valores.
4. Ejecutar `flutter build appbundle --release`.
5. Inscribirse en Play App Signing al crear la aplicación y cargar el AAB firmado con la clave de carga.

## Play Console pendiente

- Crear la ficha con nombre, descripción breve/completa, icono 512×512, gráfico 1024×500 y capturas reales.
- Proporcionar URL pública de política de privacidad. Debe explicar el acceso local a archivos de audio y que no se recopilan ni comparten datos.
- Completar Seguridad de los datos: sin recopilación ni transferencia fuera del dispositivo, si no se agregan analíticas, publicidad o red.
- Explicar que la selección de carpeta es la función central del reproductor y
  que la app procesa los archivos localmente.
- Completar clasificación de contenido, audiencia objetivo, anuncios (No), acceso a la app (sin restricciones) y categoría Música y audio.
- Probar el AAB en Internal testing y en el informe previo al lanzamiento, especialmente Android 8/10/12/13/14/15/16 y Xiaomi/Redmi.
- Página recomendada de soporte y promoción: `https://www.christianfontalvo.com/mp3-player`.

## Reproducción en segundo plano

La app incorpora un servicio multimedia en primer plano de tipo
`mediaPlayback`, notificación y controles en pantalla bloqueada. Declara
`WAKE_LOCK`, `FOREGROUND_SERVICE` y `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, sin
solicitar acceso general al almacenamiento. Antes de cada publicación deben
probarse pausa, reanudación, anterior, siguiente, bloqueo de pantalla, audífonos,
interrupciones de audio y ahorro de batería en Samsung y Xiaomi.

## APK beta

El APK beta descargable puede firmarse con la clave local de desarrollo para
pruebas privadas. No debe presentarse como artefacto de Google Play ni usarse
como sustituto de la clave de carga definitiva. El AAB de Play se generará
después con `android/key.properties` y una clave privada respaldada.
