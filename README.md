# VibeTranslator

Utilidad de barra de menú para macOS que traduce el borrador de Discord del castellano al inglés con un atajo de teclado. El mensaje traducido se queda en el cuadro de texto para que lo revises y lo envíes tú.

- **Atajos globales configurables**: por defecto `⌃⌥T` traduce el borrador, `⌃⌥Z` restaura el original y `⌃⌥Y` traduce el texto seleccionado.
- **Traducir selección** en cualquier app: detecta el idioma (inglés → español, español → inglés) y muestra la traducción en una ventana flotante junto al cursor con «Copiar». Si la selección está en un campo editable, ofrece también «Reemplazar». La ventana no roba el foco y se cierra con Esc o con un clic fuera.
- **Traducción con estilo, no literal**: por defecto usa un LLM, Apple Intelligence en el propio Mac u Ollama, con un perfil de tono («relajado técnico» por defecto), un glosario de términos que no se traducen e instrucciones propias. Si el LLM no está disponible, falla o tarda, se usa automáticamente Apple Translation.
- **Conserva** menciones (`<@id>`, `@usuario`, `@everyone`, `#canal`), emojis (Unicode, `:shortcode:`, `<:custom:id>`), enlaces, código inline y bloques, formato (`**`, `||`, `~~`…), prefijos de línea (`>`, `-`, `#`, `-#`), saltos de línea e indentación.
- **Reemplazo seguro**: solo escribe si la app, la ventana o canal, el campo y el texto siguen siendo los mismos que al empezar. Si algo ha cambiado, aborta sin tocar nada.
- **Recuperación del original**: «Restaurar original» (solo si no has editado la traducción) o «Copiar original al portapapeles» (siempre).
- **Portapapeles preservado**: lo que tuvieras copiado vuelve a su sitio, y el texto temporal se marca como transitorio para que los gestores de portapapeles no lo guarden.

## Requisitos

- macOS 26 o posterior. Se usa `TranslationSession(installedSource:target:)`, que no existe antes. Probado en macOS 27.0.1.
- Xcode 26+ / Swift 6.2+ para compilar.
- Permiso de **Accesibilidad**, que hace falta para leer el campo activo y enviar ⌘A/⌘C/⌘V.
- Los idiomas **español** e **inglés** del traductor de Apple, que se descargan una vez desde la propia app. Hacen falta también como motor de respaldo.
- Opcional: **Apple Intelligence** activado (Ajustes del Sistema › Apple Intelligence y Siri), u **Ollama** con algún modelo.

## Compilar y ejecutar

```bash
scripts/build-app.sh
```

```bash
open build/VibeTranslator.app
```

El icono se genera con `swift scripts/make-icon.swift`, que escribe `Resources/AppIcon.icns`.

Tests del núcleo (markup y pipeline de traducción):

```bash
swift test
```

### Firma y permiso de Accesibilidad

macOS asocia el permiso de Accesibilidad a la firma del ejecutable. Con la firma ad-hoc (la opción por defecto), **cada recompilación cuenta como una app nueva** y hay que quitar y volver a añadir VibeTranslator en *Ajustes del Sistema › Privacidad y seguridad › Accesibilidad*.

Para evitarlo, crea una vez un certificado de firma propio: *Acceso a Llaveros › Asistente para certificados › Crear un certificado…*, con el nombre `VibeTranslator Dev` y el tipo *Firma de código*. Después compila así:

```bash
CODESIGN_IDENTITY="VibeTranslator Dev" scripts/build-app.sh
```

## Primer arranque

1. Abre la app. Aparece el icono de bocadillo en la barra de menú.
2. Concede el permiso de Accesibilidad cuando macOS lo pida, o desde el menú.
3. En el menú, abre **Idiomas español → inglés…** y pulsa **Descargar idiomas**.
4. En Discord, escribe un borrador, deja el cursor en el cuadro de mensaje y pulsa `⌃⌥T`.

## Validación técnica (editor de Discord y versión de macOS)

Menú › **Validación técnica**:

- **Diagnosticar campo activo**: en 3 s analiza el campo con foco. Informa de la versión de macOS y de Discord, de si es Electron y del resultado de `AXManualAccessibility`, y del rol, los atributos y las propiedades escribibles del elemento. También compara `AXValue` con lo que devuelve ⌘A ⌘C.
- **Diagnosticar y probar escritura** (con el borrador **vacío**): además comprueba:
  - A) si escribir por Accesibilidad (`AXSelectedText`) llega al **modelo** del editor, y no solo al DOM;
  - B) si el pegado multilínea llega intacto.

  Después limpia el campo. Nunca envía nada.

