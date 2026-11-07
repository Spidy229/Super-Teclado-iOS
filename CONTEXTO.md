# Super Teclado: contexto para agentes

Resumen de todo lo hecho hasta la **versión 2.8.5**, para que otro agente (Claude Code, Codex…) pueda seguir el trabajo sin repetir errores. El `README.md` describe las funciones para el usuario; este documento explica **cómo está hecho, por qué y qué falta**.

---

## 1. Objetivo y usuario

- **Objetivo:** un teclado para iPhone/iPad lo más parecido posible a **Gboard de Android**, con un **portapapeles completo** con historial, hasta donde permite iOS.
- **Idioma:** el usuario escribe en **español** y quiere las respuestas en español. Los textos de la interfaz y los comentarios del código están en español; los mensajes de commit, en inglés.
- **Cómo instala:** descarga la **IPA sin firmar** del release de GitHub y la firma en el móvil con **KravaSigner** (a veces Feather).
  - **KravaSigner quita el App Group** (certificado compartido): la app y el teclado **no comparten datos** en su instalación. Ver §6.
  - Tiene activado el **acceso total** del teclado.
- **Prioridades que ha pedido:**
  - que no haya retraso al escribir;
  - vibración ajustable que funcione;
  - temas, incluida la transparencia del cristal;
  - que la autocorrección se pueda desactivar de verdad;
  - icono propio (un pato amarillo).

## 2. Repositorio, ramas y publicación

- Repo: `Spidy229/Super-Teclado-iOS`. Rama de trabajo: `claude/wizardly-knuth-yy92cs`.
- **PR #1** (https://github.com/Spidy229/Super-Teclado-iOS/pull/1): abierta y **sin fusionar**; no fusionarla sin que lo pida el usuario.
- **CI** (`.github/workflows/build-ipa.yml`, macOS 15, Xcode 16.4) se lanza con cada push a `main`, `codex/**` y `claude/**`. Pasos:
  1. XcodeGen genera el proyecto.
  2. Compila y ejecuta las pruebas en el primer simulador de iPhone disponible.
  3. `scripts/build-unsigned-ipa.sh` genera la IPA sin firmar.
  4. **Publica un release** `v<MARKETING_VERSION>-build<run_number>` con `Super-Teclado-unsigned.ipa`.
  - Enlace de descarga: `https://github.com/Spidy229/Super-Teclado-iOS/releases/download/<tag>/Super-Teclado-unsigned.ipa`.
  - Para commits solo de documentación, usar `[skip ci]` y así no crear un release repetido.
- **Subir versión** en cada cambio que se entregue, en dos sitios que deben coincidir:
  - `project.yml`: `MARKETING_VERSION` y `CURRENT_PROJECT_VERSION`, **4 veces cada uno** (app, teclado, share y widget).
  - `SuperTecladoApp/Package.swift`: `displayVersion` y `bundleVersion`.
  - Estado actual: 2.8.5 / 26 en `project.yml`, 2.8.5 / 31 en `Package.swift`.
- `scripts/build-unsigned-ipa.sh`:
  - firma ad hoc (`codesign -s -`) cada appex con sus entitlements y después la app;
  - **falla si falta `Assets.car` o `CFBundleIcons`** (comprobación añadida en 2.6.6).
- `scripts/validate-project.ps1`: comprobación estática antigua (PowerShell) que **CI no ejecuta**. Además está desfasada: busca `SharedClipboardStore.captureTemporaryText` en `KeyboardViewController.swift`, que ya no existe.
- No hay Mac en el entorno de los agentes en la nube: **solo CI compila con UIKit**. En Linux se puede usar un toolchain de Swift 6 para:
  - `swiftc -parse` (sintaxis);
  - compilar y ejecutar la lógica pura de `Shared/` (diccionario, glide, sugerencias en segundo plano, traspaso de ajustes).

## 3. Estructura y destinos (XcodeGen, Swift 6, iOS 18)

