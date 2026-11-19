# Integración con Jira

Importa a la lista las **tareas y subtareas asignadas a tu usuario** en Jira Cloud y permite
**enviar el tiempo medido a Jira** (botón de corte) como un registro de trabajo (worklog). El
inicio de sesión es OAuth 2.0 (3LO) y ocurre en el **navegador**: la app nunca ve tu
contraseña, ni si entras con Google u otro método.

## Cómo funciona

1. Pulsas **Iniciar sesión** en el diálogo de Jira (icono de nube en la barra superior).
2. La app abre en tu navegador predeterminado la página de autorización de Atlassian
   (`auth.atlassian.com`). Te autenticas como siempre y apruebas el acceso.
3. Atlassian redirige a `http://localhost:53682/callback`. La app escucha ahí solo durante
   el inicio de sesión (3 minutos como máximo), recibe un código de un solo uso y cierra el
   servidor. La pestaña muestra "Listo, ya puedes cerrar esta pestaña".
4. La app cambia el código por tokens y consulta a qué sitios Jira tienes acceso. Si hay
   más de uno, puedes elegirlo en el diálogo.
5. **Sincronizar** trae tus tareas y las incorpora a la lista.

El inicio de sesión ignora cualquier petición al puerto que no traiga el `state` correcto,
para que una web ajena no pueda inyectar un código ni abortar el flujo.

## Configuración (una sola vez)

Atlassian exige un `client_secret` al intercambiar el código por tokens y no ofrece PKCE
para apps Cloud. Por eso cada usuario usa una **app OAuth 2.0 (3LO)** creada en la consola
de desarrolladores y pega su Client ID y Secret en la app.

### 1. Crear o revisar la app en la consola

En <https://developer.atlassian.com/console/myapps/>:

| Sección | Qué configurar |
| --- | --- |
| **Authorization** → OAuth 2.0 (3LO) | Callback URL: `http://localhost:53682/callback` (exactamente así; Atlassian la compara literalmente). El diálogo de la app la muestra con un botón **Copiar**. |
| **Permissions** → Jira API → scopes clásicos | Marcar `read:jira-work` ("View Jira issue data") para importar, y `write:jira-work` ("Create and manage issues", que incluye crear worklogs) para el botón de corte. `offline_access` no se marca aquí: la app lo pide en la URL de autorización y es lo que permite refrescar el token. |
| **Distribution** | Mientras diga "Not sharing", solo el creador de la app puede iniciar sesión con ella. Para otros usuarios, activar **Sharing** (no hace falta publicar en el Marketplace). Verán un aviso de que Atlassian no ha revisado la app. |

### 2. Copiar las credenciales

En la misma consola: **Settings → Authentication details**.

- **Client ID:** campo visible, con botón de copiar.
- **Secret:** oculto, con botón de copiar. No pulses el botón de generar uno nuevo: invalida
  el actual.

El Secret equivale a una contraseña de la app. No lo compartas ni lo subas al repositorio.

### 3. Dárselas a la app: `.env` o formulario

La app saca el Client ID y el Secret de **uno de dos sitios**. Cuál se usa depende de cómo
se compiló:

| Situación | Qué hace la app |
| --- | --- |
| Compilada con un `.env` que tiene **las dos** claves | Las usa directamente. **No muestra el formulario** ni el botón "Credenciales"; el diálogo avisa de que vienen incluidas en la compilación y ofrece **Iniciar sesión** de una vez. |
| Compilada **sin** `.env`, o con un `.env` al que le falta alguna de las dos | Considera que no las tiene: **muestra el formulario** (Client ID y Client Secret), y lo que se escribe se guarda en el **almacén seguro del sistema**. |

#### Con `.env` (se compilan dentro de la app)

1. Copia `.env.example` como `.env`, junto a `pubspec.yaml`:

   ```
   JIRA_CLIENT_ID=tu-client-id
   JIRA_CLIENT_SECRET=tu-secret
   ```

