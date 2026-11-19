# UI kit

Todo lo visual de la app sale de dos carpetas:

- **`lib/config/theme/`**: el *qué se ve* —tema, colores, tokens (espacios, radios, tamaños de
  letra), límites por vista e iconos.
- **`lib/widgets/`**: el *con qué se construye* —los componentes reutilizables.

Las pantallas importan dos barriles y construyen la interfaz con estas piezas, no con los
widgets de Material "sueltos":

```dart
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
```

**Cambiar el aspecto de la app es cambiar un número o un componente aquí**, y cambia en toda
la app. La prueba `test/core/ui_kit_test.dart` ("nadie se salta el kit") impide usar `Icons.*`,
`IconButton`, `TextField`, `InputDecoration`, `ThemeData` o colores fijos (`Color(0x…)`) fuera
de su sitio.

## Tokens (`config/theme/app_tokens.dart`)

| Token | Valores |
| --- | --- |
| `AppSpacing` | `xs` 4 · `sm` 8 · `md` 12 · `lg` 16 · `xl` 24 · `panel` 10 |
| `AppRadius` | `sm` 8 · `md` 12 · `lg` 16 · `xl` 24 (y `smAll`, `mdAll`… como `BorderRadius`) |
| `AppFontSize` | `micro` 10 · `caption` 11 · `label` 12 · `body` 13 · `title` 16 · `appBar` 17 · `dialogTitle` 18 · `timer` 20 · `compactTimer` 24 |
| `AppMotion` | `fast` 220 ms |
| `AppIconButtonSize` | `compact` 30 (icono 18) · `regular` 36 (icono 20) · `large` 40 (icono 24) |

## Límites por componente y por vista (`config/theme/app_limits.dart`)

Son los números que hacen que las piezas "se acuerden" entre sí. Un componente o una
pantalla lee su medida de aquí; no la inventa.

| Límite | Valor | Para qué |
| --- | --- | --- |
| `WindowLimits.min` | 360 × 242 | tamaño **mínimo** de la ventana (la medida original 300×220 más 20 % de ancho y 10 % de alto) |
| `WindowLimits.startFor(pantalla)` | ½ × ½ de la pantalla | tamaño de **arranque**: un cuarto de la pantalla, nunca menor que el mínimo |
| `WindowLimits.compact` | 280 × 140 | tamaño de PARTIDA de la ventana de la vista simple: el ancho es fijo y el alto se ajusta solo al contenido (`WindowService.fitCompact`), porque la barra de título del sistema ocupa más o menos según el equipo |
| `WindowLimits.compactMin` | 280 × 60 | mínimo que admite esa ventana mientras se ajusta |
| `ChipLimits.maxWidth` | 240 | una etiqueta nunca pasa de este ancho; el texto se recorta con "…" |
| `ChipLimits.maxLines` | 1 | una etiqueta es de una sola línea |
| `FieldLimits.maxLinesCap` | 6 | tope de líneas de cualquier campo multilínea |
| `FieldLimits.multilineDefault` | 4 | líneas por defecto de descripción y comentario |
| `FieldLimits.hoursDigits` / `minutesSecondsDigits` | 3 / 2 | dígitos de los campos de horas y minutos del corte (por ticket y del día) |
| `DialogLimits.formWidth` | 300 | ancho del contenido de formularios, Jira y corte |
| `DialogLimits.compactWidth` | 260 | ancho de diálogos pequeños |
| `DialogLimits.infoMaxWidth` | 420 | ancho máximo del detalle del ticket |
| `DialogLimits.infoCompactBelow` | 170 | por debajo de este alto el detalle pasa a su versión compacta |
| `CompactLimits.nameMaxLines` | 1 | el nombre en la vista simple |
| `CompactLimits.opacityRowHeight` | 28 | alto de la fila del deslizador de transparencia de la vista simple |
| `TileLimits.*` | ver abajo | la fila de controles de una tarjeta |

### La fila de una tarjeta

```
[play 40] 8 [cronómetro ≤96] [ — etiqueta de estado — ] [limpiar 30][cortar 30][info 30]
```

Todo tiene ancho fijo salvo la etiqueta, que ocupa el hueco central. En la ventana mínima ese
hueco es de **87 px** (`TileLimits.statusSlotWidth(WindowLimits.min.width)`), por encima del
mínimo de 84 (`statusSlotMinWidth`) con el que "Por hacer" o "En curso" se leen enteros. Un
estado más largo se recorta con "…" y su nombre completo sale al pasar el cursor.

