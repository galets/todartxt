import 'package:flutter/material.dart';
import 'package:todo_txt/todo_txt.dart';
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

class _TaskListPageState extends State<TaskListPage> {
  final _editController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  _Filter _filter = const _Filter(_FilterKind.all);
  _SortMode _sort = _SortMode.none;
  int? _selected;
  String _search = '';
  bool _showDates = true;
  bool _showPriorities = true;
  bool _showTags = true;

  @override
  void dispose() {
    _editController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
    switch (_sort) {
      case _SortMode.priority:
        idx.sort((a, b) => (tasks[a].priority ?? 'ZZ')
            .compareTo(tasks[b].priority ?? 'ZZ'));
      case _SortMode.date:
        idx.sort((a, b) => _dateOf(tasks[a]).compareTo(_dateOf(tasks[b])));
      case _SortMode.project:
        idx.sort((a, b) => _projOf(tasks[a]).compareTo(_projOf(tasks[b])));
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

  Widget _sidebarTile(String label, IconData icon, _Filter f, int count) {
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
      onTap: () => setState(() {
        _filter = f;
        _selected = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.repository.tasks;
    final visible = _visibleIndices;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          // A. Menu bar
          Container(
            color: const Color(0xFFE8EAED),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _menu('File', ['Open', 'Save', 'Export']),
                _menu('Actions',
                    ['Batch complete', 'Batch delete', 'Move tasks']),
                _menu('View', null, isView: true),
                _menu('Sorting', null, isSort: true),
                _menu('Help', ['Documentation']),
                const Spacer(),
                Text('${visible.length}/${tasks.length} tasks',
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12)),
                const SizedBox(width: 8),
              ],
            ),
          ),
          // B. Toolbar
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(
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
                ),
                const SizedBox(width: 8),
                _tool(Icons.search, 'Search (/)', () => _searchFocus.requestFocus()),
                _tool(Icons.add, 'New task', () => _showEditDialog()),
                _tool(Icons.edit, 'Edit', _selected == null
                    ? null
                    : () => _showEditDialog(index: _selected)),
                _tool(Icons.delete, 'Delete', _selected == null ? null : _deleteSelected),
                _tool(Icons.check, 'Complete', _selected == null ? null : _completeSelected),
                _tool(Icons.undo, 'Undo', () {}),
                const VerticalDivider(),
                _tool(Icons.save, 'Save', () => widget.repository.save().then((_) => _refresh())),
                _tool(Icons.print, 'Print', () {}),
                _tool(Icons.folder_open, 'Open', () {}),
              ],
            ),
          ),
          const Divider(height: 1),
          // C + D
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 230,
                  color: Colors.white,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      _section('FILTERS'),
                      _sidebarTile('All', Icons.inbox,
                          const _Filter(_FilterKind.all), tasks.length),
                      _sidebarTile(
                          'Uncategorized',
                          Icons.label_off,
                          const _Filter(_FilterKind.uncategorized),
                          tasks
                              .where((t) =>
                                  t.context.isEmpty && t.project.isEmpty)
                              .length),
                      _sidebarTile('Due', Icons.event,
                          const _Filter(_FilterKind.due),
                          tasks
                              .where((t) => t
                                  .toText()
                                  .contains(RegExp(r'due:\S+')))
                              .length),
                      _section('CONTEXTS'),
                      for (final c in _contexts.toList()..sort())
                        _sidebarTile('@$c', Icons.alternate_email,
                            _Filter(_FilterKind.context, c),
                            tasks.where((t) => t.context.contains(c)).length),
                      _section('PROJECTS'),
                      for (final p in _projects.toList()..sort())
                        _sidebarTile('+$p', Icons.folder,
                            _Filter(_FilterKind.project, p),
                            tasks.where((t) => t.project.contains(p)).length),
                      _section('PRIORITIES'),
                      for (final pr in _priorities.toList()..sort())
                        _sidebarTile('($pr)', Icons.flag,
                            _Filter(_FilterKind.priority, pr),
                            tasks.where((t) => t.priority == pr).length),
                      _section('STATUS'),
                      _sidebarTile('Complete', Icons.check_circle,
                          const _Filter(_FilterKind.complete),
                          tasks.where((t) => t.completed).length),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('No tasks match filter'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (ctx, vi) {
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
                        ),
                ),
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

  Widget _menu(String label, List<String>? items,
      {bool isView = false, bool isSort = false}) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: (v) {
        if (v.startsWith('sort:')) {
          setState(() => _sort = _SortMode.values
              .firstWhere((e) => e.name == v.substring(5)));
        } else if (v.startsWith('view:')) {
          setState(() {
            if (v == 'view:dates') _showDates = !_showDates;
            if (v == 'view:priorities') _showPriorities = !_showPriorities;
            if (v == 'view:tags') _showTags = !_showTags;
          });
        }
      },
      itemBuilder: (_) {
        if (isView) {
          return [
            CheckedPopupMenuItem(
                value: 'view:dates',
                checked: _showDates,
                child: const Text('Show dates')),
            CheckedPopupMenuItem(
                value: 'view:priorities',
                checked: _showPriorities,
                child: const Text('Show priorities')),
            CheckedPopupMenuItem(
                value: 'view:tags',
                checked: _showTags,
                child: const Text('Show tags')),
          ];
        }
        if (isSort) {
          return [
            for (final m in _SortMode.values)
              CheckedPopupMenuItem(
                  value: 'sort:${m.name}',
                  checked: _sort == m,
                  child: Text('Sort by ${m.name}')),
          ];
        }
        return [for (final it in items!) PopupMenuItem(value: it, child: Text(it))];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
