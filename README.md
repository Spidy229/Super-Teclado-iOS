# Super Teclado

Teclado para iPhone y iPad inspirado en Gboard, con portapapeles completo.

## Versión 2.0

### Teclado

- QWERTY español (con **ñ**) en tema claro, oscuro o automático, con o sin bordes de tecla.
- Barra de sugerencias con tres propuestas, **autocorrección** al pulsar espacio o puntuación y deshacer la corrección pulsando borrar justo después.
- Aprende las palabras que escribes y usa las sustituciones de texto y los contactos de iOS.
- Mayúsculas automáticas (también tras «¿» y «¡»), doble toque en mayúsculas para bloquearlas y punto con doble espacio.
- Ventana emergente al pulsar y **pulsación larga** para acentos (á, é, ü…) y para los símbolos que se ven en la esquina de cada tecla.
- Fila de números opcional, páginas `?123` y `=\<`, teclado numérico para campos de números o teléfono y teclas `@`/`.com` en campos de correo y web.
- Desliza sobre la **barra espaciadora** para mover el cursor; mantén **borrar** para repetir o desliza a la izquierda para borrar palabras.
- Panel de **emojis** con categorías y recientes.
- Panel de **edición de texto**: cursor por letras, palabras e inicio o fin de línea, y copiar, cortar y pegar.
- **Modo una mano** a izquierda o derecha, sonido y vibración al pulsar.
- La tecla de intro cambia de icono según el campo (buscar, enviar, siguiente…).

### Portapapeles

- Captura automática de **texto e imágenes** copiados mientras el teclado está visible (requiere *Acceso total*).
- Cuadrícula con secciones **Fijados** y **Recientes**, filtros (texto, enlaces, imágenes y carpetas) e interruptor para desactivarlo.
- Toca para pegar; mantén pulsado para fijar, desfijar, copiar o eliminar; el lápiz permite seleccionar varios elementos.
- Sugerencia de pegado rápido en la barra superior justo después de copiar algo.
- Las imágenes se copian al portapapeles del sistema para pegarlas en la app, porque iOS no deja que un teclado inserte imágenes.
- Volver a copiar algo lo sube al principio en lugar de duplicarlo. Los códigos de un solo uso se omiten por defecto.
- Los cambios hechos en el teclado (fijar, borrar) se sincronizan con la app sin que los elementos borrados reaparezcan.

### App

- Historial con búsqueda (incluido el texto reconocido en imágenes), carpetas, etiquetas y colores.
- **Ajustes › Ajustes del teclado** reúne las preferencias del teclado, una guía para activarlo y un campo para probarlo.

### Limitaciones de iOS

iOS no permite a los teclados de terceros usar el micrófono, insertar imágenes directamente ni seleccionar texto, así que el dictado por voz, los GIF y «Seleccionar todo» de Gboard no están disponibles. La escritura deslizando (*glide typing*) tampoco está incluida.

## Compilación

GitHub Actions genera `Super-Teclado-unsigned.ipa` en un runner macOS. La IPA no contiene una firma de Apple y debe firmarse después con KravaSign, Feather o una herramienta equivalente usando el certificado y el perfil asociados al UDID del dispositivo.

El código de la aplicación está en `SuperTecladoApp/`, la extensión en `SuperTecladoKeyboard/` y el código común (almacenamiento compartido, preferencias y reglas de texto) en `Shared/`. `project.yml` genera el proyecto Xcode reproducible mediante XcodeGen.

La automatización compila primero las pruebas unitarias para el simulador y solo genera la IPA si lo consigue. En Windows puede ejecutarse `powershell -File scripts/validate-project.ps1` para comprobar estructura, metadatos y reglas esenciales antes de enviar los cambios a GitHub.
