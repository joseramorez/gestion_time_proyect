import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/models/project_filter_model.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/domain/usecases/filter_projects.dart';

void main() {
  const filter = FilterProjects();
  final now = DateTime(2026, 11, 12, 10);
  final yesterdayMs = DateTime(2026, 11, 11, 9).millisecondsSinceEpoch;

  // A: Jira, por hacer, 40 min · B: Jira, en curso, corriendo, 5 min · C: Jira, listo, 2 h ·
  // D: manual, 30 s · E: manual, 1 h, arrastra tiempo de ayer · F: Jira, sin estado, 10 s
  final a = const Project(
    id: 1,
    name: 'ABC-1 Pagos',
    jiraKey: 'ABC-1',
    jiraStatus: 'Por hacer',
    jiraStatusCategory: 'new',
    accumulatedMs: 40 * 60000,
  );
  final b = Project(
    id: 2,
    name: 'ABC-2 Inicio de sesión',
    description: 'Corregir ñandú',
    jiraKey: 'ABC-2',
    jiraStatus: 'En curso',
    jiraStatusCategory: 'indeterminate',
    startedAtMs: now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
  );
  final c = const Project(
    id: 3,
    name: 'ABC-3 Reportes',
    jiraKey: 'ABC-3',
    jiraStatus: 'Listo',
    jiraStatusCategory: 'done',
    accumulatedMs: 120 * 60000,
  );
  final d = const Project(id: 4, name: 'Reunión', accumulatedMs: 30000);
  final e = Project(
    id: 5,
    name: 'Tarea manual',
    accumulatedMs: 60 * 60000,
    timeSinceMs: yesterdayMs,
  );
  final f = const Project(id: 6, name: 'ABC-6 Nuevo', jiraKey: 'ABC-6', accumulatedMs: 10000);
  final all = [a, b, c, d, e, f];

  List<int> ids(ProjectFilter flt) =>
      filter(all, flt, now).map((p) => p.id!).toList();

  test('sin filtros devuelve todo en el orden original', () {
    expect(ids(ProjectFilter.initial), [1, 2, 3, 4, 5, 6]);
    expect(ProjectFilter.initial.isActive, isFalse);
  });

  group('búsqueda', () {
    test('sin mayúsculas ni tildes, en nombre, clave y descripción', () {
      expect(ids(const ProjectFilter(query: 'REUNION')), [4]);
      expect(ids(const ProjectFilter(query: 'sesion')), [2]);
      expect(ids(const ProjectFilter(query: 'abc-3')), [3]);
      expect(ids(const ProjectFilter(query: 'ÑANDU')), [2]); // en la descripción
      expect(ids(const ProjectFilter(query: 'no existe')), isEmpty);
    });

    test('los espacios de los extremos no cuentan', () {
      expect(ids(const ProjectFilter(query: '  pagos ')), [1]);
      expect(const ProjectFilter(query: '   ').isActive, isFalse);
    });
  });

  group('estado', () {
    test('uno o varios; las entradas sin estado se agrupan en «Sin estado»', () {
      expect(ids(const ProjectFilter(statuses: {'En curso'})), [2]);
      expect(ids(const ProjectFilter(statuses: {'Por hacer', 'Listo'})), [1, 3]);
      expect(ids(const ProjectFilter(statuses: {ProjectFilter.noStatus})), [4, 5, 6]);
    });

    test('las opciones salen por categoría y luego nombre, «Sin estado» al final', () {
      expect(filter.statusesIn(all).map((o) => o.status), [
        'Por hacer',
        'En curso',
        'Listo',
        ProjectFilter.noStatus,
      ]);
    });
  });

  test('origen: Jira o manuales', () {
    expect(ids(const ProjectFilter(origin: ProjectOrigin.jira)), [1, 2, 3, 6]);
    expect(ids(const ProjectFilter(origin: ProjectOrigin.manual)), [4, 5]);
  });

  test('actividad: en curso o pausados', () {
    expect(ids(const ProjectFilter(activity: ProjectActivity.running)), [2]);
    expect(ids(const ProjectFilter(activity: ProjectActivity.paused)), [1, 3, 4, 5, 6]);
  });

  test('con tiempo por subir: solo Jira y desde 1 minuto', () {
    // B (5 min corriendo), A (40) y C (2 h); D y F no llegan a 1 min; E es manual.
    expect(ids(const ProjectFilter(onlyUploadable: true)), [1, 2, 3]);
  });

  test('arrastran tiempo de otro día', () {
    expect(ids(const ProjectFilter(onlyCarried: true)), [5]);
  });

  group('ocultar finalizados (activado por defecto)', () {
    final closed = const Project(
      id: 7,
      name: 'ABC-7 Cerrado',
      jiraKey: 'ABC-7',
      jiraStatus: 'Listo',
      jiraStatusCategory: 'done',
    );
    final closedRunning = Project(
      id: 8,
      name: 'ABC-8 Cerrado corriendo',
      jiraKey: 'ABC-8',
      jiraStatus: 'Listo',
      jiraStatusCategory: 'done',
      startedAtMs: now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch,
    );
    List<int> visible(ProjectFilter flt) =>
        filter([a, c, closed, closedRunning], flt, now).map((p) => p.id!).toList();

    test('viene activado y no cuenta como filtro; mostrarlos sí cuenta', () {
      expect(ProjectFilter.initial.hideDone, isTrue);
      expect(ProjectFilter.initial.activeCount, 0);
      expect(const ProjectFilter(hideDone: false).activeCount, 1);
      expect(const ProjectFilter(hideDone: false).isActive, isTrue);
    });

    test('esconde los finalizados sin nada pendiente', () {
      expect(visible(ProjectFilter.initial), isNot(contains(7)));
      expect(visible(const ProjectFilter(hideDone: false)), contains(7));
    });

    test('pero no uno que corre ni uno con tiempo por subir', () {
      // c tiene 2 h sin enviar; closedRunning corre ahora; closed no tiene nada
      expect(visible(ProjectFilter.initial), [1, 3, 8]);
    });

    test('«Limpiar» (cleared) vuelve a ocultarlos y conserva el orden', () {
      final f = const ProjectFilter(hideDone: false, query: 'x', sort: ProjectSort.name).cleared;
      expect(f.hideDone, isTrue);
      expect(f.sort, ProjectSort.name);
      expect(f.isActive, isFalse);
    });
  });

  group('orden', () {
    test('por nombre sin tildes', () {
      expect(ids(const ProjectFilter(sort: ProjectSort.name)), [1, 2, 3, 6, 4, 5]);
    });

    test('más tiempo primero (incluye lo que corre ahora)', () {
      expect(ids(const ProjectFilter(sort: ProjectSort.mostTime)), [3, 5, 1, 2, 4, 6]);
    });

    test('por estado: por hacer, en curso, terminado y sin estado', () {
      expect(ids(const ProjectFilter(sort: ProjectSort.status)), [1, 2, 3, 6, 4, 5]);
    });

    test('en curso primero y el resto conserva su orden (estable)', () {
      expect(ids(const ProjectFilter(sort: ProjectSort.runningFirst)), [2, 1, 3, 4, 5, 6]);
    });
  });

  test('los filtros se combinan (todos deben cumplirse)', () {
    final flt = const ProjectFilter(
      origin: ProjectOrigin.jira,
      hideDone: false,
      onlyUploadable: true,
      sort: ProjectSort.mostTime,
    );
    expect(ids(flt), [3, 1, 2]);
    expect(flt.activeCount, 3); // origen, mostrar finalizados y por subir; el orden no cuenta
  });

  group('guardado', () {
    test('ida y vuelta; la búsqueda no se guarda', () {
      final original = const ProjectFilter(
        query: 'algo',
        statuses: {'Listo', 'En curso'},
        origin: ProjectOrigin.jira,
        activity: ProjectActivity.paused,
        onlyUploadable: true,
        onlyCarried: true,
        hideDone: true,
        sort: ProjectSort.mostTime,
      );
      final back = ProjectFilterModel.tryParse(ProjectFilterModel.toJson(original));
      expect(back.query, '');
      expect(back.statuses, {'Listo', 'En curso'});
      expect(back.origin, ProjectOrigin.jira);
      expect(back.activity, ProjectActivity.paused);
      expect(back.onlyUploadable && back.onlyCarried && back.hideDone, isTrue);
      expect(back.sort, ProjectSort.mostTime);
    });

    test('lo guardado antes de la v2 (ocultar finalizados apagado) toma el valor normal', () {
      final old = ProjectFilterModel.tryParse('{"hideDone":false,"sort":"name"}');
      expect(old.hideDone, isTrue);
      expect(old.sort, ProjectSort.name);
    });

    test('desde la v2 se respeta si el usuario los muestra', () {
      final shown = ProjectFilterModel.tryParse(
        ProjectFilterModel.toJson(const ProjectFilter(hideDone: false)),
      );
      expect(shown.hideDone, isFalse);
    });

    test('datos dañados o desconocidos no rompen: vuelven al filtro inicial', () {
      for (final raw in [null, '', 'no es json', '[1,2]', '{"sort":"inventado"}']) {
        final p = ProjectFilterModel.tryParse(raw);
        expect(p.activeCount, 0, reason: '$raw');
        expect(p.sort, ProjectSort.original, reason: '$raw');
      }
    });
  });
}
