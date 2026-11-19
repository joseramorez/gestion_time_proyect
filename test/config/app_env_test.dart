import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/env/app_env.dart';

void main() {
  group('AppEnv.parseDailyGoal (DAILY_HOURS del .env)', () {
    Duration parse(String raw) => AppEnv.parseDailyGoal(raw);

    test('horas enteras', () {
      expect(parse('8'), const Duration(hours: 8));
      expect(parse('6'), const Duration(hours: 6));
    });

    test('con decimales, con punto o con coma', () {
      expect(parse('7.5'), const Duration(hours: 7, minutes: 30));
      expect(parse('7,5'), const Duration(hours: 7, minutes: 30));
      expect(parse('8.25'), const Duration(hours: 8, minutes: 15));
    });

    test('ignora los espacios alrededor', () {
      expect(parse('  6  '), const Duration(hours: 6));
    });

    test('el límite superior (24 h) es válido', () {
      expect(parse('24'), const Duration(hours: 24));
    });

    test('un valor vacío usa la meta por defecto (8 h)', () {
      expect(parse(''), AppEnv.defaultDailyGoal);
      expect(parse('   '), AppEnv.defaultDailyGoal);
      expect(AppEnv.defaultDailyGoal, const Duration(hours: 8));
    });

    test('un valor que no es un número usa la meta por defecto', () {
      for (final bad in ['abc', '8h', 'ocho', '8 horas', 'NaN', 'Infinity', '1e999']) {
        expect(parse(bad), AppEnv.defaultDailyGoal, reason: bad);
      }
    });

    test('cero, negativo o más de 24 horas usan la meta por defecto', () {
      for (final bad in ['0', '-3', '-0.5', '24.01', '25', '100']) {
        expect(parse(bad), AppEnv.defaultDailyGoal, reason: bad);
      }
    });

    test('un valor diminuto pero válido no da una meta de cero', () {
      expect(parse('0.001').inMinutes, greaterThanOrEqualTo(1));
    });

    test('sin .env (no se pasó DAILY_HOURS) la meta es de 8 h', () {
      // En `flutter test` normal no se define DAILY_HOURS.
      expect(AppEnv.dailyGoal, const Duration(hours: 8));
    });
  });

  group('AppEnv.parseDailyMinimum', () {
    const goal = Duration(hours: 8);
    test('por defecto 7 h', () {
      expect(AppEnv.parseDailyMinimum('', goal), const Duration(hours: 7));
      expect(AppEnv.parseDailyMinimum('abc', goal), const Duration(hours: 7));
      expect(AppEnv.parseDailyMinimum('0', goal), const Duration(hours: 7));
    });
    test('acepta decimales y coma', () {
      expect(AppEnv.parseDailyMinimum('6.5', goal), const Duration(minutes: 390));
      expect(AppEnv.parseDailyMinimum('6,5', goal), const Duration(minutes: 390));
    });
    test('nunca pasa de la meta', () {
      expect(AppEnv.parseDailyMinimum('9', goal), goal);
      expect(AppEnv.parseDailyMinimum('', const Duration(hours: 5)), const Duration(hours: 5));
    });
  });
}
