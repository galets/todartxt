import 'package:file_picker/file_picker.dart' show FilePickerPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:todo_txt/todo_txt.dart';
import 'storage_location.dart';
import 'task_repository.dart';

enum _FilterKind { all, uncategorized, due, context, project, priority, complete }

class _Filter {
  final _FilterKind kind;
  final String? value;
  const _Filter(this.kind, [this.value]);
  String get label => switch (kind) {
        _FilterKind.all => 'All',
        _FilterKind.uncategorized => 'Uncategorized',
        _FilterKind.due => 'Due',
        _FilterKind.context => '@$value',
        _FilterKind.project => '+$value',
        _FilterKind.priority => '($value)',
        _FilterKind.complete => 'Complete',
      };
}

enum _SortMode { none, priority, date, project }

/// Desktop-style Todo.txt client per doc/USER-interface.md.
/// Presentation-focused: filters/sorting/highlighting work in-memory.
class TaskListPage extends StatefulWidget {
  final TaskRepository repository;
  const TaskListPage({super.key, required this.repository});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage>
    with WidgetsBindingObserver {
  final _editController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  _Filter _filter = const _Filter(_FilterKind.all);
  _SortMode _sort = _SortMode.priority;
  int? _selected;
  String _search = '';
  bool _showDates = true;
  bool _showPriorities = true;
  bool _showTags = true;

  bool _searchExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Autosave on exit: persist any unsaved changes (fire-and-forget;
    // dispose cannot await).
    widget.repository.saveIfDirty().catchError((_) {});
    WidgetsBinding.instance.removeObserver(this);
    _editController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      widget.repository.saveIfDirty().catchError((_) {});
    }
  }

