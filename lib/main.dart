import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:saf/saf.dart';

import 'package:gatefile_dart/gatefile_dart.dart' show AuthFailed;

import 'features/tasks/task_list_page.dart';
import 'features/tasks/task_repository.dart';

import 'features/tasks/saf_bindings.dart';
import 'features/tasks/storage_location.dart';
import 'features/tasks/todo_storage.dart';
import 'features/tasks/app_log.dart';
import 'features/tasks/todartxt_config.dart';

/// Entry point.
///
/// The todo.txt file path is supplied on the command line:
/// `flutter run -- path/to/todo.txt` (args[0]).
/// Without args: user-picked shared folder (SAF, persisted) when set,
/// else `~/Tasks/todo.txt` on Linux and app-private `<docs>/todo.txt`
/// on Android (pick a shared folder in the UI to get
/// `<storage root>/Tasks/todo.txt`, visible via `adb ls`).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final cfg = todotxtConfigPath();
  AppLog.init(await readLogLevelFromConfigFile(cfg));
  stderr.writeln('[info] config=$cfg');
  await ensureSharedStorageAccess();
  runApp(MyApp(todoPath: await effectiveTodoPath(args)));
}

class MyApp extends StatelessWidget {
  final String todoPath;
  final TaskRepository? repositoryOverride;

  const MyApp({super.key, this.todoPath = '', this.repositoryOverride});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Dart-TXT',
      home: _Home(todoPath: todoPath, repositoryOverride: repositoryOverride),
    );
  }
}

class _Home extends StatefulWidget {
  final String todoPath;
  final TaskRepository? repositoryOverride;
  const _Home({required this.todoPath, this.repositoryOverride});

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final TaskRepository _repo;
  String? _error;
  bool _loading = false;
  bool _showingSplash = true;
  StreamSubscription<void>? _gateSub;

  /// Resolve todo.txt backend: gatefile > SAF > plain file.
  Future<TodoStorage> _storageFor(String path) async {
    if (isGatefilePath(path)) {
      AppLog.info('backend=gatefile path=$path');
      final key = Platform.isAndroid
          ? await readGatefileApiKey() ?? ''
          : await readApiKeyFromConfigFile(todotxtConfigPath()) ?? '';
      if (key.isEmpty) {
        AppLog.err('gatefile: missing api_key');
        throw const AuthFailed();
      }
      return GatefileTodoStorage(gatefileEndpointUri(path), key);
    }
    if (isSafUri(path)) {
      AppLog.info('backend=saf path=$path');
      return safStorageForUri(path);
    }
    AppLog.info('backend=file path=$path');
    return FileTodoStorage(path);
  }

  /// Subscribe to SSE; on remote change reload + refresh UI.
  void _watchGatefile(TodoStorage s) {
    _gateSub?.cancel();
    if (s is! GatefileTodoStorage) {
      return;
    }
    _gateSub = s.updated.listen(
      (_) async {
        try {
          await _repo.reload();
          if (mounted) {
            setState(() {});
          }
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _gateSub?.cancel();
    (_repo.storage is GatefileTodoStorage)
        ? (_repo.storage as GatefileTodoStorage).close()
        : null;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _repo = widget.repositoryOverride ?? TaskRepository();
    if (widget.repositoryOverride != null || widget.todoPath.isEmpty) {
      // Widget tests inject a repository: skip timed splash.
      _showingSplash = false;
      if (widget.repositoryOverride != null) return;
    } else {
      // Show full-size square splash briefly so Android 12+ system splash
      // (which circle-crops icons) stays hidden via transparent animated icon.
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showingSplash = false);
      });
    }
    if (widget.todoPath.isEmpty) {
      _error = 'No todo.txt file supplied on command line.';
      return;
    }
    _loading = true;
    AppLog.info('loading todoPath=${widget.todoPath}');
    _storageFor(widget.todoPath).then((s) => _repo.loadFromStorage(s)).then((_) {
      AppLog.info('loaded ${_repo.tasks.length} tasks');
      _watchGatefile(_repo.storage!);
      if (mounted) setState(() => _loading = false);
    }).catchError((Object e) {
      AppLog.err('load failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load ${widget.todoPath}: $e';
        });
      }
    });
  }

  Future<void> _retryLoad() async {
    if (widget.todoPath.isEmpty) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _repo.loadFromStorage(await _storageFor(widget.todoPath));
      _watchGatefile(_repo.storage!);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load ${widget.todoPath}: $e';
        });
      }
    }
  }

  Future<void> _pickReplacementFile() async {
    try {
      final picked = await Saf().pickFile(
        mimeTypes: const ['text/plain', 'text/*', '*/*'],
        persistablePermission: true,
      );
      if (picked == null) return;
      await saveSafUri(picked.uri);
      if (!mounted) return;
      setState(() {
        _error = null;
        _loading = true;
      });
      await _repo.loadFromStorage(safStorageForUri(picked.uri));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load file: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showingSplash) {
      // Full-size square branding icon, no circular masking.
      return const Scaffold(
        body: Center(
          child: Image(
            image: AssetImage('assets/splash_image.png'),
            width: 240,
            height: 240,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('To-Dart-TXT')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryLoad,
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _pickReplacementFile,
                  child: const Text('Choose file'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image(
                image: AssetImage('assets/splash_image.png'),
                width: 240,
                height: 240,
                fit: BoxFit.contain,
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return TaskListPage(repository: _repo);
  }
}
