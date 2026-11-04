# Super Teclado

Teclado para iPhone y iPad inspirado en Gboard, con portapapeles completo.

## Versión 2.6

### Teclado

- **Sin retraso al escribir**, como Gboard y el teclado de Apple: las teclas se dibujan y se tocan con UIKit en una sola vista que resalta la tecla al instante, escribe al levantar el dedo y, si tocas otra tecla antes de soltar la anterior, escribe la anterior en ese momento para no perder ni desordenar letras. Las sugerencias se calculan en segundo plano y la vibración y el sonido no bloquean la pulsación.
- QWERTY español (con **ñ**) con **temas** al estilo Gboard: automático, claro, oscuro, negro, **cristal translúcido** (con su **transparencia ajustable** desde la paleta del teclado o la app), océano, bosque, atardecer, rosa, lavanda, **degradados** (aurora, amanecer, menta, noche), **personalizado con tus colores** (fondo liso o degradado, teclas, letras y acento) o **una foto propia** de fondo; con o sin bordes de tecla. El tema se cambia desde la **paleta de la barra del teclado** o desde la app.
- **Escritura deslizando** (*glide typing*): desliza de letra en letra sin levantar el dedo, con estela, **la palabra en la barra mientras deslizas**, alternativas al terminar y borrado de la palabra entera con un toque.
- **Idiomas**: español, catalán, portugués, inglés, francés, italiano y alemán, con un segundo idioma opcional a la vez, y **distribuciones** QWERTY española (ñ), QWERTY con ç, QWERTY, AZERTY y QWERTZ. Diccionarios de 30 000-40 000 palabras ordenadas por frecuencia para completar, corregir y reconocer trazos.
- Barra de sugerencias con tres propuestas, **autocorrección** de erratas y tildes («qeu» → «que», «tambien» → «también») al pulsar espacio o puntuación, y deshacer la corrección pulsando borrar justo después.
- **Predicción de la siguiente palabra desde el primer día**, con una base de pares de palabras de frases reales (Tatoeba) en cada idioma que se combina con lo que aprende de ti, y **sugerencias de emojis** («jaja» → 😂).
- Al escribir «hoy» o «ahora», la barra ofrece la fecha o la hora; los atajos admiten `{fecha}`, `{fecha_larga}`, `{hora}` y `{dia}`.
- Al elegir una sugerencia y escribir un signo, el espacio se recoloca («hola, » en vez de «hola ,»).
- Aprende las palabras que escribes, usa las sustituciones de texto y los contactos de iOS, y permite atajos propios desde el **diccionario personal** de la app.
- Mayúsculas automáticas (también tras «¿» y «¡»), doble toque en mayúsculas para bloquearlas y punto con doble espacio.
- Ventana emergente al pulsar y **pulsación larga** para acentos (á, é, ü…) y para los símbolos que se ven en la esquina de cada tecla.
- Fila de números opcional, páginas `?123` y `=\<`, teclado numérico para campos de números o teléfono y teclas `@`/`.com` en campos de correo y web.
- Desliza sobre la **barra espaciadora** para mover el cursor; mantén **borrar** para repetir o desliza a la izquierda para borrar palabras.
- Panel de **emojis** con categorías, recientes, **búsqueda en español** («pizza», «corazón», «risa»…) y **tonos de piel** manteniendo pulsado.
- **Modo incógnito** (icono del ojo): no aprende palabras ni guarda lo copiado; se activa solo en campos de contraseñas, códigos y tarjetas.
- Panel de **edición de texto**: cursor por letras, palabras e inicio o fin de línea, y copiar, cortar y pegar.
- **Modo una mano** a izquierda o derecha, altura del teclado y tamaño de las letras ajustables, retraso de la pulsación larga y **sonido al pulsar** a elegir (moderno, clásico, cristal o teléfono).
- **Fila de favoritos** opcional encima de las teclas con tus emojis y símbolos.
- **Vibración ajustable**: tipo (suave, ligera, media, seca o fuerte) e intensidad, con botón para probarla. También vibran las sugerencias y los botones de la barra al tocarlos.
- La tecla de intro cambia de icono según el campo (buscar, enviar, siguiente…).
- En **iPad**, distribución ancha con borrar e intro a la derecha, «,» «.» y dos teclas de mayúsculas.

### Portapapeles

