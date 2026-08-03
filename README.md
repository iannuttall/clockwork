<div align="center">

<img src="docs/assets/clockwork.svg" width="128" alt="Clockwork">

# Clockwork

**Run recurring commands on your Mac without learning launchd.**

[Download for macOS](https://github.com/iannuttall/clockwork/releases/latest) ·
[Report a problem](https://github.com/iannuttall/clockwork/issues) · [MIT licensed](LICENSE)

</div>

---

Clockwork lives in the menu bar. Give a task a name, add one or more commands, choose when it should run, and Clockwork turns it into a native `launchd` job.

## Quick start

[Download the latest DMG](https://github.com/iannuttall/clockwork/releases/latest), drag Clockwork to Applications, and open it. Clockwork supports Apple silicon and Intel Macs running macOS 14 or later.

Click the timer in the menu bar, choose **New Task**, and enter a command such as:

```sh
cd ~/dev/my-site && git pull --ff-only && pnpm build
```

Choose an interval, a daily time, or weekdays and a time. Clockwork registers the task with `launchd`, so it keeps running when the Clockwork app is closed.

## What it does

- Run commands on an interval, every day, or on selected weekdays.
- Add, edit, pause, delete, and run tasks from the menu bar.
- Keep tasks running through `launchd`, even when Clockwork is closed.
- Inspect exit codes, stdout, and stderr from the latest 50 runs.
- Report results that need attention without treating them as failures.
- Manage the same tasks through a CLI with JSON output.
- Explain common cron expressions with `clockwork explain-cron`.

## Everyday use

The menu shows every task, its next run, and the result of its latest run. Open a task to edit its commands, pause or run it immediately, and inspect stdout and stderr from its last 50 runs.

Tasks run through `/bin/zsh -lc`, the same login shell form you would use in Terminal. Put related commands on separate lines or join them with normal shell operators such as `&&`.

An orange badge means a task asked for attention. It is separate from failure: a task can finish successfully and still tell you that something needs a decision.

## Your data stays on your Mac

Task definitions, run history, stdout, and stderr stay in:

```text
~/Library/Application Support/Clockwork/
```

Launch agent files live in `~/Library/LaunchAgents`. Clockwork does not upload task data, logs, or usage information. Its only built-in network request is the Sparkle update check against this GitHub repository.

Clockwork does not need root, Full Disk Access, Accessibility, or a privileged helper. macOS may ask for notification permission when a task first requests attention.

## Updating from Scheduler

The first Clockwork build automatically moves data and jobs from the private pre-release app named Scheduler.

## Command line

Open Clockwork's Command Line settings and choose **Install CLI**. This installs `clockwork` to `~/.local/bin`.

```sh
clockwork list --json

clockwork add \
  --name "Update Codex" \
  --command "codex update" \
  --every 6h

clockwork update "Update Codex" --daily 09:00
clockwork disable "Update Codex"
clockwork run "Update Codex"
clockwork runs "Update Codex" --json
clockwork delete "Update Codex"
clockwork explain-cron '0 */6 * * *'
```

Tasks can be addressed by UUID or exact name. Commands that return task data accept `--json`.

The CLI uses the same files as the app, so changes appear in both places immediately. The app does not need to be running.

## Ask for attention

Every scheduled run receives a `CLOCKWORK_EVENT_FILE` environment variable. A command can report an actionable result without failing:

```sh
clockwork attention \
  --title "AMA inbox" \
  --message "36 questions are waiting" \
  --next-step "pnpm ian ama answer --remote"
```

Clockwork records the event with the run, adds an orange menu bar badge, and sends one native notification. Opening the task or marking it as seen acknowledges that run. A later attention event can alert again.

## Verify a downloaded build

Public builds are signed with Developer ID and notarized by Apple:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Clockwork.app
spctl --assess --type execute --verbose=4 /Applications/Clockwork.app
```

Each release includes a SHA-256 file beside the DMG. From your Downloads folder:

```sh
shasum -a 256 -c Clockwork-0.1.0.dmg.sha256
```

## Build from source

Clockwork is a native Swift 6.2 app built with SwiftPM. There is no Xcode project. It requires macOS 14 or newer.

```sh
make check
make dev
make package
```

`make dev` builds an ad-hoc signed app bundle, launches it, and verifies it stays running. `make package` builds an unsigned universal app for Apple silicon and Intel Macs.

The source is split into the portable `ClockworkCore` library, the native app, and the `clockworkcli` executable. See [Architecture](docs/architecture.md) and [Releasing](docs/releasing.md) for more detail.

Read [AGENTS.md](AGENTS.md) before changing the app. It records the product contracts and build traps that are easy to reintroduce.

## Common questions

### Does Clockwork need to stay open?

No. Enabled tasks are registered with the user's `launchd` session and keep running after the app closes. Clockwork is the editor and activity viewer, not a background runner.

### Is this a cron replacement?

For recurring commands on one Mac, yes. Clockwork uses native `launchd` schedules rather than installing or editing a crontab. It supports intervals, daily times, and selected weekdays. `clockwork explain-cron` helps translate common cron expressions, but Clockwork does not run arbitrary cron syntax.

### Can I pause a task without deleting it?

Yes. Disabling a task unregisters its launch agent but keeps the definition and run history. Enabling it registers the job again.

### Does it open at login?

Only if you enable **Open Clockwork at Login** in Settings. Scheduled tasks do not depend on that setting.

## Report bugs and request features

Open a [GitHub issue](https://github.com/iannuttall/clockwork/issues) with your macOS version, the schedule type, the latest exit code, and the relevant stdout or stderr. Remove tokens, passwords, and other private values from logs before posting them.

## License

Clockwork is available under the [MIT License](LICENSE). Third-party licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and included in the app bundle.
