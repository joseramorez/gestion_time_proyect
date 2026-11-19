# my-jira-work-time (gestion_time_proyect)

Cronómetro de escritorio para medir el tiempo que dedicas a cada proyecto o ticket.
Ventana compacta, con una **vista simple** que flota sobre otras ventanas mostrando solo el
ticket en curso, y con transparencia ajustable. Los datos se guardan en SQLite y,
opcionalmente, puedes importar tus tareas de Jira.

**Plataformas:** solo escritorio — Windows, macOS y Linux. Android, iOS y web se
eliminaron a propósito; no las vuelvas a agregar.
(Para regenerar una carpeta de escritorio: `flutter create --platforms=windows,macos,linux .`)

## Qué hace

- **Proyectos o tickets** con nombre, descripción y enlace. En la lista se ve el nombre, el
  cronómetro, el estado de Jira (si lo hay) y los botones; el icono ⓘ abre el detalle: nombre,
  etiqueta de Jira, tiempo medido y enviado a Jira, descripción, enlace clicable y los
  botones de editar y eliminar. El detalle **nunca pasa del alto de la ventana**: una
  descripción larga se trunca con "…" y **Ver más** la abre en una zona con scroll.
- **Cronómetro por proyecto:** iniciar, pausar, reanudar y limpiar (pone el tiempo en cero
  y detiene el cronómetro). El tiempo es independiente en cada proyecto.
- **Solo uno corre a la vez:** al iniciar un proyecto se pausa el que estuviera corriendo.
- **El tiempo sobrevive al cierre de la app:** se guarda cuándo arrancó el cronómetro, no
  un contador que avanza, así que un proyecto en marcha sigue contando al reabrir.
- **Vista simple** (icono del pin): solo se puede abrir **con un ticket en curso**; sin
  uno el pin está desactivado y su aviso explica por qué (la vista no tendría sentido). La
  ventana se encoge y muestra **solo el ticket que está corriendo, con su nombre y su
  tiempo**, más un **deslizador de transparencia propia** (30 %–100 %, independiente de la de
  la vista completa). Es de solo lectura, queda siempre encima de las otras ventanas y
  **ajusta sola su tamaño al contenido**, sea cual sea el alto de la barra de título de tu
  equipo. **Para volver a la vista completa:** el **botón de la esquina** (siempre visible),
  **doble clic** sobre el nombre o el tiempo, o la tecla **Esc**. Si el ticket dejara de
  correr estando en esta vista, vuelve sola. El cronómetro sigue corriendo todo el tiempo y
  la app siempre arranca en la vista completa.
- **Ventana** (icono de engranaje): dos controles de **transparencia** —uno para la vista
  completa y otro para la simple, del 30 % al 100 % (el mínimo evita que la ventana se vuelva
  invisible)— y el interruptor **Mantener encima de otras ventanas** de la vista completa.
- **Play en un ticket sin empezar:** si el ticket de Jira está en «Backlog» o «Selected for
  Development», al pulsar play pregunta si además lo pones **en curso** (Poner en curso / Solo
  iniciar / Cancelar). El cronómetro arranca igual aunque Jira rechace el cambio.
- **Buscar, filtrar y ordenar la lista:** una fila bajo el progreso del día con el cuadro de
  búsqueda (nombre, clave y descripción, sin importar mayúsculas ni tildes), el menú de **orden**
  (original, nombre, más tiempo, por estado, en curso primero) y el botón de **filtros**: estados de
  Jira, origen (Jira/manuales), en curso/pausados, con tiempo por subir, arrastran tiempo de otro
  día y ocultar finalizados (**activado por defecto**; no oculta un finalizado que corre o tiene
  tiempo por subir). Con filtros activos, o con finalizados ocultos, muestra «Mostrando X de Y» con **Limpiar** o **Mostrar finalizados**. Se recuerdan
  al reabrir la app (la búsqueda no). Solo cambian lo que se ve: el progreso del día cuenta todo.
- **Cambiar el estado de un ticket de Jira:** pulsa su chip de estado (tarjeta o Información) y
  elige uno de los estados que el flujo permite; solo se refleja en la app si Jira lo acepta.
- **Sincronizar Jira automáticamente** (interruptor en **Ventana**, activo por defecto): con la
  sesión de Jira iniciada y la app abierta, trae tus tickets **cada 2 horas** (la leyenda del
  ajuste muestra el intervalo). Se cambia con `JIRA_AUTO_SYNC_HOURS` en `.env` (horas, acepta
  decimales; mínimo 5 min) y se aplica al compilar.