2. Compila con el script del proyecto, que pasa el `.env` **solo si existe**:

   ```
   powershell -File tool/flutter_env.ps1 run -d windows        # Windows
   tool/flutter_env.sh run -d macos                            # macOS / Linux
   powershell -File tool/flutter_env.ps1 build windows --release
   ```

   El script avisa por consola si usa el `.env`, si no lo encuentra, o si está incompleto.
   (Es necesario porque `flutter run --dart-define-from-file=.env` **falla si el archivo no
   existe**, así que no se puede poner siempre.) También puedes pasarlo a mano:
   `flutter run -d windows --dart-define-from-file=.env`. En Android Studio, añádelo en
   *Run → Edit Configurations → Additional run args* (solo si el `.env` existe).

**Reglas:**

- **Mandan sobre lo guardado.** Con las credenciales compiladas, la app ignora lo que hubiera en
  el almacén seguro y no permite cambiarlas desde el diálogo.
- **Si antes guardaste a mano credenciales de OTRA app de Atlassian**, al abrir la app compilada
  con `.env` esas credenciales se **borran junto con su sesión**: ese token se hizo con otro
  cliente y no se podría renovar con éste. Si el Client ID del `.env` es el mismo que el
  guardado, la sesión se conserva.
- **No se copian al almacén seguro**: ya están en el binario; duplicarlas no aporta nada.
- **`.env` nunca se sube al repositorio**: está en `.gitignore` (junto con cualquier `.env.*`,
  salvo `.env.example`, que sí se versiona y va con las claves vacías).
- Formato: el de cualquier `.env` (comentarios con `#`, valores con o sin comillas, espacios
  dentro de comillas). Lo lee Flutter, no hace falta ningún paquete.

**Riesgo:** quien tenga el binario compilado puede extraer el Secret (se comprobó: queda dentro
del ejecutable). Úsalo para tu propia máquina o para una app de Atlassian que aceptes que sea de
uso interno; no distribuyas ese binario fuera. Si quieres evitar el riesgo, la opción sería un
servidor intermedio que guarde el secreto y haga el intercambio de tokens; hoy no existe.

#### Sin `.env` (formulario)

Diálogo de Jira → Client ID y Client Secret → **Guardar**. Ambos se guardan en el **almacén
seguro del sistema operativo** (nunca en SQLite) y el secreto ya no se vuelve a mostrar. Dejar el
campo del secreto vacío al guardar conserva el actual. Cambiar el Client ID cierra la sesión. Una
vez guardadas, el diálogo ofrece **Credenciales** para cambiarlas.

Un `.env` **incompleto** (por ejemplo, solo el ID) se trata como "sin credenciales": se muestra
el formulario con el ID ya rellenado y solo falta escribir el Secret.

## Qué se importa

Consulta (JQL):

```
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

`currentUser()` lo resuelve Jira con el token, así que solo devuelve lo asignado a quien
inició sesión. Quedan fuera las tareas terminadas.

Cada tarea **o subtarea** se vuelve una entrada independiente de la lista, con su propio
cronómetro:

| Campo | Contenido |
| --- | --- |
| Nombre | `KEY-12 Resumen` |
| Descripción | Texto plano de la descripción de Jira. En subtareas empieza por "Subtarea de KEY-1". |
| Enlace | `https://<sitio>.atlassian.net/browse/KEY-12` |
| Estado | El estado del ticket en Jira ("Por hacer", "En curso", "Listo"…), como etiqueta de color en la tarjeta y en el detalle |
| Seguimiento de tiempo | La estimación original, el tiempo registrado y el restante del ticket en Jira, en el detalle (icono ⓘ) |

**Seguimiento de tiempo.** El detalle del ticket muestra una sección *Seguimiento de tiempo ·
Jira* con tres valores y una barra de progreso:

- **Estimado:** la estimación original del ticket.
- **Registrado:** el tiempo que ya hay registrado en Jira. Es la **suma de los registros de
  todos los usuarios**, no solo los que enviaste desde esta app (por eso es distinto del
  "En Jira: …" de la tarjeta, que cuenta únicamente lo que enviaste tú con el corte).
