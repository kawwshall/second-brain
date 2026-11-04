# Working on this ecosystem

The real personal vault is outside this repository. Work only with the clean starter vault and test fixtures here; never import personal notes, secrets, client material, session data, or local paths into commits.

Keep the short-list daily-log style. Clubs apply within a time horizon. Daily and annual Red goals are separate lists. Personal dates are YY·DDD; Obsidian uses YY·DDDD. Preserve required API/calendar formats.

Mahdi stays a small native Mac companion. Logs contain only timestamps and user-entered text. Preserve existing Markdown content when editing logs. No runtime network dependencies by default.

Validate relevant changes with `swift run --package-path tools/mahdi MahdiChecks` and `./scripts/build-mahdi.sh`. File-writing tests must use temporary vaults. Keep setup documentation consistent with the build script.
