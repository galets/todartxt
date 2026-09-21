import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_test_config.dart';

void main() {
  test('smoke config targets ownCloud provider', () {
    expect(kTestProviderPrefix, 'content://org.owncloud.documents/tree/');
    expect(kTestTreeUri.startsWith(kTestProviderPrefix), isTrue);
    expect(kTestFileName, 'todart-smoke.txt');
    expect(smokeTestContent(DateTime.utc(2026, 1, 1)), contains('2026'));
  });
}