El informe se abre en una ventana y se guarda en `~/Library/Logs/VibeTranslator/`.

## Cómo accede al borrador

| Método | Lectura | Escritura |
| --- | --- | --- |
| Accesibilidad | `AXValue` del elemento con foco | Selecciona todo y sustituye `AXSelectedText` (o `AXValue`), y verifica leyendo de nuevo |
| Portapapeles | ⌘A ⌘C, y restaura el portapapeles | ⌘A ⌘C (comprueba que no ha cambiado), ⌘V, y restaura el portapapeles |

**Automático** (por defecto) usa el portapapeles en apps Electron como Discord y Accesibilidad en campos nativos, con el portapapeles como alternativa. En Discord el editor (Slate) mantiene su propio modelo del documento, así que:

- escribir por Accesibilidad puede cambiar lo que se ve sin cambiar lo que se envía;
- el copiar/pegar del propio editor conserva menciones y emojis personalizados en su forma canónica (`<@id>`, `<:nombre:id>`).

La prueba de escritura del diagnóstico confirma o descarta esto en tu versión de Discord. Las teclas ⌘A/⌘C/⌘V se resuelven según la distribución de teclado activa, así que funcionan también con AZERTY, Dvorak, etc.

## Motores de traducción

| Motor | Qué aporta | Privacidad |
| --- | --- | --- |
| **Apple Intelligence** (por defecto) | LLM en el Mac: sigue el tono, el glosario y tus instrucciones, y traduce expresiones por su sentido | Todo en local |
| **Ollama** | El modelo que elijas (`ollama pull …`) con el mismo perfil de estilo | Local, salvo los modelos `…cloud`, que la app marca como «nube» |
| **Apple Translation** | Traducción automática clásica: rápida y fiable, pero sin control del tono | Todo en local |

Los LLM reciben el borrador entero en una sola petición (`{"lines": [...]}`), así que cada línea tiene el contexto de las demás. La respuesta se valida:

- tiene que haber una línea por entrada;
- ninguna línea puede estar vacía;
- ninguna puede ser desproporcionadamente larga, porque eso suele indicar que el modelo ha respondido al mensaje en vez de traducirlo.

Si algo no cuadra, o el motor tarda más de 20 s, ese borrador se traduce con Apple Translation y el aviso lo indica.

## Cómo se protege el markup

`DraftTranslator` (en `VibeTranslatorCore`) trabaja línea a línea:

1. Separa los bloques de código ```` ``` ```` y no los traduce.
2. Guarda aparte la indentación y los prefijos de línea.
3. Sustituye cada fragmento protegido por un marcador `{n}` y traduce la línea completa para conservar el contexto.
4. Comprueba que cada marcador vuelve **exactamente una vez**. Si el motor ha perdido o duplicado alguno, traduce esa línea fragmento a fragmento, de modo que el markup nunca se pierde.

## Estructura

```
Sources/VibeTranslatorCore/   Lógica pura y testeada: markup, pipeline, protocolo del motor
Sources/VibeTranslator/
  AppModel.swift              Orquesta traducir / restaurar / diagnosticar
  Draft/DraftAccessor.swift   Lectura y reemplazo seguros (AX y portapapeles)
  System/                     Accesibilidad, atajos (Carbon), teclado, portapapeles
  Translation/                Motor Apple Translation y descarga de idiomas
  Settings/ UI/ Diagnostics/  Ajustes, HUD, informe de validación
Tests/VibeTranslatorCoreTests/
```

## Limitaciones conocidas del MVP

- Solo español → inglés.
- El tono solo se aplica con los motores LLM; Apple Translation no admite instrucciones.
- La mayúscula inicial de cada línea se ajusta en código para que coincida con el original, sea cual sea el motor.
- «Reemplazar» en una selección no tiene «Restaurar original»; usa ⌘Z en la propia app.
- Los enlaces con texto (`[texto](url)`) se conservan enteros, sin traducir el texto.
- Una traducción que supere el límite de caracteres de Discord puede hacer que Discord ofrezca enviarla como archivo.
- Si una mención aparece como «@Nombre Apellido» al leerla por Accesibilidad, solo se protege la primera palabra. Por eso en Discord se lee por portapapeles.

## Licencia

MIT. Consulta [LICENSE](LICENSE).
