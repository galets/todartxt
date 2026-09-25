# To-Dart-TXT

this is a flutter UI for todotxt

Platforms:
  - Linux
  - Android

Use library: 
  https://github.com/galets/todo_txt

## Data source

App loads data using TodoTxt class from file supplied on command line. App edits data and saves it to the file used to load records

## Logging

App logs to stderr as `[level] message` (levels: `debug`, `info`,
`warning` (default), `error`). Level from `~/.config/todartxt.yaml`:

```yaml
log_level: debug
```

## UI

the UX contains a single window listing all
