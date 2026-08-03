---
name: qa-clockwork
description: Build, launch, and verify Clockwork after a code or packaging change.
---

# QA Clockwork

1. Run `make check` and fix every failure.
2. Run `make dev` to build, ad-hoc sign, launch, and perform the process check.
3. Confirm the exact bundle is running:

   ```sh
   pgrep -af "Clockwork.app/Contents/MacOS/Clockwork"
   ```

4. Cross-check app state through the bundled CLI:

   ```sh
   .build/package/Clockwork.app/Contents/MacOS/clockworkcli list --json
   ```

5. For packaging work, run `make package`, verify both executable architectures with `lipo -archs`, run `make dmg`, and verify the DMG with `hdiutil verify`.

Do not trigger Keychain prompts in tests. Report the exact app path, process, signatures, architectures, and behavior you verified.
