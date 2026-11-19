# Arquitectura

La app está organizada en capas dentro de `lib/`. Cada capa tiene una responsabilidad y
solo puede depender de las que están "más adentro". Las dependencias entre capas **las
hace cumplir una prueba** (`test/architecture_test.dart`): si un archivo importa algo que
no le corresponde, la prueba falla y dice cuál.

## Estructura

```
lib/
├── main.dart                        arranque: arma las dependencias y abre la app
├── config/
│   ├── env/app_env.dart             meta diaria de horas (DAILY_HOURS, en compilación)
│   ├── router/app_router.dart       rutas de la app (AppRoutes + AppRouter)
│   └── theme/                       tema, colores, tokens, límites e iconos (ver ui-kit.md)
├── core/
│   ├── utils/duration_format.dart   formatDuration (HH:MM:SS) y formatWorkDuration (1 h 05 m)
│   └── services/window_service.dart ventana nativa (interfaz + implementación con window_manager) y
│                                    compactWindowHeight (el cálculo del alto de la vista simple)
├── domain/                          reglas de negocio: Dart puro, no depende de nada
│   ├── entities/                    Project, dayKey, JiraLive, JiraIssue, JiraSession…
│   ├── errors/jira_exceptions.dart  JiraAuthException, JiraUnauthorized, JiraApiException
│   ├── repositories/                contratos (interfaces): ProjectsRepository, WorkLogRepository
│   └── usecases/                    StartProject, PauseProject, ClearProject, ApplyJiraCut,
│                                    PrepareWorklog, FindStaleJiraKeys, EvaluateGoal,
│                                    SplitMinutes
├── data/                            cómo se guardan y se piden los datos
│   ├── datasources/                 AppDatabase (SQLite), JiraApi, JiraOAuth, SecretStore
│   ├── models/                      conversión entidad ⇄ SQLite/JSON (ProjectModel, JiraSessionModel…)
│   └── repository/                  ProjectsRepositoryImpl, WorkLogRepositoryImpl
├── presentation/
│   ├── viewModels/                  ProjectsController, JiraController, DailyController (ChangeNotifier)
│   └── screens/                     HomePage, CompactView, DayProgressBar y dialogs/
│                                    (formulario, detalle, Jira, corte por ticket, corte del día)
└── widgets/                         UI kit reutilizable (ver ui-kit.md)
    ├── buttons/  inputs/  chips/  layout/  dialogs/
    └── widgets.dart                 barril: un solo import para todo el kit
```

## Dirección de las dependencias

```
presentation ───► domain ◄─── data
     │               ▲          │
     └──► widgets ───┘          │   (widgets no depende de domain/usecases ni de data)
config / core: base común que usan todas; no dependen de presentation ni widgets
```

| Capa | Puede importar | No puede importar |
| --- | --- | --- |
| `domain` | solo `dart:` core y otros archivos de `domain` | Flutter, paquetes de terceros, `data`, `presentation`, `widgets`, `config`, `core`, `dart:io`, `dart:ui` |
| `data` | `domain`, `core`, paquetes (sqflite, http…) | `presentation`, `widgets`, Flutter `material`/`widgets` |
| `presentation/viewModels` | `domain`, `data` (ver "Desviaciones"), `core`, `flutter/foundation` | `widgets`, `presentation/screens`, `material.dart` |
| `presentation/screens` | todo lo anterior y `widgets`, `config` | — |
| `widgets` | `config`, `core`, Flutter | `presentation`, `data`, `domain/usecases` |
| `config` | Flutter | `presentation`, `data`, `domain` |
| `core` | `config`, Flutter, paquetes | `presentation`, `widgets` |

Además, **en `lib/` todos los imports internos son de paquete** (`package:gestion_time_proyect/...`),
nunca relativos: así se ve de un vistazo en qué capa vive cada archivo y mover uno no rompe a
sus vecinos.

## Cómo fluye una acción

Ejemplo: pulsar **play** en una tarjeta.

1. `ProjectTile` (screens) llama a `controller.start(project)`.
2. `ProjectsController` (viewModel) llama al caso de uso `StartProject` con la lista y el id.
3. `StartProject` (domain) decide *qué* cambia —pausar al que corría y arrancar este— y
   devuelve los proyectos modificados. No toca la base de datos ni conoce Flutter.
