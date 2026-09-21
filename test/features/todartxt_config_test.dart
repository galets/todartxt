import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';
import 'package:todart_txt/features/tasks/todartxt_config.dart';

void main() {
  group('todartxt.yaml linux default', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('todotxt_cfg_test');
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('creates missing config with previous default then uses it', () async {
      final cfg = '${tmp.path}/.config/todartxt.yaml';
      final fallback = '${tmp.path}/Tasks/todo.txt';
      final first = await ensureTodotxtConfig(
          fallbackTodoPath: fallback, configPath: cfg);
      expect(first, fallback);
      expect(File(cfg).existsSync(), isTrue);
      expect(await readTodoPathFromConfigFile(cfg), fallback);
      // Second call reuses existing file.
      final second = await ensureTodotxtConfig(
          fallbackTodoPath: fallback, configPath: cfg);
      expect(second, fallback);
    });

    test('uses configured todo_file when present', () async {
      final cfg = '${tmp.path}/c.yaml';
      File(cfg).writeAsStringSync('todo_file: /data/mine/todo.txt\n');
      expect(await readTodoPathFromConfigFile(cfg), '/data/mine/todo.txt');
      expect(
          await ensureTodotxtConfig(
              fallbackTodoPath: '/home/u/Tasks/todo.txt', configPath: cfg),
          '/data/mine/todo.txt');
    });

    test('defaultTodoPathAsync on linux uses config file', () async {
      final cfg = '${tmp.path}/todartxt.yaml';
      final path = await defaultTodoPathAsync(
          platform: 'linux', homeDir: '${tmp.path}/home', configPath: cfg);
      expect(path, '${tmp.path}/home/Tasks/todo.txt');
      expect(File(cfg).existsSync(), isTrue);
    });

    test('expands ~ and \$VAR in todo_file', () async {
      final cfg = '${tmp.path}/e.yaml';
      File(cfg).writeAsStringSync('todo_file: ~/Tasks/todo.txt\n');
      expect(
          await readTodoPathFromConfigFile(cfg,
              homeDir: '/home/u', env: const {}),
          '/home/u/Tasks/todo.txt');
      File(cfg).writeAsStringSync('todo_file: \$TODO_DIR/todo.txt\n');
      expect(
          await readTodoPathFromConfigFile(cfg,
              homeDir: '/home/u', env: const {'TODO_DIR': '/data/mine'}),
          '/data/mine/todo.txt');
      File(cfg).writeAsStringSync('todo_file: \${TODO_DIR}/todo.txt\n');
      expect(
          await readTodoPathFromConfigFile(cfg,
              homeDir: '/home/u', env: const {'TODO_DIR': '/data/mine'}),
          '/data/mine/todo.txt');
      expect(expandTodoPath('~/a', homeDir: '/h', env: const {}), '/h/a');
    });
    test('todotxtConfigPath respects XDG_CONFIG_HOME', () {
      expect(todotxtConfigPath(xdgConfigHome: '/x/cfg'), '/x/cfg/todartxt.yaml');
      expect(todotxtConfigPath(homeDir: '/home/u', xdgConfigHome: ''),
          '/home/u/.config/todartxt.yaml');
    });
  });
}