  Future<void> _pickStorageDir() async {
    final dir = await FilePickerPlatform.instance.getDirectoryPath(
      dialogTitle: 'Choose shared folder for todo.txt (e.g. Tasks)',
    );
    if (dir == null) return;
    final from = widget.repository.path;
    try {
      final to = await saveCustomDir(dir);
      if (from != null) await migrateTodoFile(from, to);
      await widget.repository.load(to);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('todo.txt location: $to')),
        );
      }
    } catch (_) {}
    _refresh();
  }

  Future<void> _showStorageInfo() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Storage location'),
        content: Text(widget.repository.path ?? '(not loaded)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _pickStorageDir();
            },
            child: const Text('Choose folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    try {
      await widget.repository.save();
    } catch (_) {}
    _refresh();
  }

  void _refresh() => setState(() {});

  // --- derived data ---
  Set<String> get _contexts => {for (final t in widget.repository.tasks) ...t.context};
  Set<String> get _projects => {for (final t in widget.repository.tasks) ...t.project};
  Set<String> get _priorities => {
        for (final t in widget.repository.tasks)
          if (t.priority != null) t.priority!
      };

  List<int> get _visibleIndices {
    final tasks = widget.repository.tasks;
    var idx = List<int>.generate(tasks.length, (i) => i);
    bool matches(int i) {
      final t = tasks[i];
      if (_search.isNotEmpty &&
          !t.toText().toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      return switch (_filter.kind) {
        _FilterKind.all => true,
        _FilterKind.uncategorized => t.context.isEmpty && t.project.isEmpty,
        _FilterKind.due => t.toText().contains(RegExp(r'due:\S+')),
        _FilterKind.context => t.context.contains(_filter.value),
        _FilterKind.project => t.project.contains(_filter.value),
        _FilterKind.priority => t.priority == _filter.value,
        _FilterKind.complete => t.completed,
      };
    }

    idx = idx.where(matches).toList();
    int completedLast(int a, int b) {
      final ac = tasks[a].completed ? 1 : 0;
      final bc = tasks[b].completed ? 1 : 0;
      return ac.compareTo(bc);
    }

    switch (_sort) {
      case _SortMode.priority:
        idx.sort((a, b) =>
            completedLast(a, b) != 0
                ? completedLast(a, b)
                : (tasks[a].priority ?? '')
                    .compareTo(tasks[b].priority ?? ''));
      case _SortMode.date:
        idx.sort((a, b) => completedLast(a, b) != 0
            ? completedLast(a, b)
            : _dateOf(tasks[a]).compareTo(_dateOf(tasks[b])));
      case _SortMode.project:
        idx.sort((a, b) => completedLast(a, b) != 0
            ? completedLast(a, b)
            : _projOf(tasks[a]).compareTo(_projOf(tasks[b])));
      case _SortMode.none:
        break;
    }
    return idx;
  }

  static String _dateOf(Task t) {
    final m = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(t.toText());
    return m?.group(0) ?? '9999-99-99';
  }

  static String _projOf(Task t) => t.project.isEmpty ? '~~~' : t.project.first;

  // --- actions (presentation-safe) ---
  Future<void> _showEditDialog({int? index}) async {
    final initial =
        index == null ? '' : widget.repository.tasks[index].toText();
    _editController.text = initial;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add task' : 'Edit task'),
        content: TextField(
          controller: _editController,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '(A) Call mom +Family @phone due:2023-05-01'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_editController.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    try {
      final task = Task.fromText(saved);
      if (index == null) {
        await widget.repository.add(task);
      } else {
        await widget.repository.update(index, task);
      }
    } catch (_) {}
    _refresh();
  }

  Future<void> _completeSelected() async {
    if (_selected == null) return;
    try {
      final t = widget.repository.tasks[_selected!];
      if (!t.completed) await widget.repository.toggleCompleted(_selected!);
    } catch (_) {}
    _refresh();
  }

  Future<void> _undo() async {
    try {
      await widget.repository.undo();
    } catch (_) {}
    _refresh();
  }

  Future<void> _deleteSelected() async {
    if (_selected == null) return;
    try {
      await widget.repository.removeAt(_selected!);
      _selected = null;
    } catch (_) {}
    _refresh();
  }

  // --- syntax highlighting ---
  InlineSpan _highlight(String raw, Task t) {
    if (t.completed) {
      return TextSpan(
        text: raw,
        style: TextStyle(
          color: Colors.grey.shade500,
          decoration: TextDecoration.lineThrough,
        ),
      );
    }
    final spans = <InlineSpan>[];
    final tokenRe = RegExp(
        r'^(\([A-Z]\)|x\b)|\d{4}-\d{2}-\d{2}|[+@]\S+|\S+:\S+|\(.\)|\S+|\s+');
    for (final m in tokenRe.allMatches(raw)) {
      final tok = m.group(0)!;
      TextStyle style =
          const TextStyle(color: Color(0xFF212121), fontSize: 13.5);
      if (RegExp(r'^\([A-Z]\)$').hasMatch(tok)) {
        if (!_showPriorities) continue;
        style = TextStyle(
          fontWeight: FontWeight.bold,
          color: tok == '(A)'
              ? Colors.red.shade700
              : tok == '(B)'
                  ? Colors.orange.shade800
                  : Colors.blue.shade700,
        );
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tok)) {
        if (!_showDates) continue;
        style = TextStyle(color: Colors.grey.shade600, fontSize: 12.5);
      } else if (tok.startsWith('+')) {
        if (!_showTags) continue;
        style = TextStyle(
            color: Colors.green.shade800, fontWeight: FontWeight.w600);
      } else if (tok.startsWith('@')) {
        if (!_showTags) continue;
        style =
            TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.w600);
      } else if (RegExp(r'^\S+:\S+$').hasMatch(tok)) {
        style = TextStyle(
            color: Colors.grey.shade700,
            fontStyle: FontStyle.italic,
            fontSize: 12.5);
      }
      if (tok.startsWith('+') || tok.startsWith('@')) {
        final tagValue = tok.substring(1);
        final isCtx = tok.startsWith('@');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => setState(() => _filter = _Filter(
                isCtx ? _FilterKind.context : _FilterKind.project,
                tagValue)),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isCtx
                    ? Colors.teal.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isCtx
                        ? Colors.teal.shade200
                        : Colors.green.shade200),
              ),
              child: Text(tok,
                  style: style.copyWith(fontSize: 12.5)),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: tok, style: style));
      }
    }
    return TextSpan(children: spans);
  }

  Widget _sidebarTile(String label, IconData icon, _Filter f, int count,
      {VoidCallback? onSelected}) {
    final active = _filter.kind == f.kind && _filter.value == f.value;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 16),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text('$count',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      selected: active,
      selectedTileColor: Colors.blue.shade50,
      onTap: () {
        setState(() {
          _filter = f;
          _selected = null;
        });
        onSelected?.call();
      },
    );
  }

  List<Widget> _sidebarChildren(List<Task> tasks, {VoidCallback? onSelected}) =>
      [
        _section('FILTERS'),
        _sidebarTile('All', Icons.inbox, const _Filter(_FilterKind.all),
            tasks.length,
            onSelected: onSelected),
        _sidebarTile(
            'Uncategorized',
            Icons.label_off,
            const _Filter(_FilterKind.uncategorized),
            tasks
                .where((t) => t.context.isEmpty && t.project.isEmpty)
                .length,
            onSelected: onSelected),
        _sidebarTile(
            'Due',
            Icons.event,
            const _Filter(_FilterKind.due),
            tasks
                .where((t) => t.toText().contains(RegExp(r'due:\S+')))
                .length,
            onSelected: onSelected),
        _section('CONTEXTS'),
        for (final c in _contexts.toList()..sort())
          _sidebarTile('@$c', Icons.alternate_email,
              _Filter(_FilterKind.context, c),
              tasks.where((t) => t.context.contains(c)).length,
              onSelected: onSelected),
        _section('PROJECTS'),
        for (final p in _projects.toList()..sort())
          _sidebarTile('+$p', Icons.folder,
              _Filter(_FilterKind.project, p),
              tasks.where((t) => t.project.contains(p)).length,
              onSelected: onSelected),
        _section('PRIORITIES'),
        for (final pr in _priorities.toList()..sort())
          _sidebarTile('($pr)', Icons.flag,
              _Filter(_FilterKind.priority, pr),
              tasks.where((t) => t.priority == pr).length,
              onSelected: onSelected),
        _section('STATUS'),
        _sidebarTile('Complete', Icons.check_circle,
            const _Filter(_FilterKind.complete),
            tasks.where((t) => t.completed).length,
            onSelected: onSelected),
      ];

  Widget _searchField() => SizedBox(
        width: 220,
        height: 34,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          decoration: InputDecoration(
            hintText: 'Search…',
            prefixIcon: const Icon(Icons.search, size: 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6)),
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
      );

  PopupMenuButton<String> _viewMenu() => PopupMenuButton<String>(
        icon: const Icon(Icons.visibility, size: 20),
        tooltip: 'View',
        offset: const Offset(0, 40),
        onSelected: (v) => setState(() {
          switch (v) {
            case 'dates':
              _showDates = !_showDates;
            case 'priorities':
              _showPriorities = !_showPriorities;
            case 'tags':
              _showTags = !_showTags;
          }
        }),
        itemBuilder: (ctx) => [
          CheckedPopupMenuItem(
              value: 'dates',
              checked: _showDates,
              child: const Text('Show dates')),
          CheckedPopupMenuItem(
              value: 'priorities',
              checked: _showPriorities,
              child: const Text('Show priorities')),
          CheckedPopupMenuItem(
              value: 'tags',
              checked: _showTags,
              child: const Text('Show tags')),
        ],
      );

  PopupMenuButton<_SortMode> _sortMenu() => PopupMenuButton<_SortMode>(
        icon: const Icon(Icons.sort, size: 20),
        tooltip: 'Sort',
        offset: const Offset(0, 40),
        onSelected: (v) => setState(() => _sort = v),
        itemBuilder: (ctx) => [
          for (final m in _SortMode.values)
            CheckedPopupMenuItem(
                value: m,
                checked: _sort == m,
                child: Text('Sort by ${m.name}')),
        ],
      );

  Widget _wideToolbar(List<int> visible, List<Task> tasks) => Container(
        color: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _searchField(),
            const SizedBox(width: 8),
            _tool(Icons.search, 'Search (/)', () => _searchFocus.requestFocus()),
            _tool(Icons.add, 'New task', () => _showEditDialog()),
            _tool(Icons.edit, 'Edit', _selected == null
                ? null
                : () => _showEditDialog(index: _selected)),
            _tool(Icons.delete, 'Delete', _selected == null ? null : _deleteSelected),
            _tool(Icons.check, 'Complete', _selected == null ? null : _completeSelected),
            _tool(Icons.undo, 'Undo', widget.repository.canUndo ? _undo : null),
            const VerticalDivider(),
            _tool(Icons.save, 'Save', _save),
            _tool(Icons.folder_open, 'Storage location', _showStorageInfo),
            const VerticalDivider(),
            _viewMenu(),
            _sortMenu(),
            const Spacer(),
            Text('${visible.length}/${tasks.length} tasks',
                style: TextStyle(
                    color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(width: 8),
          ],
        ),
      );

  Widget _narrowToolbar(
      BuildContext context, List<int> visible, List<Task> tasks) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _tool(Icons.menu, 'Filters', () => Scaffold.of(context).openDrawer()),
              _tool(Icons.search, 'Search (/)', () {
                setState(() => _searchExpanded = !_searchExpanded);
                if (_searchExpanded) _searchFocus.requestFocus();
              }),
              const Spacer(),
              Text('${visible.length}/${tasks.length}',
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 12)),
              _tool(Icons.add, 'New task', () => _showEditDialog()),
              _sortMenu(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'More actions',
                offset: const Offset(0, 40),
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await _showEditDialog(index: _selected);
                    case 'delete':
                      await _deleteSelected();
                    case 'complete':
                      await _completeSelected();
                    case 'undo':
                      await _undo();
                    case 'save':
                      await _save();
                    case 'storage':
                      await _showStorageInfo();
                    case 'dates':
                      setState(() => _showDates = !_showDates);
                    case 'priorities':
                      setState(() => _showPriorities = !_showPriorities);
                    case 'tags':
                      setState(() => _showTags = !_showTags);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                      value: 'edit',
                      enabled: _selected != null,
                      child: const Text('Edit')),
                  PopupMenuItem(
                      value: 'delete',
                      enabled: _selected != null,
                      child: const Text('Delete')),
                  PopupMenuItem(
                      value: 'complete',
                      enabled: _selected != null,
                      child: const Text('Complete')),
                  PopupMenuItem(
                      value: 'undo',
                      enabled: widget.repository.canUndo,
                      child: const Text('Undo')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      value: 'save', child: Text('Save')),
                  const PopupMenuItem(
                      value: 'storage', child: Text('Storage location…')),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(
                      value: 'dates',
                      checked: _showDates,
                      child: const Text('Show dates')),
                  CheckedPopupMenuItem(
                      value: 'priorities',
                      checked: _showPriorities,
                      child: const Text('Show priorities')),
                  CheckedPopupMenuItem(
                      value: 'tags',
                      checked: _showTags,
                      child: const Text('Show tags')),
                ],
              ),
            ],
          ),
          if (_searchExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
              child: SizedBox(
                height: 34,
                width: double.infinity,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.repository.tasks;
    final visible = _visibleIndices;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 700;
            final taskList = visible.isEmpty
                ? const Center(child: Text('No tasks match filter'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (c2, vi) {
                      final i = visible[vi];
                      final t = tasks[i];
                      final raw = t.toText();
                      final sel = _selected == i;
                      return GestureDetector(
                        onTap: () => setState(() => _selected = i),
                        onDoubleTap: () => _showEditDialog(index: i),
                        child: Container(
                          color: sel
                              ? Colors.blue.shade50
                              : (vi.isEven
                                  ? Colors.white
                                  : const Color(0xFFFAFAFA)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: t.completed,
                                visualDensity:
                                    VisualDensity.compact,
                                onChanged: (_) async {
                                  try {
                                    await widget.repository
                                        .toggleCompleted(i);
                                  } catch (_) {}
                                  _refresh();
                                },
                              ),
                              if (_showPriorities &&
                                  t.priority != null &&
                                  !t.completed)
                                Container(
                                  margin: const EdgeInsets.only(
                                      right: 6, top: 3),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: t.priority == 'A'
                                        ? Colors.red.shade600
                                        : t.priority == 'B'
                                            ? Colors.orange.shade600
                                            : Colors.blue.shade600,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(t.priority!,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.bold)),
                                ),
                              Expanded(
                                child: Opacity(
                                  opacity:
                                      t.completed ? 0.55 : 1.0,
                                  child: RichText(
                                      text: _highlight(raw, t)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
            return Scaffold(
              backgroundColor: const Color(0xFFF3F4F6),
              drawer: narrow
                  ? Drawer(
                      child: SafeArea(
                        child: ListView(
                          padding:
                              const EdgeInsets.symmetric(vertical: 4),
                          children: _sidebarChildren(tasks,
                              onSelected: () =>
                                  Navigator.of(ctx).pop()),
                        ),
                      ),
                    )
                  : null,
              body: Column(
                children: [
                  Builder(
                    builder: (scaffoldCtx) => narrow
                        ? _narrowToolbar(
                            scaffoldCtx, visible, tasks)
                        : _wideToolbar(visible, tasks),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: narrow
                        ? taskList
                        : Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 230,
                                color: Colors.white,
                                child: ListView(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  children:
                                      _sidebarChildren(tasks),
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: taskList),
                            ],
                          ),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _showEditDialog(),
                tooltip: 'Add task',
                child: const Icon(Icons.add),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Text(s,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.8)),
      );

  Widget _tool(IconData icon, String tip, VoidCallback? onPressed) =>
      IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact);
}