4. El controlador guarda cada cambio con `ProjectsRepository.update` (contrato del dominio).
5. `ProjectsRepositoryImpl` (data) delega en `AppDatabase`, que usa `ProjectModel` para
   convertir la entidad en una fila de SQLite.
6. El controlador actualiza su lista y llama a `notifyListeners()`; la pantalla se redibuja.

La **regla** (solo uno corre a la vez) vive en el dominio y se prueba sin base de datos; el
**almacenamiento** se puede cambiar sin tocar la regla; la **pantalla** solo pinta estado.

## Qué va en cada sitio (recetas)

| Quiero… | Lo pongo en… |
| --- | --- |
| Una regla de negocio nueva (p. ej. "no permitir dos cortes seguidos") | un caso de uso en `domain/usecases/`, con pruebas puras (sin base de datos) |
| Un dato nuevo en el proyecto | campo en `domain/entities/project.dart` + columna en `AppDatabase` (con migración) + `data/models/project_model.dart` |
| Cambiar cómo se guarda algo | `data/` (datasource o repositorio); el dominio no se entera |
| Una pantalla o diálogo | `presentation/screens/` (los diálogos en `dialogs/`) + su ruta en `config/router` si es una pantalla |
| Estado que ve la interfaz | un `ChangeNotifier` en `presentation/viewModels/` |
| Un componente visual reutilizable | `widgets/<tipo>/` y exportarlo en `widgets/widgets.dart` |
| Un color, tamaño o límite | `config/theme/` (nunca a mano en una pantalla) |
| Un formato (fechas, duraciones…) | `core/utils/` |

## Pruebas

Las carpetas de `test/` siguen a las de `lib/` para que sea fácil encontrar la prueba de cada
cosa:

| Prueba | Qué comprueba |
| --- | --- |
| `test/architecture_test.dart` | la dirección de las dependencias entre capas |
| `test/domain/usecases_test.dart`, `daily_usecases_test.dart` | las reglas de negocio, puras y con el reloj como parámetro (incluye la meta del día y las horas y minutos) |
| `test/data/project_model_test.dart` | el viaje entidad ⇄ SQLite |
| `test/presentation/` | view models con un repositorio en memoria (sin SQLite) y pantallas con un servicio de ventana falso |
| `test/core/ui_kit_test.dart` | componentes, límites y que nadie se salte el kit |
| `test/support/fakes.dart` | `FakeProjectsRepository`, `FakeWorkLogRepository` y `FakeWindowService` |
| el resto (`jira_*.dart`, `widget_test.dart`…) | integración con SQLite real y con Atlassian simulado |

Dos trampas de `flutter test` que conviene recordar:

- Un archivo de prueba que arranca el servidor local de OAuth **no debe contener ningún
  `testWidgets`**: el binding de widgets intercepta el HTTP real (incluso el de localhost) y
  la prueba se cuelga 30 s.
- Cada archivo que arranca ese servidor usa **su propio puerto** (`JiraOAuth(port: …)`):
  los archivos de prueba corren en paralelo y compartir el puerto hace que las peticiones
  lleguen al servidor de otro archivo.
- En una `testWidgets` que arranca un cronómetro, el `ProjectsController` crea un `Timer`
  periódico y Flutter exige que no quede ninguno al terminar el cuerpo de la prueba (antes
  de los `tearDown`): hay que liberar el controlador dentro del cuerpo.

## Desviaciones y pendientes

- **`JiraController` depende directamente de los datasources de Jira** (`JiraApi`,
  `JiraOAuth`, `SecretStore`) en lugar de un `JiraRepository` del dominio. Es la única
  dependencia de `presentation` hacia `data` que no pasa por un contrato. Consecuencia: sus
  pruebas montan los datasources con clientes HTTP simulados. Si crece, el siguiente paso es
  un `JiraRepository` en `domain/repositories/`.
- **`blocs/` y `providers/` no existen.** El estado se maneja con `ChangeNotifier` en
  `viewModels/`; no se usa ningún paquete de bloc ni provider, y una carpeta vacía ni siquiera
  se versiona en git. Si algún día se adopta uno, se crea entonces.
- **`domain/repositories/` y `domain/errors/`** no estaban en la estructura de referencia,
  pero la arquitectura los necesita: los contratos para no depender de SQLite, y los errores
  para que las capas de fuera puedan reconocerlos.
- **`AppDatabase` conoce las entidades** (devuelve `Project`, no filas): el mapeo vive en
  `data/models`, pero el datasource ya habla en términos del dominio.