- **Restante:** el tiempo restante estimado.

La barra compara lo registrado con la estimación (si no hay estimación, con registrado +
restante, como el gráfico de Jira). Si lo registrado supera la estimación, la barra y el
valor se ponen en rojo con el aviso "Se pasó de la estimación".

Lo que Jira no informa se muestra como **"—"**, no como 0: un ticket sin estimación no
tiene "estimado 0". Si el seguimiento de tiempo está desactivado en el proyecto de Jira,
la sección no aparece. Los valores se leen del campo `timetracking` con el mismo permiso de
lectura (`read:jira-work`); no hace falta ningún permiso nuevo.

**Colores del estado.** Cada proyecto de Jira puede nombrar sus estados como quiera, así que
el color sale de la *categoría* que define Jira, no del nombre: **gris** = por hacer (`new`),
**azul** = en curso (`indeterminate`), **verde** = terminado (`done`). Un estado largo se
recorta con "…" en la tarjeta (el nombre completo sale al pasar el cursor y en el detalle).

Las entradas se identifican por la clave de Jira (columna `jira_key`, índice único). Al
**volver a sincronizar**:

- Se actualizan nombre, descripción, enlace, **estado** y **seguimiento de tiempo**.
- **No se toca el tiempo medido ni el estado del cronómetro.**
- No se duplican entradas.
- Las tareas que dejaron de estar asignadas o se terminaron **se conservan** en la lista;
  se borran a mano.
- **El estado y el seguimiento de tiempo de esas tareas que ya no aparecen también se
  refrescan.** La búsqueda solo trae pendientes asignados a ti, así que un ticket que pasa a
  "Listo" dejaría de venir y quedaría con los datos viejos. Por eso, tras importar, la app
  consulta aparte esos datos de los tickets ya importados que no vinieron (`key in (…)`, en
  grupos de 50). Si Jira deja de informar un valor (por ejemplo, le quitan la estimación),
  se borra también aquí. Si una clave
  ya no existe o no tienes acceso, se omite sin afectar a las demás. Si esa consulta falla,
  lo importado se conserva y el mensaje avisa "No se pudo refrescar el estado de tickets
  anteriores".
- Si editas a mano una entrada importada, la siguiente sincronización sobrescribe esos
  cambios.

Límites: se piden páginas de 100 resultados, con un tope de 50 páginas (5000 issues).

## Corte: enviar el tiempo a Jira

Cada entrada importada de Jira tiene un botón de **corte** (icono de nube con flecha). Al
pulsarlo:

1. Se abre un diálogo con el **resumen** de lo que se va a registrar. Escribir en Jira no se
   puede deshacer desde la app, por eso se revisa y se confirma antes de enviar. Puedes
   **modificar**:
   - el **tiempo a registrar**, en **horas y minutos** (sin segundos; empieza con lo medido; si lo
     cambias aparece **Usar el medido** para volver al valor original);
   - la casilla **Reiniciar el cronómetro al subir** (marcada por defecto);
   - un **comentario** opcional.

   El recuadro **Resumen** se actualiza mientras editas y muestra: lo que **se registrará**,
   el **inicio aproximado** (*ahora menos la duración*) y lo que **quedará en el reloj** tras
   el corte (en cero si reinicias).
2. Al pulsar **Enviar a Jira** se crea un worklog en el ticket
   (`POST /rest/api/3/issue/{key}/worklog`) con la duración confirmada, esa hora de inicio y
   el comentario (en formato ADF).
3. **Solo si Jira responde que lo creó**, la app vuelve a leer el ticket para actualizar su
   *Registrado* y *Restante* (Jira los ajusta solo al crear el registro). Si esa relectura
   falla no se muestra error: el registro ya está hecho y la siguiente sincronización lo
   corrige. Después, lo enviado se resta del cronómetro y se suma al
   total de la tarjeta ("En Jira: 1 h 05 m"):
   - si enviaste **menos** de lo medido, **lo que sobra se conserva** en el cronómetro;
   - si enviaste **más**, el cronómetro queda en 00:00:00;
   - si el cronómetro corría, **sigue corriendo** con lo que quede. El tiempo que pasó
     mientras tenías abierto el diálogo o durante la llamada de red no se pierde.

