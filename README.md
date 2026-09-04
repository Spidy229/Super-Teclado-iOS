# Super Teclado

Teclado para iPhone y iPad con historial temporal y guardado del portapapeles.

La versión 1.0 (compilación 2) añade un teclado QWERTY español oscuro, historial de múltiples copias temporales, actualización del panel sin reiniciar su estado y almacenamiento de respaldo dentro de la extensión.

## Comportamiento 1.0

- El contenido nuevo entra en una bandeja temporal y solo pasa al historial permanente cuando la persona pulsa **Guardar**.
- Con **Acceso total**, el teclado detecta contenido copiado mientras permanece visible y lo muestra inmediatamente en **Temporales**.
- El teclado funciona sin abrir la app principal, sin audio y sin aparecer como reproductor.
- Los temporales caducan y tienen un límite independiente configurable.
- Los temporales pueden insertarse con un toque o fijarse desde el propio teclado para guardarlos permanentemente.
- Los códigos de un solo uso siguen excluidos de forma predeterminada.

## Compilación

GitHub Actions genera `Super-Teclado-unsigned.ipa` en un runner macOS. La IPA no contiene una firma de Apple y debe firmarse después con KravaSign, Feather o una herramienta equivalente usando el certificado y el perfil asociados al UDID del dispositivo.

El código de la aplicación está en `SuperTecladoApp/` y la extensión en `SuperTecladoKeyboard/`. `project.yml` genera el proyecto Xcode reproducible mediante XcodeGen.

La automatización ejecuta primero las pruebas unitarias en el simulador y solo genera la IPA si pasan. En Windows puede ejecutarse `powershell -File scripts/validate-project.ps1` para comprobar estructura, metadatos y reglas esenciales antes de enviar los cambios a GitHub.

