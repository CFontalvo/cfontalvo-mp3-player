# Preparación para Google Play

## Estado técnico

- ID de aplicación definitivo: `com.christianfontalvo.mp3player`, basado en `christianfontalvo.com`.
- Versión inicial: `1.0.0+1`. Incrementar el número después de `+` en cada carga.
- Android: mínimo API 21; objetivo y compilación API 36.
- Formato de publicación: Android App Bundle (`.aab`).
- Datos: procesamiento local; la app no transmite ni comparte datos.
- Permiso: música y audio, necesario para la función principal.
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
- Declarar el permiso Música y audio como función central de un reproductor.
- Completar clasificación de contenido, audiencia objetivo, anuncios (No), acceso a la app (sin restricciones) y categoría Música y audio.
- Probar el AAB en Internal testing y en el informe previo al lanzamiento, especialmente Android 8/10/12/13/14/15/16 y Xiaomi/Redmi.
- Página recomendada de soporte y promoción: `https://www.christianfontalvo.com/mp3-player`.

## Alcance actual de reproducción

La reproducción está diseñada para uso con la aplicación visible. No se declara
un servicio en primer plano, permiso de notificaciones ni controles multimedia
en pantalla bloqueada. Si se requiere reproducción continua en segundo plano,
debe incorporarse un servicio multimedia con notificación antes de publicar esa
función; no conviene declarar esos permisos sin implementarla.
