import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay_new/core/utils/quota_budget.dart';

void main() {
  group('QuotaBudget', () {
    test('allows exactly the daily limit, then refuses', () {
      final QuotaBudget budget = QuotaBudget(dailyLimit: 3);

      expect(budget.tryConsume(), isTrue);
      expect(budget.tryConsume(), isTrue);
      expect(budget.remaining, 1);
      expect(budget.tryConsume(), isTrue);

      expect(budget.isExhausted, isTrue);
      expect(budget.tryConsume(), isFalse);
      expect(
        budget.remaining,
        0,
        reason: 'a refused call must not go negative',
      );
    });

    test('refund restores a unit of budget', () {
      final QuotaBudget budget = QuotaBudget(dailyLimit: 1);

      expect(budget.tryConsume(), isTrue);
      expect(budget.tryConsume(), isFalse);

      budget.refund();
      expect(budget.tryConsume(), isTrue);
    });

    test('a zero limit is permanently exhausted rather than unlimited', () {
      final QuotaBudget budget = QuotaBudget(dailyLimit: 0);

      expect(budget.isExhausted, isTrue);
      expect(budget.tryConsume(), isFalse);
      expect(budget.fractionRemaining, 0);
    });

    test('reports tight once under 10% remains', () {
      final QuotaBudget budget = QuotaBudget(dailyLimit: 100);

      expect(budget.isTight, isFalse);
      for (int i = 0; i < 91; i++) {
        budget.tryConsume();
      }
      expect(budget.remaining, 9);
      expect(budget.isTight, isTrue);
    });

    test('resets when the UTC day rolls over', () {
      final DateTime dayOne = DateTime.utc(2026, 3, 1, 23, 59);
      final QuotaBudget budget = QuotaBudget(dailyLimit: 1, now: dayOne);

      expect(budget.tryConsume(), isTrue);
      expect(budget.isExhausted, isTrue);

      // One minute later is the next day, so the budget is restored.
      expect(budget.tryConsume(dayOne.add(const Duration(minutes: 2))), isTrue);
      expect(budget.remaining, 0);
    });

    test('does not reset within the same UTC day', () {
      final DateTime morning = DateTime.utc(2026, 3, 1, 6);
      final QuotaBudget budget = QuotaBudget(dailyLimit: 1, now: morning);

      expect(budget.tryConsume(), isTrue);
      expect(
        budget.tryConsume(morning.add(const Duration(hours: 12))),
        isFalse,
      );
    });

    test('survives a persistence round trip', () {
      final QuotaBudget budget = QuotaBudget(
        dailyLimit: 5,
        now: DateTime.utc(2026, 3, 1),
      );
      budget.tryConsume();
      budget.tryConsume();

      final QuotaBudget restored = QuotaBudget.fromJson(
        budget.toJson(),
        fallbackLimit: 5,
        now: DateTime.utc(2026, 3, 1),
      );

      expect(restored.remaining, 3);
      expect(restored.tryConsume(), isTrue);
      expect(restored.remaining, 2);
      expect(restored.tryConsume(), isTrue);
      expect(restored.tryConsume(), isTrue);
      expect(restored.isExhausted, isTrue);
      expect(restored.tryConsume(), isFalse);
    });

    test('falls back to a clean budget when the stored payload is corrupt', () {
      final QuotaBudget restored = QuotaBudget.fromJson(
        <String, Object>{'limit': 5, 'window': 'not-a-date', 'spent': 99},
        fallbackLimit: 5,
        now: DateTime.utc(2026, 3, 1),
      );

      expect(restored.remaining, 5);
    });
  });
}