- **Confirmar al cerrar** (interruptor en **Ventana**, activo por defecto): al cerrar la app
  pregunta antes. Si hay tickets en curso ofrece **Pausar y cerrar**, **Subir a Jira y cerrar**
  (pausa, sube las horas y minutos con reinicio y solo cierra si Jira lo aceptó; si falla, avisa
  y no cierra) o **Dejar corriendo** (el tiempo sigue contando al volver a abrir). Apagado,
  cierra sin preguntar.
- **Ventana:** arranca centrada y ocupando **un cuarto de la pantalla** (la mitad de ancho y
  la mitad de alto); el mínimo sigue siendo 360×242 y puedes cambiar su tamaño. Si un diálogo necesita más alto del que tiene la ventana, esta se agranda
  sola mientras el diálogo está abierto y vuelve a su tamaño al cerrarlo.
- **Jira (opcional):** inicio de sesión OAuth 2.0 en el navegador, importación de las
  tareas y subtareas asignadas al usuario **con su estado en Jira** (etiqueta de color) y su
  **seguimiento de tiempo** (estimado, registrado y restante), y **botón de corte** que envía
  el tiempo medido del ticket a Jira como worklog. Antes de enviar muestra un **resumen** y
  deja modificar el tiempo y el comentario. El diálogo de Jira siempre tiene un botón
  **Cerrar**. El Client ID y el Secret de tu app de Atlassian pueden venir de un archivo
  **`.env`** (se compilan dentro de la app y el diálogo ya no los pide) o, si no hay `.env`,
  se escriben en el diálogo y se guardan en el **almacén seguro** del sistema. Ver
  [docs/jira.md](docs/jira.md).
