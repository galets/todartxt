import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_startup.dart';
import 'package:todart_txt/features/tasks/saf_todo_storage.dart';

MirrorCache memMirror([Map<String, String>? files]) {
  final f = files ?? <String, String>{};
  return MirrorCache(
    '/docs/saf-mirror',
    readFile: (p) async {
      final v = f[p];
      if (v == null) throw Exception('missing');
      return v;
    },
    writeFile: (p, t) async => f[p] = t,
  );
}

void main() {
  test('startup falls back to mirror when remote read fails', () async {
    final storage = SafTodoStorage(
      'content://org.owncloud.documents/document/987',
      readBytes: (_) async => throw Exception(
        'SafIoException: KoinApplication has not been started',
      ),
      writeBytes: (_, __) async {},
    );
    final mirror = memMirror();
    await mirror.refreshMirror(
      uri: storage.uri,
      text: 'cached task\n',
    );
    final result = await loadStartupContent(
      storage,
      mirror,
      delayForRetry: Duration.zero,
    );
    expect(result.text, 'cached task\n');
    expect(result.offline, isTrue);
  });

  test('startup retries transient Koin failure then succeeds', () async {
    var calls = 0;
    final storage = SafTodoStorage(
      'content://org.owncloud.documents/document/987',
      readBytes: (_) async {
        calls++;
        if (calls == 1) {
          throw Exception('KoinApplication has not been started');
        }
        return 'fresh\n';
      },
      writeBytes: (_, __) async {},
    );
    final result = await loadStartupContent(
      storage,
      memMirror(),
      delayForRetry: Duration.zero,
    );
    expect(result.text, 'fresh\n');
    expect(result.offline, isFalse);
    expect(calls, 2);
  });
}