- Captura automática de **texto, enlaces e imágenes** mientras el teclado está visible, también cuando se copian **varios elementos a la vez** (requiere *Acceso total*).
- Historial con **Fijados** y **Recientes agrupados por fecha** (hoy, ayer, esta semana…), filtros (texto, enlaces, imágenes, carpetas) e interruptor para desactivarlo.
- **Buscador** del historial escribiendo con el propio teclado.
- Toca para pegar; mantén pulsado para fijar, copiar, **ver el texto completo**, **pegar como** (MAYÚSCULAS, minúsculas, Tipo Título, en una línea, sin espacios de más), **mover a una carpeta** o eliminar.
- Selección múltiple para **pegar o copiar varios juntos**, fijarlos o borrarlos, y **Deshacer** tras borrar.
- **Privacidad**: lo que parece una tarjeta, un IBAN, una contraseña o un código se guarda oculto y se borra a los 2 minutos (o no se guarda, según el ajuste); lo que los gestores de contraseñas marcan como oculto nunca se guarda.
- Enlaces con su dominio y colores `#RRGGBB` con muestra.
- Recientes de hasta 500 elementos y opción **sin caducidad**.
- **Con el teclado cerrado**: «Compartir › Super Teclado» en cualquier app, y acciones de **Atajos y Siri** («Guardar el portapapeles en Super Teclado», «Copiar lo último de Super Teclado») que se pueden lanzar con el toque posterior del iPhone. La app explica cómo en *Ajustes › Guardar con el teclado cerrado*.
- Sugerencia de pegado rápido en la barra superior justo después de copiar algo.
- Las imágenes se copian al portapapeles del sistema para pegarlas en la app, porque iOS no deja que un teclado inserte imágenes.
- Volver a copiar algo lo sube al principio en lugar de duplicarlo. Los cambios hechos en el teclado se sincronizan con la app sin que los elementos borrados reaparezcan.

### App

- Historial con búsqueda (incluido el texto reconocido en imágenes), carpetas, etiquetas y colores.
- **Widget** de pantalla de inicio con tus fijados (toca para copiar) y botón del **Centro de control** para copiar lo último.
- **Copia de seguridad**: exporta e importa historial, imágenes, carpetas, diccionario personal y ajustes en un archivo, para no perder nada al reinstalar con otro certificado.
- **Diagnóstico del teclado**: memoria disponible, carga del diccionario y cierres inesperados, con un informe para copiar.
- **Guía de bienvenida** paso a paso para activar el teclado, que detecta cuándo ya funciona.
- La app muestra si el teclado está **activado con acceso total**.
- **Ajustes › Ajustes del teclado** reúne las preferencias del teclado, una guía para activarlo, un campo para probarlo y el **diccionario personal** (palabras aprendidas y atajos).

### Limitaciones de iOS

iOS no permite a los teclados de terceros usar el micrófono, insertar imágenes directamente, seleccionar texto ni leer el portapapeles en segundo plano, así que el dictado por voz, los GIF, «Seleccionar todo» y la captura de lo copiado con el teclado cerrado (más allá de Compartir y Atajos) no están disponibles.

## Compilación

GitHub Actions genera `Super-Teclado-unsigned.ipa` en un runner macOS. La IPA no contiene una firma de Apple y debe firmarse después con KravaSign, Feather o una herramienta equivalente usando el certificado y el perfil asociados al UDID del dispositivo.

El código de la aplicación está en `SuperTecladoApp/`, el teclado en `SuperTecladoKeyboard/`, la extensión de Compartir en `SuperTecladoShare/`, el widget en `SuperTecladoWidget/`, las acciones de Atajos compartidas en `SharedIntents/` y el código común (almacenamiento compartido, preferencias y reglas de texto) en `Shared/`. `project.yml` genera el proyecto Xcode reproducible mediante XcodeGen.

La automatización compila y **ejecuta las pruebas unitarias** en un simulador de iPhone y solo genera la IPA si pasan. En Windows puede ejecutarse `powershell -File scripts/validate-project.ps1` para comprobar estructura, metadatos y reglas esenciales antes de enviar los cambios a GitHub.

Los diccionarios proceden de FrequencyWords (CC BY-SA 4.0), los pares de palabras para predecir de Tatoeba (CC BY 2.0 FR) y los nombres de emojis de Unicode CLDR (licencia Unicode); consulta `THIRD_PARTY_NOTICES.md`.
