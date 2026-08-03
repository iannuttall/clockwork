# Changelog

All notable changes to Clockwork are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/) and
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.0 - 2026-08-03

- Added the final Clockwork logo and app icon.
- Renamed the app from its private Scheduler working title to Clockwork.
- Added a one-time migration for existing Scheduler tasks, run history, and launch agents, including closing the old app before migration.
- Added universal DMG packaging, checksum generation, release preflight checks, and end-to-end CI packaging verification.
- Added public repository documentation, an MIT license, third-party notices, and GitHub funding metadata.
- Added human-friendly interval, daily, and weekday schedules.
- Added task creation, editing, disabling, deletion, and manual runs.
- Added native launchd jobs so tasks run without keeping a window open.
- Added last-run status, exit codes, stdout, and stderr.
- Added an installable CLI with JSON output for humans and AI agents.
- Added common cron expression explanations.
- Added explicit task attention events with native macOS notifications and a menu-bar alert badge.
- Added actionable next steps and persistent acknowledgement for attention events.
- Switched the menu-bar icon to the timer SF Symbol.
- Rebuilt the menu-bar UI as an instant, non-blocking panel and moved task/log I/O off the main thread.