Reglas y límites:

- Solo hay botón en entradas de Jira; las creadas a mano no lo tienen.
- El tiempo a registrar debe estar entre **1 minuto y 24 horas**. Son salvaguardas de la app
  (el mínimo no está confirmado en Jira; el máximo atrapa errores de tecleo). Fuera de ese
  rango el botón **Enviar a Jira** queda deshabilitado y el diálogo lo explica.
- La **hora de inicio** no se edita: siempre es *ahora menos la duración*.
- Necesita el permiso `write:jira-work`. Si todavía tienes una sesión de antes de que
  existiera el corte (solo lectura), el botón abre el diálogo de Jira con un aviso:
  **cierra sesión e inicia de nuevo** para conceder el permiso de escritura.
- Si Jira falla, **no cambia nada local** y puedes reintentar. Si falla la **red**, la app no
  puede saber si Jira llegó a crear el registro: revisa el ticket antes de reintentar para no
  duplicarlo.
- Un corte a la vez. No se editan ni borran worklogs desde la app; se hace en Jira.

## Cambiar el estado de un ticket

Pulsa el **chip de estado** («Por hacer», «En curso»…) de un ticket de Jira, en su tarjeta o en
el diálogo de **Información**. La app pide a Jira los cambios que el flujo del proyecto permite
desde el estado actual (`GET /issue/{key}/transitions`) y los muestra; al elegir uno ejecuta la
transición (`POST /issue/{key}/transitions`).

- Usa el permiso `write:jira-work` que ya se pide para el corte; una sesión antigua de solo
  lectura debe volver a iniciar sesión.
- **Solo si Jira acepta** el cambio se actualiza el estado guardado en la app (y se relee el
  ticket por si Jira ajusta algo más). Si falla, no cambia nada localmente.
- Si la transición exige campos obligatorios (pantalla de transición), Jira responde 400: la app
  avisa de que hay que hacerlo desde Jira; no rellena campos por ti.
- Los estados disponibles dependen del flujo de cada proyecto. Nunca se cambian en silencio: la
  única vía automática es la **pregunta al pulsar play** (abajo).

### Pregunta al iniciar el cronómetro

Si el ticket es de Jira, hay sesión con permiso de escritura y su estado es «Backlog» o
«Selected for Development» (también «Seleccionado para desarrollo»), al pulsar play la app
pregunta **¿Poner el ticket en curso?**:

- **Poner en curso:** arranca el cronómetro y pide a Jira la transición de categoría «en curso»
  (prefiere la llamada «In Progress» / «En curso» / «En progreso»; si hay varias sin un nombre
  claro, abre el menú de estados para que elijas).
- **Solo iniciar:** arranca el cronómetro sin tocar Jira.
- **Cancelar:** no hace nada.

Si Jira rechaza el cambio (por ejemplo, la transición exige campos obligatorios), el cronómetro
corre igual y se avisa con un mensaje. Sin sesión o sin permiso de escritura no se pregunta.

## Progreso del día y corte del día (opcional)

Bajo la barra superior se ve el **progreso del día**: la suma de lo que marcan **ahora** los
cronómetros de todos los tickets frente a la **meta** (`DAILY_HOURS` en `.env`, por defecto 8 h;
se lee al compilar). Si limpias un ticket o subes su tiempo con reinicio, deja de contar. Lo
**subido a Jira hoy** se ve aparte, en verde ("· subido 2 h"), no se suma al total de los
tickets y vuelve a cero al cambiar el día (se guarda en `day_sent`).

**El corte no se abre solo ni es obligatorio.** El botón de nube de esa franja abre el **Corte del día**
cuando tú quieras:

