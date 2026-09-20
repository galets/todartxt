import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todart_txt/features/tasks/task_list_page.dart';
import 'package:todart_txt/features/tasks/task_repository.dart';
import 'package:todart_txt/main.dart';

/// Harness notes (all learned the hard way):
/// * `testWidgets` runs in a fake-async zone, so real `dart:io` work
///   (TaskRepository load/save) hangs unless wrapped in `tester.runAsync`.
/// * The page always contains a TextField (blinking cursor), so
///   `pumpAndSettle` never settles. [settle] does bounded pumps instead.
/// * UI-triggered saves only finish with interleaved fake/real clock
///   progress ([flushSaves]); a single `runAsync` delay is racy.
/// * Row content is RichText spans: assert with
///   `find.textContaining(..., findRichText: true)`.
/// * Row GestureDetector has onTap AND onDoubleTap, so selection needs
///   >300ms of pumped time (covered by [settle]).
/// * `widgetWithText(Container, ...)` also matches outer layout Containers
///   (e.g. the whole sidebar), so chips/badges are scoped to the task list.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('todart_widget');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  const richFixture = '(A) Call mom +Family @phone due:2023-05-01\n'
      '(B) Buy milk +Groceries @store\n'
      'x Done task +Family @phone\n'
      'plain task\n';

  /// Loads [content] into a temp file within the REAL async zone.
  Future<TaskRepository> loadedRepo(WidgetTester tester,
      [String? content]) async {
    late TaskRepository repo;
    await tester.runAsync(() async {
      final path = '${tmp.path}/todo.txt';
      File(path).writeAsStringSync(content ?? richFixture);
      repo = TaskRepository();
      await repo.load(path);
    });
    return repo;
  }

  /// Bounded replacement for pumpAndSettle (which hangs on the blinking
  /// search-field cursor). 500ms covers gestures, double-tap timeout,
  /// popup/dialog animations.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets file I/O triggered from UI callbacks (save on
  /// complete/delete/add/toggle) finish, then renders the refresh.
  Future<void> flushSaves(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpPage(WidgetTester tester, TaskRepository repo) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(home: TaskListPage(repository: repo)));
    await settle(tester);
  }

  Finder rowsContaining(String s) =>
      find.textContaining(s, findRichText: true);

  /// The task list is the second ListView (sidebar is first). Only valid
  /// with no popup menu / dialog open.
  Finder taskListView() => find.byType(ListView).at(1);
  Finder listText(String s) =>
      find.descendant(of: taskListView(), matching: find.text(s));

  testWidgets('shows error when no file supplied on command line',
      (tester) async {
    await tester.pumpWidget(const MyApp(todoPath: ''));
    await tester.pump();
    expect(find.textContaining('No todo.txt file supplied'), findsOneWidget);
  });

  testWidgets('baseline: counter and empty state', (tester) async {
    final repo = await loadedRepo(tester);
    await pumpPage(tester, repo);
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(find.text('4/4 tasks'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
    await settle(tester);
    expect(find.text('No tasks match filter'), findsOneWidget);
    expect(find.text('0/4 tasks'), findsOneWidget);
  });

  testWidgets('search narrows list and counter', (tester) async {
    final repo = await loadedRepo(
        tester, '(A) Call mom +Family @phone due:2023-05-01\nBuy milk\n');
    await pumpPage(tester, repo);
    expect(find.text('2/2 tasks'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'milk');
    await settle(tester);
    expect(rowsContaining('Buy milk'), findsOneWidget);
    expect(rowsContaining('Call mom'), findsNothing);
    expect(find.text('1/2 tasks'), findsOneWidget);
  });

  testWidgets('sidebar filters narrow list and mark selected', (tester) async {
    final repo = await loadedRepo(tester);
    await pumpPage(tester, repo);

    Future<void> tapTile(String label) async {
      await tester.tap(find.widgetWithText(ListTile, label).first);
      await settle(tester);
    }

    bool tileSelected(String label) {
      final tile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, label).first);
      return tile.selected == true;
    }

    await tapTile('@phone');
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(rowsContaining('Done task'), findsOneWidget);
    expect(rowsContaining('plain task'), findsNothing);
    expect(tileSelected('@phone'), isTrue);

    await tapTile('All');
    await tapTile('+Family');
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(rowsContaining('plain task'), findsNothing);
    expect(tileSelected('+Family'), isTrue);

    await tapTile('All');
    await tapTile('(A)');
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(rowsContaining('Buy milk'), findsNothing);
    expect(tileSelected('(A)'), isTrue);

    await tapTile('All');
    await tapTile('Complete');
    expect(rowsContaining('Done task'), findsOneWidget);
    expect(rowsContaining('Call mom'), findsNothing);
    expect(tileSelected('Complete'), isTrue);

    await tapTile('All');
    await tapTile('Due');
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(rowsContaining('plain task'), findsNothing);

    await tapTile('All');
    await tapTile('Uncategorized');
    expect(rowsContaining('plain task'), findsOneWidget);
    expect(rowsContaining('Call mom'), findsNothing);
  });

  testWidgets('tap tag chip in row applies same filter', (tester) async {
    final repo = await loadedRepo(tester);
    await pumpPage(tester, repo);
    await tester.tap(listText('@phone').first);
    await settle(tester);
    expect(rowsContaining('plain task'), findsNothing);
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(find.text('2/4 tasks'), findsOneWidget);
  });

  testWidgets('defaults to sorting by priority', (tester) async {
    final repo = await loadedRepo(
      tester,
      '(C) Lowest task\n'
      '(A) Highest task\n'
      '(B) Middle task\n',
    );
    await pumpPage(tester, repo);

    double top(String s) => tester.getTopLeft(rowsContaining(s).first).dy;

    expect(top('Highest task'), lessThan(top('Middle task')));
    expect(top('Middle task'), lessThan(top('Lowest task')));
  });

  testWidgets('sorting changes row order', (tester) async {
    final repo = await loadedRepo(
      tester,
      '(B) Buy milk +Zebra @store 2023-06-01\n'
      '(A) Call mom +Apple @phone 2023-05-01\n'
      'plain task\n',
    );
    await pumpPage(tester, repo);

    Future<void> selectSort(String label) async {
      await tester.tap(find.text('Sorting'));
      await settle(tester);
      await tester.tap(find.text(label), warnIfMissed: false);
      await settle(tester);
    }

    double top(String s) => tester.getTopLeft(rowsContaining(s).first).dy;

    await selectSort('Sort by priority');
    expect(top('Call mom'), lessThan(top('Buy milk')));

    await selectSort('Sort by date');
    expect(top('Call mom'), lessThan(top('Buy milk')));

    await selectSort('Sort by project');
    expect(top('Call mom'), lessThan(top('Buy milk')));
  });

  testWidgets('view toggles hide priorities/tags/dates', (tester) async {
    final repo = await loadedRepo(tester,
        '(A) Call mom +Family @phone 2023-05-01 due:2023-06-01\nplain task\n');
    await pumpPage(tester, repo);
    expect(listText('A'), findsOneWidget);
    expect(listText('@phone'), findsOneWidget);
    expect(rowsContaining('2023-05-01'), findsOneWidget);

    Future<void> toggleView(String label) async {
      await tester.tap(find.text('View'));
      await settle(tester);
      await tester.tap(find.text(label), warnIfMissed: false);
      await settle(tester);
    }

    await toggleView('Show priorities');
    expect(listText('A'), findsNothing);

    await toggleView('Show tags');
    expect(listText('@phone'), findsNothing);
    expect(listText('+Family'), findsNothing);

    await toggleView('Show dates');
    // Pure date token is skipped; the due:2023-06-01 key:value token stays.
    expect(rowsContaining('2023-05-01'), findsNothing);
    expect(rowsContaining('due:2023-06-01'), findsOneWidget);
  });

  testWidgets('selection enables toolbar; complete and delete mutate repo',
      (tester) async {
    final repo = await loadedRepo(
        tester, '(A) Call mom +Family @phone due:2023-05-01\nBuy milk\n');
    await pumpPage(tester, repo);

    IconButton tool(IconData icon) => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, icon).first);

    expect(tool(Icons.edit).onPressed, isNull);
    expect(tool(Icons.delete).onPressed, isNull);
    expect(tool(Icons.check).onPressed, isNull);

    await tester.tap(rowsContaining('Call mom').first);
    await settle(tester);
    expect(tool(Icons.edit).onPressed, isNotNull);
    expect(tool(Icons.delete).onPressed, isNotNull);
    expect(tool(Icons.check).onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await flushSaves(tester);
    expect(repo.tasks.first.completed, isTrue);
    expect(find.text('2/2 tasks'), findsOneWidget);

    await tester.tap(rowsContaining('Buy milk').first);
    await settle(tester);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete));
    await flushSaves(tester);
    expect(repo.tasks.length, 1);
    expect(find.text('1/1 tasks'), findsOneWidget);
  });

  testWidgets('FAB add task saves to repo', (tester) async {
    final repo = await loadedRepo(tester, 'Buy milk\n');
    await pumpPage(tester, repo);
    await tester.tap(find.byTooltip('Add task'));
    await settle(tester);
    expect(find.text('Add task'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'New shining task');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await flushSaves(tester);
    expect(repo.tasks.length, 2);
    expect(rowsContaining('New shining task'), findsOneWidget);
  });

  testWidgets('highlight: completed lineThrough + opacity; (A) red badge',
      (tester) async {
    final repo = await loadedRepo(tester);
    await pumpPage(tester, repo);

    // rowsContaining with findRichText matches the row RichText itself.
    final doneRt =
        tester.widget<RichText>(rowsContaining('Done task').first);
    final style = (doneRt.text as TextSpan).style;
    expect(style?.decoration, TextDecoration.lineThrough);
    final opacity = tester.widget<Opacity>(find.ancestor(
      of: rowsContaining('Done task').first,
      matching: find.byType(Opacity),
    ).first);
    expect(opacity.opacity, 0.55);

    final badge = find.ancestor(
      of: listText('A'),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          (w.decoration is BoxDecoration) &&
          (w.decoration as BoxDecoration).color == Colors.red.shade600),
    );
    expect(badge, findsOneWidget);
  });

  testWidgets('lists all tasks from loaded file', (tester) async {
    final repo = await loadedRepo(
        tester, '(A) Call mom +Family @phone\nBuy milk\n');
    await pumpPage(tester, repo);
    expect(rowsContaining('Call mom'), findsOneWidget);
    expect(rowsContaining('Buy milk'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('toggling checkbox saves to file', (tester) async {
    final repo = await loadedRepo(tester, 'Buy milk\n');
    await pumpPage(tester, repo);
    await tester.tap(find.byType(Checkbox));
    await flushSaves(tester);
    expect(repo.tasks.first.completed, isTrue);
    expect(File(repo.path!).readAsStringSync(), contains('x '));
  });
}