- **Progreso del día y corte del día (opcional):** bajo la barra superior se ve **lo que marcan
  ahora los cronómetros de todos los tickets frente a la meta** ("Hoy 5 h 40 m / 8 h"). Si
  limpias un ticket o subes su tiempo con reinicio, deja de contar. Lo **subido a Jira hoy** se
  ve aparte y en **verde** ("· subido 2 h"), no se suma al total de los tickets y vuelve a cero
  al cambiar el día. La meta sale de `DAILY_HOURS` en el `.env` (acepta decimales, p. ej. `7.5`;
  sin valor o inválido, 8 h) y se lee **al compilar**. **El corte no se abre solo ni es obligatorio:** el botón de nube de
  esa franja abre el **Corte del día** cuando tú quieras. El corte lista todos los tickets con
  tiempo y deja **subir uno por uno o todos a la vez**, con **horas y minutos** (los segundos no
  se tienen en cuenta). Al subir, el cronómetro **se reinicia** por defecto (casilla
  "Reiniciar el cronómetro al subir"; sin marcar conserva lo que sobre). Cada ticket se sube a
  Jira **por separado** y la suma de lo reportado (subido hoy + lo que subes ahora) se compara
  con la meta: **8 h = día completo**, **7 h = mínimo aceptable** (`DAILY_MIN_HOURS`) y más horas
  se permiten. Es solo una referencia: avisa ("Faltan", "Aceptable", "Día completo", "Sobran")
  pero no impone nada. **Día trabajado:** cada ticket del corte lleva un selector con
  **dos escenarios**: **Hoy** y **Anterior** (el día desde el que viene el tiempo del ticket
  o, si no se sabe, el día hábil anterior; puede ser de varios días atrás si no registraste
  desde la última vez que usaste la app). **A Jira solo viaja el tiempo**: la fecha es solo
  control interno de la app para llevar los cortes por día sin encimar nada. Solo lo subido
  para **hoy** cuenta en "subido hoy" y frente a la meta; así, subir hoy el tiempo de ayer no
  infla hoy. Si un
  cronómetro trae tiempo de un día anterior, la franja avisa ("N tickets con tiempo de días
  anteriores · ver corte") y el corte sugiere ese día. **Ese ticket no se puede iniciar**
  (el play queda desactivado y explica por qué) hasta que subas su tiempo anterior o lo limpies,
  para no mezclar días en un mismo cronómetro; solo afecta a ese ticket, pausar siempre se
  puede y un cronómetro en marcha no se detiene. El botón de corte de esa tarjeta abre el corte
  del día. En el resto de tickets, el corte por ticket sigue funcionando, lo anota como de hoy
  y también cuenta como subido hoy.
- Tema claro y oscuro según el sistema, con diseño de tarjetas redondeadas.

Las preferencias (transparencias y superposición) se guardan y se aplican al abrir la app.

## Requisitos

- Flutter 3.44 o superior (Dart `^3.12.0`).
- **Windows:** Visual Studio con la carga de trabajo "Desarrollo para el escritorio con C++".
- **macOS:** Xcode.
- **Linux:** las dependencias habituales de Flutter para GTK, más `libsecret-1-dev` (lo usa
  el almacén seguro de las credenciales de Jira).

## Comandos

```
flutter pub get
flutter run -d windows        # o macos / linux (hay que ejecutarlo en ese sistema)
powershell -File tool/flutter_env.ps1 run -d windows   # igual, pasando las credenciales de Jira de .env (si existe)
tool/flutter_env.sh run -d macos                       # lo mismo en macOS / Linux
flutter analyze               # lints (flutter_lints)
flutter test                  # todas las pruebas
flutter test test/domain/usecases_test.dart --plain-name "<nombre de la prueba>"   # una sola
flutter build windows         # o macos / linux
```

**Scripts de compilación (en la raíz):** compilan en modo release pasando las credenciales
de `.env` si existe, y muestran dónde queda la app.

```
.\build_windows.ps1               # Windows -> build\windows\x64\runner\Release\
.\build_windows.ps1 -Verify -Zip  # antes corre analyze + test; al final deja dist\my-jira-work-time-windows.zip
./build_macos.sh                  # macOS (solo en un Mac) -> build/macos/Build/Products/Release/*.app
./build_macos.sh --verify --zip   # lo mismo; deja dist/my-jira-work-time-macos.zip
DRY_RUN=1 ./build_macos.sh        # muestra los pasos sin ejecutarlos ($env:DRY_RUN='1' en Windows)
```

Se entrega la carpeta `Release` completa (el `.exe` solo no funciona). Si compilas con `.env`,
el Client Secret de Jira queda dentro del binario (se puede extraer): entrega ese build solo a
quien deba tenerlo. El `.app` de macOS sale sin firmar ni notarizar. En macOS, la primera vez:
`chmod +x build_macos.sh tool/flutter_env.sh`.

Si `flutter build windows --debug` falla con `LNK1168 ... no se puede abrir ... para
escritura`, es que la app sigue abierta y bloquea el `.exe`: ciérrala y vuelve a compilar.

## Dónde se guardan los datos

| Qué | Dónde |
| --- | --- |
| Proyectos, tiempos, preferencias y lo subido a Jira cada día | SQLite, archivo `gestion_time.db` en la carpeta de datos de la aplicación del sistema |
| Client ID, Client Secret y tokens de Jira (si se escriben en la app) | Almacén seguro del sistema operativo (nunca en SQLite) |
| Client ID y Secret de Jira (si vienen de `.env`) | Compilados dentro de la app; `.env` está en `.gitignore` y nunca se sube |

## Estructura del código

El código está en capas dentro de `lib/` (detalle y reglas en
[docs/architecture.md](docs/architecture.md); el kit visual en [docs/ui-kit.md](docs/ui-kit.md)):

```
lib/
├── main.dart                 arranque: arma las dependencias
├── config/
│   ├── env/                  meta diaria (DAILY_HOURS)
│   ├── router/               rutas de la app
│   └── theme/                tema, colores, tokens, límites e iconos
├── core/
│   ├── utils/                formato de duraciones
│   └── services/             ventana nativa (window_manager tras una interfaz)
├── domain/                   reglas de negocio: Dart puro, no depende de nada
│   ├── entities/             Project, JiraIssue, JiraSession…
│   ├── errors/               excepciones de Jira
│   ├── repositories/         contratos (ProjectsRepository)
│   └── usecases/             iniciar, pausar, limpiar, corte a Jira, meta y horas y minutos…
├── data/
│   ├── datasources/          SQLite, API y OAuth de Jira, almacén seguro
│   ├── models/               conversión entidad ⇄ SQLite/JSON
│   └── repository/           implementaciones de los contratos del dominio
├── presentation/
│   ├── viewModels/           estado de la interfaz (ChangeNotifier)
│   └── screens/              pantalla principal, vista simple y diálogos
└── widgets/                  UI kit: botones, campos, etiquetas, paneles, diálogos
test/                         sigue la estructura de lib/
tool/generate_icon.py         generador del icono de la app
tool/flutter_env.ps1 / .sh    ejecutan flutter pasando .env solo si existe
build_windows.ps1 / build_macos.sh   compilan en release (+ zip en dist/) usando los de tool/
.env.example                  plantilla de credenciales de Jira y meta diaria (copiar como .env)
windows/ macos/ linux/        runners nativos generados por Flutter (sin lógica propia)
```

Las **reglas de dependencia entre capas las hace cumplir una prueba**
(`test/architecture_test.dart`): por ejemplo, `domain` no puede importar Flutter ni SQLite,
y un componente de `widgets` no conoce la lógica de la app.

Los archivos `generated_plugin_registrant.*`, `GeneratedPluginRegistrant.swift` y
`macos/Flutter/ephemeral/` los regenera Flutter: no se editan a mano.

## Detalles que conviene saber

- **Diálogos:** usa `showFittedDialog` en lugar de `showDialog`; si no, un diálogo puede
  desbordarse en la ventana mínima. La excepción es el detalle del proyecto, que no agranda
  la ventana: se adapta al alto que hay.
- **Barra superior:** con los 4 botones el título dispone de poco ancho; si no cabe el texto
  "my-jira-work-time", queda solo el logo.
- **Pegado:** en Windows el portapapeles puede estar bloqueado un instante por otro
  programa (historial del portapapeles, gestores…) y el pegado estándar de Flutter hace un
  solo intento. `RobustPaste` reemplaza `Ctrl+V` por uno que reintenta hasta 6 veces y deja
  un mensaje en la consola (`Portapapeles: intento N/6 falló`) si no lo consigue. Ya está
  aplicado dentro de `showFittedDialog`. El menú de clic derecho sigue usando el pegado
  estándar.
- **Base de datos:** la versión 2 agregó `jira_key`, la 3 `jira_logged_ms` (total enviado a
  Jira), la 4 `jira_status` y `jira_status_category`, y la 5 `jira_estimate_s`,
  `jira_remaining_s` y `jira_spent_s` (seguimiento de tiempo, en segundos; `NULL` = Jira no lo
  informa). Las migraciones conservan los datos.
- **Preferencias guardadas:** `always_on_top`, `opacity` (vista completa) y `opacity_compact`
  (vista simple). Qué vista está abierta **no** se guarda.

## Icono de la app

El icono (reloj con check sobre azul) está generado, no dibujado a mano:

```
python -m pip install pillow
python tool/generate_icon.py
```

Reescribe `assets/icon/app_icon.png` (también se muestra en la barra superior), el `.ico`
de Windows y el `AppIcon.appiconset` de macOS. Linux no tiene icono configurado en su
runner. Tras regenerarlo hay que recompilar para que cambie el icono del `.exe`.

## Estado y pendientes

- **Verificado:** `flutter analyze` sin avisos y 326 pruebas pasando. Compilación de Windows
  (release) y comprobación en la **ventana real**, con clics reales del ratón: pin → vista
  simple (la ventana pasa de su tamaño a 280×130, justo el alto de su contenido) → botón de
  salida → vista completa; el deslizador cambia la transparencia real de la ventana (216/255
  al entrar con 85 %, 76/255 al arrastrarlo) y la vista completa conserva la suya (255).
  Credenciales de Jira: se compiló con y sin `.env` y se vieron en la ventana real los dos
  diálogos (sin formulario con `.env`, con formulario sin él); el ID y el Secret quedan dentro
  del binario solo cuando hay `.env`. El script `tool/flutter_env.ps1` se probó en todos los
  casos (con `.env`, incompleto, sin `.env`, otros comandos); `tool/flutter_env.sh` solo en
  Git Bash, no en macOS ni Linux reales.
- **Sin verificar:** macOS y Linux no se han compilado ni ejecutado. El inicio de sesión y
  el corte de Jira se probaron solo con Atlassian simulado; falta confirmarlos contra una
  cuenta real (en especial el formato de fecha y el comentario del worklog, y el mínimo de
  60 s). La vista simple no se ha probado con varios monitores ni con otras escalas de pantalla
  (el ajuste de tamaño está pensado para ellas, pero solo se midió en un equipo):
  `setResizable(false)` y `setMinimumSize` de `window_manager` pueden comportarse distinto en
  macOS y Linux.
- **Pendiente de arquitectura:** `JiraController` usa los datasources de Jira directamente, sin
  un `JiraRepository` (ver [docs/architecture.md](docs/architecture.md)).
- **Sin commit:** todos los cambios están en el árbol de trabajo.