- Lista **todos los tickets con al menos 1 minuto**. Los de Jira traen **horas y minutos**
  (lo medido, sin segundos) y se pueden editar; los manuales se ven pero no se suben.
- **Subir** (por ticket) o **Subir todos**: un worklog por ticket, con `started = ahora − duración`.
  Un ticket que falla no detiene a los demás; el error sale en su fila y se puede reintentar.
- **Los segundos no cuentan.** Se sube lo que escribas en horas y minutos. La casilla
  **Reiniciar el cronómetro al subir** (marcada por defecto) deja el cronómetro en cero; sin
  marcar, conserva lo que sobre. El corte por ticket de cada tarjeta tiene la misma casilla.
- La suma de lo reportado (subido hoy + lo que vas a subir) se compara con la meta: **menos de
  7 h** = Faltan (mínimo), **7 h a menos de 8 h** = Aceptable, **8 h** = Día completo, **más** =
  Sobran (permitido). Solo es una referencia: avisa, no impone. El mínimo sale de
  `DAILY_MIN_HOURS` (7 por defecto; nunca pasa de la meta).
- **Día trabajado, solo control interno:** cada ticket tiene un selector con dos escenarios,
  **Hoy** y **Anterior** (el día desde el que viene su tiempo o, si no se sabe, el día hábil
  anterior; puede ser de varios días atrás si no registraste desde la última vez que usaste la
  app). **A Jira solo viaja el tiempo**: el worklog siempre lleva `started = ahora − duración`,
  nunca una fecha pasada. El día solo sirve para que la app lleve los cortes por día sin
  encimar: solo lo subido para **hoy** cuenta en "subido hoy" y en el total frente a la meta;
  lo de otros días se muestra aparte ("para otros días").
- **Aviso de tiempo de días anteriores:** la app guarda desde cuándo viene el tiempo de cada
  cronómetro (`time_since_ms`). Si es de un día anterior, la franja del progreso avisa y el corte
  sugiere ese día. Los cronómetros anteriores a esta función no tienen esa fecha y no avisan.
- **Ese ticket no se puede iniciar** hasta subir su tiempo anterior (o limpiarlo): el play queda
  desactivado con el aviso "Sube o limpia primero el tiempo del dd/MM de este ticket" (en un
  ticket manual, "Limpia primero…", porque no se puede subir). Así un mismo cronómetro no
  mezcla días. Solo afecta a ese ticket; pausar siempre se puede, un cronómetro en marcha no se
  detiene y lo que sobre por debajo de 1 minuto (que no se puede subir) no bloquea. El botón de
  corte de esa tarjeta abre el corte del día.
- Sin sesión de Jira (o sin permiso de escritura) el diálogo avisa y ofrece abrir Jira.

Un corte por ticket (botón de la tarjeta) también cuenta como subido hoy y anota el tiempo
como de hoy; si el ticket trae tiempo de un día anterior, su diálogo avisa de que use el corte
del día para anotarlo en el día trabajado.

Al actualizar a esta versión se **borran** las tablas `work_intervals` y `day_cuts` del
historial de la versión anterior (la base pasa a v7 y luego a v8, que añade `time_since_ms`); proyectos, ajustes y lo subido se
conservan. **Sin verificar contra Jira real:** el envío de worklogs se probó con Atlassian
simulado.

## Sesión y seguridad

- **Dónde se guarda:** Client Secret y tokens van al almacén seguro del sistema operativo
  (en macOS, el keychain heredado, para no requerir el entitlement "Keychain Sharing").
  Nada de esto está en SQLite.
- **Caducidad:** el token de acceso se refresca solo antes de consultar. Si Jira responde
  `401`, refresca y reintenta una vez; si sigue fallando, cierra la sesión y pide iniciar
  de nuevo.
- **Cerrar sesión** borra la sesión local. No revoca el acceso en Atlassian: para eso, en
  tu cuenta de Atlassian, apps conectadas.
