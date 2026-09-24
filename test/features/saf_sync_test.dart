import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_sync.dart';

void main() {
  test('any SAF uri is a sync uri', () {
    expect(isSafSyncUri('content://com.example.documents/tree/1'), isTrue);
    expect(
        isSafSyncUri('content://com.android.externalstorage.documents/x'),
        isTrue);
    expect(isSafSyncUri('/storage/emulated/0/Tasks/todo.txt'), isFalse);
    expect(isSafSyncUri(''), isFalse);
  });

  test('maybeSync calls requestSync for any SAF uri', () async {
    var calls = 0;
    final sync = SafSync(requestSync: () async => calls++);
    await sync.maybeSync('content://com.example.documents/tree/1');
    expect(calls, 1);
    await sync.maybeSync(
        'content://com.android.externalstorage.documents/x');
    expect(calls, 2);
    await sync.maybeSync('/storage/emulated/0/Tasks/todo.txt');
    expect(calls, 2);
  });

  test('maybeSync swallows errors', () async {
    final sync = SafSync(requestSync: () async => throw Exception('no'));
    await sync.maybeSync('content://com.example.documents/tree/1');
  });
}