| Destino | Carpeta(s) | Bundle ID | Qué es |
|---|---|---|---|
| App `SuperTeclado` | `SuperTecladoApp`, `Shared`, `SharedIntents` | `com.spidy229.superteclado` | App SwiftUI + SwiftData: historial del portapapeles, ajustes, temas, diccionario personal, copia de seguridad, diagnóstico, bienvenida |
| `SuperTecladoKeyboard` | `SuperTecladoKeyboard`, `Shared` | `…superteclado.keyboard` | La extensión de teclado (`UIInputViewController`) |
| `SuperTecladoShare` | `SuperTecladoShare`, `Shared` | `…superteclado.share` | Extensión «Compartir» para guardar en el portapapeles |
| `SuperTecladoWidget` | `SuperTecladoWidget`, `SharedIntents`, `Shared` | `…superteclado.widget` | Widget + control del Centro de control (iOS 18) |
| `SuperTecladoTests` | `SuperTecladoTests` | `…superteclado.tests` | XCTest sobre la app (`@testable import SuperTeclado`, incluye `Shared`) |

- App Group: `group.com.spidy229.superteclado`. `SharedClipboardStore.sharedDefaults` es `UserDefaults(suiteName:)` de ese grupo.
  - Sin el grupo en la firma, esos `UserDefaults` siguen funcionando, pero **cada proceso guarda los suyos**.
  - `isAppGroupAvailable` devuelve `containerURL != nil`.
- Recursos del teclado (`SuperTecladoKeyboard/Resources`):
  - `words-<idioma>.txt`: 40 000 palabras en es y 30 000 en ca/pt/en/fr/it/de, de FrequencyWords, CC BY-SA 4.0;
  - `bigrams-<idioma>.txt`: pares de palabras de Tatoeba, CC BY 2.0 FR, sin nombres propios;
  - `es-emojis.txt`: nombres de los emojis según CLDR.
  - Licencias en `THIRD_PARTY_NOTICES.md`.