- **Permisos pedidos:** `read:jira-work`, `write:jira-work` y `offline_access`. Aunque
  `write:jira-work` permite en la API crear y editar issues, **la app solo crea worklogs**,
  y solo cuando pulsas Enviar en el diálogo de corte. No modifica ni borra nada más.
- **Sesiones antiguas:** la sesión guarda los scopes concedidos. Una sesión de antes del
  corte no tiene permiso de escritura y la app lo detecta.

## Solución de problemas

| Síntoma | Causa probable |
| --- | --- |
| "El puerto 53682 está ocupado" | Otro programa usa ese puerto. Ciérralo e inténtalo de nuevo. |
| "Se agotó el tiempo para iniciar sesión" | No completaste el inicio de sesión en 3 minutos. Vuelve a pulsar **Iniciar sesión**. |
| "No se pudo abrir el navegador" | El sistema no tiene un navegador predeterminado configurado. |
| El navegador muestra un error de Atlassian sobre la URL de redirección | La Callback URL de la consola no coincide con `http://localhost:53682/callback`. |
| `invalid_client` o "Atlassian rechazó la autenticación" | Client ID o Secret equivocados o regenerados. Vuelve a copiarlos de Settings. |
| `failed to retrieve client` para otros usuarios | La app sigue en "Not sharing" o hay un problema de distribución. Hay reportes de este error incluso con Sharing activado. |
| "La cuenta no tiene sitios de Jira accesibles" | La cuenta no tiene acceso a ningún sitio Jira, o falta el scope `read:jira-work`. |
| `401 scope does not match` al sincronizar | Hay reportes de que algunas configuraciones exigen scopes granulares además del clásico. Agrégalos en Permissions → Jira API → Granular scopes. |
| "Falta el permiso de escritura en Jira" (al cortar) | La sesión se inició antes de añadir `write:jira-work`, o la app de la consola no tiene ese scope. Añádelo en Permissions y cierra sesión / inicia de nuevo. |
| "No tienes permiso para registrar tiempo en KEY" (403) | Tu usuario no puede registrar trabajo en ese proyecto (permiso "Work on issues" de Jira), o falta el scope de escritura. |
| "KEY no existe o no tienes acceso" (404) | El ticket se movió, se borró o ya no tienes acceso. |
| "No se pudo confirmar el envío" | Falló la red durante el envío. Revisa el ticket en Jira antes de reintentar. |
| "No se pudo refrescar el estado de tickets anteriores" | Falló la consulta de estados tras importar (red o Jira). Lo importado está guardado; vuelve a sincronizar. |
| Un ticket terminado sigue mostrando "En curso" | No se ha vuelto a sincronizar desde que cambió de estado. Pulsa **Sincronizar**. |
| No aparece "Seguimiento de tiempo" en un ticket | El proyecto de Jira tiene el seguimiento de tiempo desactivado, o Jira no informó ningún valor para ese ticket. |
| "Registrado" no coincide con "En Jira" de la tarjeta | Es normal: "Registrado" suma a todos los usuarios; "En Jira" solo lo enviado desde esta app. |
| "Jira rechazó la sesión. Inicia sesión de nuevo" | Token revocado o caducado sin posibilidad de refrescar. Inicia sesión otra vez. |
| Entrar con Google | Debería funcionar sin cambios (la autenticación ocurre en Atlassian), pero no se ha probado. Si tu empresa fuerza SSO o restringe apps de terceros, el administrador puede tener que aprobar la app. |

## Código

