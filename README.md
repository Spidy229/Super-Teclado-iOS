# Super Teclado

Teclado para iPhone y iPad con historial temporal y guardado del portapapeles.

La versión 1.1 (compilación 3) corrige la protección del historial, la sincronización del borrado y la caducidad de los temporales. Conserva el texto original y completa las teclas de puntuación y los caracteres españoles.

## Comportamiento 1.1

- El contenido nuevo entra en una bandeja temporal y solo pasa al historial permanente cuando la persona pulsa **Guardar**.
- Con **Acceso total**, el teclado detecta contenido copiado mientras permanece visible y lo muestra inmediatamente en **Temporales**.
- El teclado funciona sin abrir la app principal, sin audio y sin aparecer como reproductor.
- Los temporales caducan y tienen un límite independiente configurable.
- Los temporales pueden insertarse con un toque o fijarse desde el propio teclado para guardarlos permanentemente.
- Los códigos de un solo uso siguen excluidos de forma predeterminada.

## Compilación

GitHub Actions genera `Super-Teclado-unsigned.ipa` en un runner macOS. La IPA lleva una firma ad hoc para conservar sus entitlements, pero no una firma válida de Apple para instalarla. Debe firmarse después con KravaSign, Feather o una herramienta equivalente usando el certificado y los perfiles de la app y la extensión asociados al UDID del dispositivo. Ambos perfiles deben permitir el mismo App Group para compartir el historial.

El código de la aplicación está en `SuperTecladoApp/` y la extensión en `SuperTecladoKeyboard/`. `project.yml` genera el proyecto Xcode reproducible mediante XcodeGen.

La automatización selecciona un simulador iPhone disponible y ejecuta las pruebas unitarias con `xcodebuild test`; solo genera la IPA si pasan. El artefacto incluye la IPA, su SHA-256 y un JSON con la versión y el commit de origen. Los resultados de XCTest se publican en un artefacto separado, también cuando hay fallos. En Windows puede ejecutarse `powershell -File scripts/validate-project.ps1` para comprobar estructura, metadatos y reglas esenciales antes de enviar los cambios a GitHub.