- Icono: `SuperTecladoApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (pato, 1024×1024 sobre blanco).

## 4. Arquitectura del teclado

### Controlador: `KeyboardViewController.swift`
- Capas de la vista del teclado, de abajo arriba (2.8.0):
  1. `KeyboardBackgroundView` (UIKit): color, degradado o foto.
  2. `KeyboardRootView` (SwiftUI) en un `UIHostingController`: barra, favoritos y paneles. En los paneles de escritura deja un hueco transparente para las teclas.
  3. `KeyGridUIView` (UIKit), colocada por `gridFrame(for:)` en ese hueco (márgenes seguros y modo una mano incluidos). Así un toque en una tecla no pasa nunca por SwiftUI.
  4. La capa de las ventanas emergentes.
- `syncGrid()` actualiza el fondo, el marco, la visibilidad y la configuración de las teclas. Se llama tras `engine.objectWillChange` (agrupado en un `Task`) y en `viewDidLayoutSubviews`. El aviso flotante de SwiftUI se dibuja sobre la barra superior, porque las teclas lo taparían.
- La altura sale de `KeyboardMetrics` (franja superior + fila de favoritos + teclas).
- `viewDidLoad`:
  - marca la sesión para detectar cierres inesperados;
  - activa el **modo seguro** si hubo 2 cierres seguidos (sin diccionarios, contactos ni foto);
  - carga ajustes y el portapapeles;
  - pide el léxico de iOS (`requestSupplementaryLexicon`).
- `viewDidAppear`:
  - vuelve a leer `hasFullAccess`, porque iOS puede darlo tarde;
  - `removeSystemTouchDelays()` pone `delaysTouchesBegan = false` en los reconocedores del sistema. Si no, se retrasaban los toques en los bordes.
- **Portapapeles:**
  - desde 2.8.3, todo (`changeCount`, leer lo copiado, miniaturas y guardado) va en `Task.detached` (`readPasteboard`), y el historial se recarga con `reloadClipsInBackground`. Leer una imagen o algo del portapapeles universal congelaba el teclado medio segundo o más;
  - `checkPasteboard()` solo lee si cambia `changeCount`;
  - se consulta cada 1,5 s, **excepto si se ha tocado una tecla en los últimos 1,5 s**;
  - también al aparecer el teclado y al abrir el panel.
- **Traspaso de ajustes** (2.6.8): si el portapapeles trae el tipo `com.spidy229.superteclado.settings`, se aplican los ajustes, se vacía el portapapeles y se muestra un aviso (ver §6).

### Estado y lógica: `KeyboardEngine.swift` (`@MainActor ObservableObject`)
- Guarda panel, página, mayúsculas, preferencias, métricas, portapapeles, emojis, avisos y glide.
- **Lo que cambia con cada pulsación va aparte**, en `SuggestionBarState` (`engine.bar`): `suggestions`, `showsToolbar` y `quickPaste`. Solo lo observa `SuggestionStripView`, así que escribir no redibuja el teclado entero.
  - `engine.suggestions`, `showsToolbar` y `quickPaste` son propiedades calculadas que reenvían a `bar`.
- `insertCharacter`, `insertSpace`, `commitWord` (autocorrección con deshacer al borrar), `deleteBackward`, `selectSuggestion`, glide (`beginGlide`, `extendGlide`, `endGlide`, `cancelGlide`), cursor y emojis.
- `keyFeedback(kind)` (desde 2.8.4 sin acumular retraso: vibración como mucho cada 40 ms y clic saltado si el anterior aún suena, porque antes los clics hacían cola y sonaban segundos tarde; el coste de cada vibración se mide en el diagnóstico):
  - **vibración** con el `hasFullAccess` guardado, `impactOccurred(intensity:)` y luego `prepare()` para la siguiente tecla;
  - **sonido** con `AudioServicesPlaySystemSound` en una cola propia, para no bloquear el hilo principal;
  - apunta `lastKeyTouch`.
- `scheduleSuggestions()`: espera 12 ms, luego `refreshSuggestions() async`.
- Espacio tras elegir una sugerencia (2.8.1, `addSpaceAfterSuggestion`, preferencia `spaceAfterSuggestion`, activada por defecto). Usa `KeyboardTextLogic.suggestionSpace(before:)` con el texto detrás del cursor:
  - si hay un espacio, el cursor salta detrás de él en vez de duplicarlo;
  - delante de un signo, unas comillas o un salto de línea no se pone espacio.
  - Pulsar espacio justo después de una sugerencia no añade otro (`autoSpaceInserted`); un segundo espacio seguido pone el punto.
- `autocorrectAllowed` = preferencia activada + sugerencias permitidas + el campo no la prohíbe. Si es `false`, las propuestas `.correction` se muestran como `.completion` (sin azul) y el espacio no cambia nada (2.6.8).

### Teclas: `Views/KeyGridUIView.swift` (UIKit, desde 2.6.5)
Este archivo es la solución al **retraso al escribir**. Antes cada tecla era una vista SwiftUI con `DragGesture` y todo se redibujaba en cada pulsación.
- `apply(_:palette:)` recibe un `KeyGridConfiguration` (`Equatable`) y la paleta, y no hace nada si no cambian. Ya no hay `UIViewRepresentable`: la cuadrícula es una subvista directa de la vista del teclado.
  - Las teclas se reutilizan por `KeySpec.id`.
  - Si las filas no cambian, solo se actualizan textos y colores.
- **Una sola vista recibe todos los dedos**, a través de `KeyTouchRecognizer` (2.7.1).
  - Es un `UIGestureRecognizer` que nunca reconoce nada (`canBePrevented` y `canPrevent` devuelven `false`, `cancelsTouchesInView = false`).
  - iOS entrega los toques a los reconocedores al instante; a las vistas puede retrasarlos (bordes de la pantalla, otros gestos).
  - Desde 2.8.4 la vista también atiende los toques: cada dedo llega por los dos caminos, se atiende el primer aviso y el otro se descarta (`isDuplicateBegin`, `downTimestamp`, `lastMoveTimestamp`).
    - En 2.8.5 se quitó la lista de dedos terminados de 2.8.4: iOS puede reutilizar el mismo objeto `UITouch` para un toque nuevo y ese toque se descartaba (sin luz ni vibración). Un aviso es duplicado solo si el dedo ya está en `states` con el mismo `touch.timestamp` de inicio, si ya no está en `.began` o si ya terminó. Si un camino falla, no se pierde ningún toque.
  - `fingersReset()` cierra los dedos que quedaran al terminar la secuencia. La tecla tocada es la más cercana de su fila, así que los huecos cuentan para la tecla de al lado.
  - Al tocar: resalta la tecla y la ventana emergente, vibra/suena y programa la pulsación larga.
  - Al levantar: escribe.
  - **Rollover:** si toca otro dedo antes de levantar el anterior, la letra o el espacio anterior se escriben ya (estado `.committed`).
  - Mayúsculas y `?123` actúan al tocar. Intro, emoji y ocultar actúan al levantar.
  - Borrar: borra al tocar, repite (420 ms y después cada 65 ms; tras 20, por palabras) y deslizar a la izquierda borra palabras.
  - Espacio: deslizar mueve el cursor (fase `.cursor`).
  - Globo: `handleInputModeList(from:with:)`.
  - Glide:
    - empieza si una letra se mueve más de `max(18, ancho de tecla × 0,6)` y solo hay un dedo activo;
    - usa los toques intermedios (`coalescedTouches`);
    - el trazo es un `CAShapeLayer` con las animaciones implícitas desactivadas.
  - Sin glide, deslizar cambia a la letra que queda bajo el dedo.
- Las ventanas emergentes (`KeyPopupUIView`) van en una capa propia (`popupContainer`) añadida una sola vez a `engine.controller.view`. Así nada las recorta y mostrarlas no obliga a recolocar el teclado en cada toque. Se reutilizan y se quitan en `tearDown()`.
- `KeyCapUIView` reproduce el aspecto de Gboard: tapa con esquinas de 7 pt (continuas), sombra desplazada 1 pt, etiqueta, símbolo de la esquina e icono SF.
- **Mantener `KeySpec` y `KeyboardPalette` como `Equatable`**; la configuración depende de ello.
- Las filas (`keyRows()`: letras, `?123`, `=\<`, teclado numérico y distribución ancha de iPad) y `KeyGridConfiguration(engine:)` están en `KeyRows.swift`.
  - La cuadrícula se pone al día con el motor después de cada toque (`syncWithEngine()`), sin esperar a SwiftUI; así el siguiente dedo ya ve la página y las mayúsculas correctas.
  - `KeyGridGeometry` reparte las alturas (la fila de números ocupa 0,78 de una fila normal).
- **Reglas para no perder toques al teclear deprisa** (2.6.9):
  - el glide solo empieza si el dedo sale de su tecla y recorre más de `max(26, 0,8 × ancho)`, o `1,3 × ancho` si hubo otra letra hace menos de 0,3 s;
  - si toca un segundo dedo con un trazo todavía corto (< 2,5 teclas), el trazo se convierte en pulsación de la tecla inicial; si el trazo es largo, se termina en ese momento. Desde 2.8.5 un dedo nuevo nunca se ignora;
  - un trazo corto sin palabra reconocida también cuenta como pulsación;
  - el cursor de la barra espaciadora solo se mueve con un deslizamiento claro (> 28 pt, sobre todo horizontal y tras 80 ms); igual con borrar palabras (> 32 pt);
  - sin glide, deslizar solo cambia de letra si el dedo entra bien en otra tecla (20 % hacia dentro);
  - un toque cancelado por iOS se escribe si era corto (< 0,4 s y < 14 pt);
  - los dedos de los que iOS no avisó al levantarse se cierran (`dropTouchesThatEnded`), para que no bloqueen el teclado;
  - tocar otra tecla detiene la repetición de borrar;
  - un dedo quieto más de 0,6 s (apoyado) o con la pulsación larga abierta no escribe nada cuando toca otro dedo (2.7.1);
  - un deslizamiento vertical desde la barra espaciadora no escribe un espacio (2.7.1).
- **Precisión inteligente** (2.7.0, `smartKeyIndex`, preferencia `smartTouch`, activada por defecto):
  - si el toque cae a menos del 15 % del borde de otra letra, se puntúa cada candidata con `−2·(dx²+dy²)` (distancia normalizada al centro) más `0,2·log(peso+1)` (2.7.1; en 2.7.0 eran 25 % y 0,25);
  - el peso es `WordDictionary.prefixWeight(palabra + letra)`: índice ordenado de palabras como teclas con sumas acumuladas, unos 0,6 µs por consulta;
  - la palabra sale de `engine.wordForPrediction`: el contexto del documento completado con `typedWord`, porque el contexto puede ir una letra por detrás al teclear deprisa;
  - el rollover se escribe antes de elegir la tecla nueva, para que esa letra cuente;
  - no se usa en contraseñas, códigos, tarjetas, usuario, correo, web ni campos con `autocorrectionType = .no`.
- **Diagnóstico de toques**: `engine.touchDiagnostics`, visible en el panel ⚙︎ con «Poner a cero». Incluye:
  - contadores y los últimos 12 toques con los milisegundos entre toques;
  - desde 2.8.0, el retraso de entrega (`CACurrentMediaTime() − touch.timestamp`);
  - el tiempo de proceso de cada toque;
  - los bloqueos del hilo principal de más de 100 ms, medidos con un temporizador de 0,1 s (desde 2.8.2; un `CADisplayLink` podía bajar la frecuencia de la pantalla);
  - desde 2.8.2, «Copiar informe de velocidad» (`engine.diagnosticsReport()`), con modelo, iOS, memoria libre y ajustes. Es lo primero que hay que pedir al usuario si dice que va lento.
- Pulsación larga: el valor por defecto pasa de 330 a **400 ms**; el 330 guardado se convierte al cargar. Se elige en ⚙︎ (250 / 400 / 550 ms).
- `Views/KeyViews.swift` conserva las teclas SwiftUI (`FunctionKeyView`, `DeleteKeyView`, `RepeatingKeyView`) que usan los paneles de emojis y edición, y `GlideTrail` (solo `preview`).

### Sugerencias: `SuggestionEngine.swift`
- `SuggestionSnapshot` (`Sendable`) calcula las sugerencias **en segundo plano** (`Task.detached`) a partir de una copia de:
  - diccionario, distribución, palabras aprendidas, léxico de iOS, atajos y rechazadas.
- Funcionamiento:
  - **completar** con el diccionario;
  - **tildes** con `bestForm`;
  - **erratas** a distancia 1, con más peso para las teclas vecinas (`TypoCorrector`);
  - las tres casillas, como en Gboard.
- **UITextChecker** solo se usa en el hilo principal:
  - antes de cargar el diccionario;
  - al pulsar espacio con la autocorrección activada, para confirmar (`needsSpellCheck`) una errata probable en una palabra que no está en el diccionario. Si iOS la da por buena, no se corrige. Desde 2.8.0, nunca se usa para la barra mientras se escribe.
- Caché por palabra con `cacheGeneration`, que se invalida al aprender o rechazar palabras y al cambiar de diccionario o léxico. `autocorrection(for:)` es síncrona al pulsar espacio y casi siempre sale de la caché.
- Fecha y hora («hoy», «ahora») y emojis (`EmojiKeywords`) se añaden en `slots(for:word:includeEmoji:)`.
- `predictions(after:)` combina los pares de Tatoeba (`BigramModel`) con lo que aprende del usuario.
- Mide unos 1,7 ms por palabra con `-O` en Linux, fuera del hilo principal.

### Otras vistas del teclado
- `KeyboardRootView`: franja superior según el panel, fila de favoritos, panel, fondo (tema, degradado o foto) y aviso flotante.
- `SuggestionStripView`: sugerencias, pegado rápido y herramientas (emoji, portapapeles, edición, una mano, temas y ⚙︎ ajustes).
- `KeyFeedbackButtonStyle` (`KeyboardTheme.swift`) **vibra al tocar** (no al soltar) y atenúa el botón. Lo usan las sugerencias, el pegado rápido, `StripButton` y `PanelBackButton` (2.6.7).
- Paneles:
  - `ClipboardPanelView`: Recientes y Fijados, carpetas, búsqueda, selección múltiple, deshacer al borrar e imágenes;
  - `EmojiPanelView`: categorías, recientes, búsqueda y tonos de piel;
  - `TextEditingPanelView`;
  - `ThemePickerPanelView`: temas y **control de transparencia del cristal**;
  - `KeyboardSettingsPanelView` (⚙︎): vibración (tipo e intensidad), sonido, glide, autocorrección, fila de números, bordes, incógnito, y el estado del acceso total y del App Group.

## 5. App y datos compartidos

- `Shared/SharedClipboardStore.swift`:
  - guarda Fijados y la bandeja temporal (Recientes) en JSON dentro del contenedor del grupo, y las imágenes en una carpeta;
  - sin contenedor, recurre a `UserDefaults`;
  - registra borrados para no volver a importar lo eliminado, aplica retención y límites, y permite carpetas.
- `ClipboardCapture`: captura textos, enlaces e imágenes, también varios a la vez. No guarda lo que los gestores de contraseñas marcan como privado.
- `KeyboardHistorySync.commit`: sincroniza en ambos sentidos el historial de SwiftData de la app con el del teclado.
- `KeyboardPreferences`: todos los ajustes, con `load(from:)` y `save(to:)`.
  - Las claves están en `KeyboardPreferenceKey` y empiezan por `keyboard`.
  - Los colores se guardan con 8 bits por canal para que coincidan al volver a leerlos.
- App:
  - `KeyboardSettingsView` y `KeyboardThemesView` usan `@AppStorage` sobre el grupo;
  - `KeyboardStatusView` muestra el estado del teclado;
  - además: `DiagnosticsView`, `BackupView`/`BackupService` (JSON), `PersonalDictionaryView`, `OnboardingView`, Face ID (`AppLockController`) y OCR.
- Diagnóstico (`KeyboardDiagnostics`): cierres seguidos, modo seguro, memoria libre (`os_proc_available_memory`) y tiempos del diccionario.

## 6. El problema del App Group (importante para este usuario)

- KravaSigner firma con un certificado compartido: **elimina el App Group**. Consecuencias:
  - la app no ve lo que copia el teclado (en la app sale «Temporales 0 / Guardados 0»);
  - lo que se cambia **en la app no llega solo al teclado**;
  - la app no sabe si hay acceso total.
- El teclado funciona por su cuenta y sus ajustes se cambian desde ⚙︎.
- Solución añadida en 2.6.8 (`Shared/KeyboardSettingsTransfer.swift`):
  - La app muestra **«Enviar ajustes al teclado»** (`KeyboardSettingsTransferSection`) en Ajustes del teclado y en Temas.
  - El botón pone en el portapapeles los ajustes (`keyboard*` y los del portapapeles) como plist, con un tipo propio, solo en este dispositivo y con caducidad de 10 min.
  - El teclado los aplica al abrirse y vacía el portapapeles.
  - **No se envían las palabras ni los pares aprendidos** (`learnedWords`, `learnedBigrams`), ni `lastActive`.
- Solución completa: firmar con un certificado propio que conserve los App Groups (Feather con certificado propio, AltStore/SideStore/Sideloadly).

## 7. Historial de versiones

| Versión | Cambios |
|---|---|
| 1.0 – 2.0 | QWERTY español al estilo Gboard, portapapeles con historial, temporales y fijados |
| 2.1 – 2.2 | Escritura deslizando (decodificador con alineación dinámica, ~95 % de acierto top-1), diccionario de frecuencias, autocorrección, predicción, temas, búsqueda de emojis, tonos de piel, incógnito, inglés |
| 2.3 | Portapapeles «hasta el límite de iOS»: varios elementos, privados, imágenes, carpetas, búsqueda, selección múltiple, extensión Compartir, App Intents |
| 2.4 | Vibración ajustable, selector de temas en el teclado, tema personalizado |
| 2.5 | 7 idiomas y distribuciones (QWERTY, ç, AZERTY, QWERTZ), sonidos, temas en degradado y cristal, fila de favoritos, bienvenida |
| 2.6 | Base de predicción (Tatoeba), fecha y hora, diccionario compacto (índices `Int32`), diagnóstico, copia de seguridad, widget y control, distribución de iPad, vista previa del glide |
| 2.6.1 | **Cierre al abrir:** el cierre del léxico se ejecutaba en otra cola con aislamiento `@MainActor` → `dispatch_assert_queue_fail`. Arreglo: `@Sendable` + `nonisolated(unsafe)` + `Task { @MainActor }` |
| 2.6.2 | Lo mismo, por prevención, en las respuestas de `NSItemProvider` de la extensión Compartir |
| 2.6.3 | Botones de volver de los paneles (cápsula separada del borde + `removeSystemTouchDelays`), primeras mejoras del retraso, panel ⚙︎ en el teclado, aviso de App Group en la app |
| 2.6.4 | Icono del pato (no se veía: ver 2.6.6) |
| 2.6.5 | **Teclas en UIKit** (`KeyGridUIView`), barra con estado propio, sugerencias en segundo plano, vibración y sonido sin bloquear, portapapeles sin consultar mientras se escribe |
| 2.6.6 | **Icono:** `project.yml` usaba una clave `resources:` que **no existe en XcodeGen** y además excluía `Assets.xcassets` de `sources`, así que nunca se compilaba. Ahora va en `sources` y el script lo comprueba |
| 2.6.7 | Vibración en sugerencias y botones de la barra; control de **transparencia del cristal** (`glassTransparency`, 0–1, por defecto 1) en el teclado y en la app |
| 2.6.8 | Sin azul ni corrección en el espacio con la autocorrección desactivada; «Enviar ajustes al teclado» |
| 2.6.9 | Toques más fiables al teclear deprisa (ver reglas en §4) y cuadrícula que se actualiza sin esperar a SwiftUI |
| 2.7.0 | Precisión inteligente al tocar entre dos letras, diagnóstico de toques en ⚙︎, pulsación larga de 400 ms ajustable en ⚙︎ |
| 2.7.1 | Toques por reconocedor de gestos, capa propia para las ventanas emergentes, sin solape con la barra, dedos apoyados ignorados, precisión más prudente; portapapeles y clips se leen 0,7 s después de abrir, y el diccionario personal se guarda fuera del hilo principal |
| 2.8.0 | Teclas y fondo fuera de SwiftUI (subvistas UIKit de la vista del teclado), medidas de retraso y bloqueos en el diagnóstico, sin UITextChecker al mostrar sugerencias, vibración preparada al aparecer |
| 2.8.1 | Espacio tras una sugerencia sin duplicar el que ya hay ni ponerlo delante de signos; se puede desactivar |
| 2.8.2 | 120 Hz en el teclado (`CADisableMinimumFrameDurationOnPhone`), la tecla y su ventana se envían a la pantalla (`CATransaction.flush()`) antes de vibrar y sonar, tecla resaltada también con ventana emergente, informe de velocidad copiable |
| 2.8.3 | Sin bloqueos del hilo principal: portapapeles e historial en segundo plano, UITextChecker perezoso y nunca para la barra (antes arrancaba en el primer toque y congelaba), lo aprendido se lee en segundo plano; los bloqueos aparecen en los últimos toques |
| 2.8.4 | Clics y vibración sin cola (se saltan en vez de acumular segundos de retraso al teclear deprisa), toques por dos caminos con deduplicación, coste de la vibración en el informe |
| 2.8.5 | Un toque nuevo ya no se descarta por error como duplicado (iOS reutiliza objetos de dedo) ni se ignora mientras otro dedo desliza; el informe dice por qué camino llegó cada toque |

## 8. Errores ya resueltos (no repetirlos)

- **Swift 6 y las respuestas del sistema:** todo cierre que iOS llame desde otra cola debe ser **`@Sendable` explícito**; si no, hereda `@MainActor` y se cierra al entrar. Esto incluye `requestSupplementaryLexicon`, `NSItemProvider.loadItem` y las colas de `DispatchQueue`.
  - Si el valor no es `Sendable`, se pasa con `nonisolated(unsafe) let` y se usa dentro de `Task { @MainActor in … }`.
- El cierre de la etiqueta de `PhotosPicker` es `Sendable`: calcular el texto **antes** del `Form`.
- **XcodeGen:** los recursos (`.xcassets`, `.txt`) van en `sources`; no existe una clave `resources:` a nivel de destino.
- El script de validación cuenta llaves en bruto: no escribir `"{"` en cadenas (usar `"\u{7B}"`).
- Memoria del teclado (límite estricto de iOS):
  - diccionarios en segundo plano con índices `Int32`;
  - foto de fondo reducida a 1 400 px;
  - en modo seguro no se cargan.
- No reconstruir las teclas en SwiftUI ni publicar en `KeyboardEngine` datos que cambian con cada pulsación (usar `engine.bar` o estado local).
- No llamar a `controller.hasFullAccess` en cada pulsación (es lento): usar `engine.hasFullAccess`, que se actualiza en `viewDidLoad`, `viewWillAppear` y `viewDidAppear`.
- En la primera subida el usuario envió un registro de cierre equivocado (AccessoryCrash de unos auriculares): pedir siempre el `.ips` de `SuperTecladoKeyboard-…`.

## 9. Pendiente y sin verificar

- **La cuadrícula UIKit (2.6.5+) no se ha probado en un dispositivo real**; el usuario aún no ha confirmado si ha desaparecido el retraso. Puntos a vigilar:
  - posición de las ventanas emergentes en la fila superior y en modo una mano;
  - tecla del globo (`handleInputModeList`);
  - VoiceOver;
  - toques cancelados por gestos del sistema (ahora no escriben nada).
- No está verificado en un iPhone que «Enviar ajustes al teclado» funcione con KravaSigner (debería, con acceso total).
- El usuario aún no ha dicho qué muestra el panel ⚙︎ (estado del acceso total y del App Group).
- `scripts/validate-project.ps1` está desfasado (§2).
- El usuario notaba que se perdían pulsaciones al teclear deprisa. Tras la 2.6.9 seguía notando fallos, así que la 2.7.0 añade la precisión inteligente y el diagnóstico de toques. Hay que pedirle una captura del diagnóstico (⚙︎) justo después de un fallo: si «Cancelados y perdidos» y «Sin aviso de fin» siguen en 0, los toques perdidos no llegan al teclado (es cosa de iOS); si llegan, se ve qué les pasa.
- Ideas posibles:
  - pulsación larga en `?123` para escribir números sin cambiar de página;
  - más ajustes de la app dentro del panel ⚙︎ (idiomas, altura), para quien no tiene App Group.

## 10. Cómo trabajar en este repo

1. Trabajar en la rama indicada; no fusionar la PR.
2. Cambios de interfaz o lógica:
   1. revisar la sintaxis (`swiftc -parse`) y el equilibrio de llaves;
   2. subir la versión (§2);
   3. hacer commit y push;
   4. esperar a CI (~10 min);
   5. dar al usuario el enlace directo a la IPA del nuevo release.
3. Si se puede, probar la lógica de `Shared/` fuera de iOS; añadir pruebas en `SuperTecladoTests` (por ejemplo, `ThemeAndHapticsTests` cubre preferencias, cristal y traspaso de ajustes).
4. Responder al usuario en español, claro y sin tecnicismos.