Si se agrega un botón a la tarjeta, o se agranda el cronómetro, el hueco se encoge: la prueba
`límites › la etiqueta de estado dispone de su ancho mínimo` lo detecta.

## Iconos (`config/theme/app_icons.dart`)

Los iconos tienen nombre por su **función**, no por su forma (`AppIcons.cutToJira`, no
`Icons.cloud_upload_outlined`). Para cambiar un icono se cambia ahí y cambia en toda la app.
Ninguna pantalla usa `Icons.*` directamente.

## Componentes (`lib/widgets/`)

| Componente | Carpeta | Para qué | Límites y reglas |
| --- | --- | --- | --- |
| `AppIconButton` | `buttons/` | único botón de icono | exige `tooltip`; 3 tamaños; 3 variantes (`plain`, `tonal`, `filled`); fija los colores de `tonal`/`filled` para que una `AppBar` no los pise |
| `AppTextField` | `inputs/` | único campo de texto | constructores: normal, `.multiline` (tope `FieldLimits`), `.secret`, `.digits` (solo dígitos, centrado, máximo de dígitos) |
| `RobustPaste` | `inputs/` | `Ctrl+V` con reintentos | ya aplicado dentro de `showFittedDialog` |
| `AppChip` | `chips/` | estado o dato corto | una línea; `maxWidth` ≤ `ChipLimits.maxWidth`; tonos `neutral`, `accent`, `success`, `danger`, `brand`; variantes `badge` (con borde) y `soft` (plana, con icono); `muted` = "aún sin dato" |
| `JiraStatusChip` | `chips/` | estado de un ticket de Jira | traduce la *categoría* de Jira a un tono (`done` → verde, `indeterminate` → acento, `new` → neutro) |
| `AppPanel` | `layout/` | caja redondeada que agrupa contenido | variantes `filled` y `outlined`; con `onTap` es pulsable |
| `AppSectionLabel` | `layout/` | rótulo de sección | se escribe en minúsculas normales y el componente lo pone en mayúsculas |
| `AppEmptyState` | `layout/` | vista vacía con acción opcional | se centra y hace scroll si la ventana es muy baja |
| `AppDialogBody` | `layout/` | contenido de un diálogo | ancho de `DialogLimits` y scroll vertical |
| `showFittedDialog` | `dialogs/` | `showDialog` que agranda la ventana | mide el alto natural del diálogo y agranda la ventana si no cabe; la restaura al cerrar |

## Reglas de uso

- **Un campo de texto, un botón de icono o una etiqueta nuevos** se hacen con el componente
  del kit. Si falta una variante, se agrega al componente, no se improvisa en la pantalla.
- **Un color que no sale del `ColorScheme`** (como el verde de "terminado") va en
  `AppColors`, con su versión para claro y oscuro y un contraste verificado por prueba (≥ 3:1
  en todos los tonos de `AppChip`, en ambos temas).
- **Un componente no conoce la lógica de la app**: no importa view models, repositorios ni
  casos de uso (lo comprueba `architecture_test.dart`).
- **Los diálogos** se abren con `showFittedDialog` y su cuerpo va en `AppDialogBody`; la única
  excepción es el detalle del ticket, que no agranda la ventana sino que se adapta a su alto.

## Cómo agregar un componente

1. Crear `lib/widgets/<tipo>/app_<nombre>.dart` con un nombre `App…`.
2. Leer colores del `Theme` y medidas de los tokens y límites; si hace falta una medida nueva,
   añadirla a `app_tokens.dart` o `app_limits.dart` (con un comentario de dónde se usa).
3. Exportarlo en `lib/widgets/widgets.dart`.
4. Probarlo en `test/core/ui_kit_test.dart`: tamaño, límites, estados deshabilitado/vacío y
   que no desborde en la ventana mínima.


## Búsqueda y filtros de la lista

- `AppTextField.search(controller:, label:, onChanged:)`: campo denso de una línea con lupa y botón
  de borrar (`AppIcons.clear`). Es la única forma de poner un cuadro de búsqueda.
- `FilterBarLimits` (`config/theme/app_limits.dart`): alto de la barra (= botón regular + margen) y
  ancho mínimo del campo (120 px). La barra es de **una sola fila** para no quitarle alto a la lista en
  la ventana mínima 360×242.
- Iconos nuevos: `AppIcons.search`, `clear`, `filter`, `sort`.
