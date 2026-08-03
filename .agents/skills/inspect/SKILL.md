---
name: inspect-clockwork
description: Read-only inspection of Clockwork identity, version, tasks, and release state.
---

# Inspect Clockwork

Use this skill to answer questions about the app without changing tasks, jobs, credentials, or releases.

## Read

- Read `app.config.json` for app identity, distribution, repository, and Sparkle configuration.
- Read `version.env` for the marketing version and build number.
- Run `swift run clockworkcli list --json` to inspect shared task state without launching the app.
- Read `appcast.xml` to inspect published update entries.
- Run `git status --short` and `git remote -v` to inspect repository readiness.

Never read or print signing, notary, or Sparkle private keys. Use the QA skill for builds and tests.