| Archivo | Responsabilidad |
| --- | --- |
| `lib/data/datasources/jira_oauth.dart` | Servidor local de un solo uso, URL de autorización, intercambio y refresco de tokens, sitios accesibles |
| `lib/data/datasources/jira_api.dart` | Búsqueda paginada (`/rest/api/3/search/jql`), estado y seguimiento de tiempo por clave (`liveInfoFor`), creación de worklogs y conversión de la descripción (ADF) a texto |
| `lib/presentation/viewModels/jira_controller.dart` | Estado, inicio y cierre de sesión, sincronización, corte (`logWork`) y `_withToken` (refresco con un reintento, compartido) |
| `lib/domain/entities/jira_entities.dart` | Sesión, tokens, sitio, issue y excepciones |
| `lib/data/datasources/secret_store.dart` | Almacén seguro (real) y en memoria (pruebas) |
| `lib/presentation/screens/dialogs/jira_dialog.dart` | Diálogo: credenciales, URL de callback con botón Copiar, sesión, sincronizar |
| `lib/widgets/chips/status_chip.dart` | Etiqueta de estado con color por categoría |
| `lib/domain/entities/jira_live.dart` | Datos de Jira que cambian solos (estado y seguimiento de tiempo), usados para refrescar |
| `lib/presentation/screens/dialogs/jira_cut_dialog.dart` | Diálogo de corte: resumen en vivo, tiempo y comentario editables, envío |
| `test/jira_test.dart` | Pruebas con Atlassian simulado, incluido el servidor local real |
| `test/jira_cut_test.dart` | Pruebas del corte (incluido el tiempo editado), del permiso de escritura, del formato de fecha y de la migración de la base de datos |
| `test/jira_status_test.dart` | Pruebas del estado y del seguimiento de tiempo: lectura, consulta por clave (grupos de 50, claves inválidas, clave inexistente), refresco al sincronizar y migración de la base de datos |
| `test/jira_status_ui_test.dart` | Pruebas de widget: etiqueta de estado y sección de seguimiento de tiempo (normal, excedida, ausente, ventana mínima) |
| `test/jira_cut_dialog_test.dart` | Pruebas de widget del diálogo de corte: resumen, edición, límites y ventana mínima |

Las pruebas cubren: conversión de ADF, paginación y subtareas, el flujo OAuth contra el
servidor local (con una petición ajena que debe ignorarse), refresco por caducidad y por
`401`, cierre de sesión, credenciales compiladas y que sincronizar no pierda el tiempo
medido. Las del corte cubren el cuerpo del worklog, éxito, fallos de Jira y de red, el mínimo
de 1 minuto, sesión sin permiso de escritura y refresco con reintento. Ninguna usa un Jira real.

## Estructura del código de Jira

Las reglas del corte no viven en el controlador sino en el dominio, y se prueban sin red ni
base de datos (`test/domain/usecases_test.dart`):

- `PrepareWorklog` (`lib/domain/usecases/`): valida el tiempo (1 min – 24 h) y calcula el inicio
  (*ahora menos la duración*).
- `ApplyJiraCut`: qué le pasa al cronómetro tras el corte.
- `FindStaleJiraKeys`: qué tickets ya importados hay que refrescar porque dejaron de venir en
  la búsqueda.

`JiraController` coordina: pide el token, llama a la API y a esas reglas, y actualiza el estado
que ve la interfaz. Hoy usa los datasources de Jira directamente, sin un `JiraRepository`
(ver [architecture.md](architecture.md), "Desviaciones").

## El diálogo de Jira

- Siempre tiene un botón **Cerrar** (a la izquierda de la acción principal), en todos los
  estados: sin credenciales, con credenciales sin sesión, con la sesión iniciada y editando las
  credenciales. **No se desactiva mientras se espera al navegador**: se puede cerrar el diálogo y
  el inicio de sesión sigue en segundo plano. También se cierra con `Esc` o pulsando fuera.
- El pie solo lleva "Cerrar" y la acción principal (**Iniciar sesión** o **Sincronizar**). Las
  acciones poco frecuentes —**Credenciales** y **Cerrar sesión**— están en el cuerpo.
- La URL de callback va siempre visible, con el botón **Copiar** junto a su título.

## Referencias

- [Guía de OAuth 2.0 (3LO)](https://developer.atlassian.com/cloud/oauth/getting-started/implementing-oauth-3lo/)
- [Gestión de apps OAuth y distribución](https://developer.atlassian.com/cloud/oauth/getting-started/managing-oauth-apps/)
- [Búsqueda de issues en la API REST v3](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/)
