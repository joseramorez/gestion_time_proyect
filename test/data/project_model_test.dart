import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/models/project_model.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';

void main() {
  test('una entrada completa de Jira sobrevive al viaje a SQLite y de vuelta', () {
    const original = Project(
      id: 7,
      name: 'ABC-1 Pagos',
      description: 'detalle',
      link: 'https://x.test/browse/ABC-1',
      accumulatedMs: 5000,
      startedAtMs: 123456,
      jiraKey: 'ABC-1',
      jiraLoggedMs: 3000,
      jiraStatus: 'En curso',
      jiraStatusCategory: 'indeterminate',
      jiraEstimateSeconds: 7200,
      jiraRemainingSeconds: 3600,
      jiraSpentSeconds: 3600,
    );
    final back = ProjectModel.fromMap(ProjectModel.toMap(original));

    expect(back.id, 7);
    expect(back.name, original.name);
    expect(back.description, original.description);
    expect(back.link, original.link);
    expect(back.accumulatedMs, 5000);
    expect(back.startedAtMs, 123456);
    expect(back.jiraKey, 'ABC-1');
    expect(back.jiraLoggedMs, 3000);
    expect(back.jiraStatus, 'En curso');
    expect(back.jiraStatusCategory, 'indeterminate');
    expect(back.jiraEstimateSeconds, 7200);
    expect(back.jiraRemainingSeconds, 3600);
    expect(back.jiraSpentSeconds, 3600);
  });

  test('lo que Jira no informa sigue siendo null (no se convierte en 0)', () {
    final back = ProjectModel.fromMap(
        ProjectModel.toMap(const Project(id: 1, name: 'manual')));
    expect(back.jiraEstimateSeconds, isNull);
    expect(back.jiraRemainingSeconds, isNull);
    expect(back.jiraSpentSeconds, isNull);
    expect(back.jiraKey, isNull);
    expect(back.startedAtMs, isNull);
  });

  test('sin id no se escribe la columna id (la asigna la base de datos)', () {
    expect(ProjectModel.toMap(const Project(name: 'nuevo')).containsKey('id'), isFalse);
  });

  test('filas antiguas con columnas vacías usan valores por defecto', () {
    final p = ProjectModel.fromMap({'id': 1, 'name': 'viejo'});
    expect(p.description, '');
    expect(p.link, '');
    expect(p.accumulatedMs, 0);
    expect(p.jiraLoggedMs, 0);
  });
}
