# Scheduler

Run recurring commands on your Mac without learning crontab.

Scheduler lives in the menu bar. Add a name, one or more commands, an optional working folder, and pick when it should
run. Scheduler turns that into a native `launchd` job and keeps the latest 50 exit codes and command outputs where
you can actually find them.

## What it does

- Pick "every 6 hours", "daily at 09:00", or specific weekdays and a time.
- Add, edit, disable, delete, and run tasks from the app.
- Monitor running jobs and inspect the output from their latest 50 runs.
- Receive a native notification and menu-bar alert badge when a task explicitly reports that it needs attention.
- Keep jobs running through `launchd`, even when the Scheduler window is closed.
- Manage the same tasks through a CLI built for humans and agents.
- Translate common cron expressions with `scheduler explain-cron`.

Task definitions and logs stay in `~/Library/Application Support/Scheduler`. Scheduler does not send them anywhere.

## Use the CLI

Open Scheduler's Command Line pane and press **Install CLI**. This installs `scheduler` to `~/.local/bin`.

```sh
scheduler list --json

scheduler add \
  --name "Update Codex" \
  --command "codex update" \
  --every 6h

scheduler update "Update Codex" --daily 09:00
scheduler disable "Update Codex"
scheduler run "Update Codex"
scheduler attention --title "AMA inbox" --message "36 questions are waiting"
scheduler runs "Update Codex" --json
scheduler delete "Update Codex"

scheduler explain-cron '0 */6 * * *'
```

Tasks can be addressed by their UUID or exact name. Commands that return task data accept `--json`.

## Report something that needs attention

Every scheduled run receives a `SCHEDULER_EVENT_FILE` environment variable. A command can report an actionable result
without failing by running:

```sh
scheduler attention --title "AMA inbox" --message "36 questions are waiting"
```

Scheduler records the event with the run, marks it in orange, and sends one native notification for that run. Commands
can add `--next-step "pnpm ian ama answer --remote"` to show the exact follow-up in the run detail. Opening the task or
clicking **Mark as seen** acknowledges the current attention state; a later attention run alerts again. Commands that do
not report attention continue to finish quietly.

## Build it

Scheduler is a native SwiftPM app with no Xcode project. It requires macOS 14 or newer.

```sh
swift build
make check
make dev
make install
```

`make dev` builds an ad-hoc signed app bundle, launches it, and leaves it running in the menu bar.
`make install` builds the same local bundle, installs it to `/Applications/Scheduler.app`, installs the CLI, and
launches the installed copy. Scheduler registers itself as a login item by default; this can be changed in General.

## Ship it

The app uses the shared `macos` release pipeline for Developer ID signing, notarization, Sparkle updates, and a
Homebrew cask. Signing credentials belong in `~/.config/macos`, never in this repository.

## License

MIT. See [LICENSE](LICENSE).
