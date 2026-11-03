# Avisos de terceros

## Diccionario de frecuencias en español

`SuperTecladoKeyboard/Resources/words-es.txt` se ha generado a partir de la lista
`es_50k.txt` de [FrequencyWords](https://github.com/hermitdave/FrequencyWords), de Hermit Dave,
calculada sobre el corpus OpenSubtitles 2018.

- Contenido original: © Hermit Dave, con licencia
  [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
- Cambios: se conservan solo palabras formadas por letras del español, se eliminan las
  variantes sin tilde de palabras que casi siempre la llevan (por ejemplo «tambien») y se
  limita a las 40 000 palabras más frecuentes.
- El archivo derivado se distribuye con la misma licencia CC BY-SA 4.0.

Los demás diccionarios (`words-en.txt`, `words-ca.txt`, `words-pt.txt`, `words-fr.txt`,
`words-it.txt` y `words-de.txt`) proceden de las listas `en_50k.txt`, `ca_50k.txt`,
`pt_br_50k.txt`, `fr_50k.txt`, `it_50k.txt` y `de_50k.txt` del mismo proyecto, con las mismas
condiciones (CC BY-SA 4.0). Se conservan solo palabras formadas por letras, se eliminan las
variantes sin tilde de palabras que casi siempre la llevan y se limitan a las 30 000 más
frecuentes.

## Pares de palabras para predecir la siguiente palabra

Los archivos `SuperTecladoKeyboard/Resources/bigrams-*.txt` se han calculado a partir de las
frases de [Tatoeba](https://tatoeba.org) (exportaciones por idioma de `downloads.tatoeba.org`),
con licencia [Creative Commons Attribution 2.0 France](https://creativecommons.org/licenses/by/2.0/fr/).
Contienen, para cada palabra, las cuatro palabras que más a menudo la siguen y las palabras
con que suelen empezar las frases; se han quitado los nombres de los ejemplos (Tom, Mary…).

## Nombres de emojis en español

`SuperTecladoKeyboard/Resources/es-emojis.txt` se ha generado a partir de las anotaciones en
español de [Unicode CLDR](https://github.com/unicode-org/cldr-json)
(`cldr-annotations-full` y `cldr-annotations-derived-full`).

Copyright © 2015-2024 Unicode, Inc. Distribuido bajo la
[Unicode License V3](https://www.unicode.org/license.txt), que permite usar, copiar, modificar y
distribuir los datos siempre que se incluya este aviso de copyright.
