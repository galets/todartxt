import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_bindings.dart';

void main() {
  group('withProviderRetry', () {
    test('succeeds after transient Koin cold-start failures', () async {
      var calls = 0;
      final waits = <Duration>[];
      final result = await withProviderRetry(() async {
        calls++;
        if (calls < 3) {
          throw StateError('KoinApplication has not been started');
        }
        return 'ok';
      }, sleep: (d) async => waits.add(d));
      expect(result, 'ok');
      expect(calls, 3);
      expect(waits, [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1000),
      ]);
    });

    test('rethows last error when attempts exhausted', () async {
      var calls = 0;
      await expectLater(
        withProviderRetry(() async {
          calls++;
          throw StateError('KoinApplication has not been started');
        }, attempts: 2, sleep: (_) async {}),
        throwsStateError,
      );
      expect(calls, 2);
    });

    test('no delay when first attempt succeeds', () async {
      var waited = false;
      final result = await withProviderRetry(() async => 42,
          sleep: (_) async => waited = true);
      expect(result, 42);
      expect(waited, isFalse);
    });
  });
}
