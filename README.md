# Super Teclado

Aplicación privada de historial del portapapeles para iPhone y iPad.

## Comportamiento 1.0

- El contenido nuevo entra en una bandeja temporal y solo pasa al historial permanente cuando la persona pulsa **Guardar**.
- La captura automática funciona con la app activa o al volver a ella; iOS no permite vigilar continuamente el portapapeles con la app suspendida.
- Con **Acceso total**, el teclado deposita el texto copiado en una bandeja compartida. La app lo importa como temporal en su siguiente apertura, sin usar audio ni aparecer como reproductor.
- Los temporales caducan y tienen un límite independiente configurable.
- El teclado publica únicamente elementos guardados permanentemente.
- Los códigos de un solo uso siguen excluidos de forma predeterminada.

## Compilación

GitHub Actions genera `Super-Teclado-unsigned.ipa` en un runner macOS. La IPA no contiene una firma de Apple y debe firmarse después con KravaSign, Feather o una herramienta equivalente usando el certificado y el perfil asociados al UDID del dispositivo.

El código de la aplicación está en `SuperPortapapelesV2/`. `project.yml` genera el proyecto Xcode reproducible mediante XcodeGen.

La automatización ejecuta primero las pruebas unitarias en el simulador y solo genera la IPA si pasan. En Windows puede ejecutarse `powershell -File scripts/validate-project.ps1` para comprobar estructura, metadatos y reglas esenciales antes de enviar los cambios a GitHub.

