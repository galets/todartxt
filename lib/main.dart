import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

import 'features/tasks/task_list_page.dart';
import 'features/tasks/task_repository.dart';

import 'features/tasks/saf_bindings.dart';
import 'features/tasks/saf_startup.dart';
import 'features/tasks/saf_todo_storage.dart';
import 'features/tasks/storage_location.dart';
import 'features/tasks/todo_storage.dart';

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
  bool _offline = false;

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
    final loadFuture = isSafUri(widget.todoPath)
        ? _loadSafWithMirror(widget.todoPath)
        : _repo.load(widget.todoPath);
    loadFuture.then((_) {
      if (mounted) setState(() => _loading = false);
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load ${widget.todoPath}: $e';
        });
      }
    });
  }

  /// SAF startup: retry transient provider init failures (ownCloud
  /// `KoinApplication has not been started` on cold start), then fall back
  /// to the local mirror per doc/STORAGE-access-framework.md §2.
  Future<void> _loadSafWithMirror(String uri) async {
    final storage = safStorageForUri(uri);
    final mirror = await fileMirror();
    final content = await loadStartupContent(storage, mirror);
    _offline = content.offline;
    await _repo.loadFromStorage(_StartupStorage(storage, content.text));
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
    if (_offline) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade100,
            padding: const EdgeInsets.all(8),
            child: const Text(
              'Offline — showing cached copy',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(child: TaskListPage(repository: _repo)),
        ],
      );
    }
    return TaskListPage(repository: _repo);
  }
}

/// File-backed mirror under `<app docs>/saf-mirror` (doc §2).
Future<MirrorCache> fileMirror() async {
  final dir = await getApplicationDocumentsDirectory();
  final mirrorDir = '${dir.path}/saf-mirror';
  await Directory(mirrorDir).create(recursive: true);
  return MirrorCache(
    mirrorDir,
    readFile: (p) => File(p).readAsString(),
    writeFile: (p, t) => File(p).writeAsString(t),
  );
}

/// Presents already-loaded startup text while keeping the live SAF
/// backend for subsequent writes/reloads.
class _StartupStorage implements TodoStorage {
  final TodoStorage _inner;
  final String _initial;
  _StartupStorage(this._inner, this._initial);

  @override
  String get displayName => _inner.displayName;

  @override
  Future<bool> isReachable() => _inner.isReachable();

  @override
  Future<DateTime?> lastModified() => _inner.lastModified();

  @override
  Future<String> readAll() async => _initial;

  @override
  Future<void> writeAll(String text) => _inner.writeAll(text);
}
