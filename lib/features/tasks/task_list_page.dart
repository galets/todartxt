import 'package:flutter/material.dart';
import 'package:todo_txt/todo_txt.dart';
import 'task_repository.dart';

/// Single-window page listing all tasks from the loaded file.
class TaskListPage extends StatefulWidget {
  final TaskRepository repository;
  const TaskListPage({super.key, required this.repository});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _showEditDialog({int? index}) async {
    final initial = index == null
        ? ''
        : widget.repository.tasks[index].toText();
    _controller.text = initial;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'Add task' : 'Edit task'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '(A) Call mom +Family @phone'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final task = Task.fromText(saved);
    if (index == null) {
      await widget.repository.add(task);
    } else {
      await widget.repository.update(index, task);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.repository.tasks;
    return Scaffold(
      appBar: AppBar(title: Text('todo.txt — ${widget.repository.path ?? ''}')),
      body: tasks.isEmpty
          ? const Center(child: Text('No tasks'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (ctx, i) {
                final t = tasks[i];
                final subtitle = [
                  if (t.priority != null) '(${t.priority})',
                  ...t.context.map((c) => '@$c'),
                  ...t.project.map((p) => '+$p'),
                ].join(' ');
                return ListTile(
                  leading: Checkbox(
                    value: t.completed,
                    onChanged: (_) async {
                      await widget.repository.toggleCompleted(i);
                      _refresh();
                    },
                  ),
                  title: Text(
                    t.title,
                    style: TextStyle(
                      decoration:
                          t.completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => _showEditDialog(index: i),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    onPressed: () async {
                      await widget.repository.removeAt(i);
                      _refresh();
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}
