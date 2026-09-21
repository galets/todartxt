import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/saf_bindings.dart';

void main() {
  test('writeToFd writes full content via fd number (no path reopen)', () async {
    final chunks = <List<int>>[];
    int fakeWrite(int fd, Pointer<Uint8> buf, int count) {
      expect(fd, 42);
      // Simulate partial writes of max 2 bytes (like pipes).
      final n = count > 2 ? 2 : count;
      chunks.add(buf.asTypedList(n).toList());
      return n;
    }

    await writeToFd(42, utf8.encode('hello owncloud'), rawWrite: fakeWrite);
    expect(utf8.decode(chunks.expand((c) => c).toList()), 'hello owncloud');
    // Must have looped over partial writes, not a single path-based write.
    expect(chunks.length, greaterThan(1));
  });

  test('writeToFd handles empty content (truncate commit)', () async {
    var called = false;
    await writeToFd(42, <int>[], rawWrite: (fd, buf, count) {
      called = true;
      return 0;
    });
    expect(called, isFalse);
  });

  test('writeToFd throws on write error instead of silent blank file', () async {
    expect(
      writeToFd(42, utf8.encode('x'), rawWrite: (_, __, ___) => -1),
      throwsA(isA<FileSystemException>()),
    );
  });
}
