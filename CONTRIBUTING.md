# Contributing

Open an issue with the behavior you want, or send a focused pull request. Keep Mahdi small and daily logs plain. Avoid adding task schemas, scoring systems, or required cloud accounts to the starter workflow.

For code changes, run:

```sh
swift run --package-path tools/mahdi MahdiChecks
./scripts/build-mahdi.sh
```

Manually check the floating widget and note editor on macOS when changing UI. Exercise file-writing changes against a temporary vault, never a real personal vault. Include tests for data-preservation or timer logic changes where practical.

Do not commit personal daily pages, client material, chat exports, credentials, vault indexes, app sessions, or local configuration. Copy the starter vault outside the repository before using it for real notes.
