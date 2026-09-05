# Automatic insertion acceptance — September 6, 2026

Implemented: global-shortcut capture of the active accessible field; finalization before delivery; direct selected-text write; unchanged app, field, selection and text checks; result verification; preview on unsupported or changed destinations; uncertain outcome without retry. No per-app toggle. Outlook and Teams use one process-targeted Command+V with current-host-only clipboard text; other supported fields use direct selected-text insertion. Secure fields and known terminal apps are excluded.

## Verified

`xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test` built the app and passed all 27 tests with zero failures. Result: `.build/Logs/Test/Test-Yada-2026.09.06_02-41-21-+0530.xcresult`.

Deterministic insertion tests cover finalization before delivery, cancellation before delivery, no retry or cancellation during an uncertain write, changed-target fallback, missing Accessibility permission without microphone startup, and Unicode/selection fingerprint checks. Existing lifecycle, history and audio tests also pass. These tests use synthetic recognition and insertion boundaries; they do not prove real Accessibility delivery.

The latest changes move shortcut handling to key-down, prioritize stop over setup checks, and add Microsoft-specific paste delivery without requiring writable selected text. Two regression tests cover the production shortcut start/stop handler and route selection for both Microsoft bundle IDs, native fields and unsupported apps. No new external dependency was added. The prior controller state-shadowing fix remains.

## Physical acceptance pending

The user reports successful insertion through the pill Stop button in TextEdit and most native apps on the prior build; Outlook/Teams and shortcut stop failed. The current fixes have not yet passed live insertion acceptance. The user must grant Yada Accessibility permission and restart the newly built app, preserving any current text first. Never read private history or use private documents as fixtures.

Start with a new TextEdit document, then test each desired compose surface in Codex, a browser, email and Teams. Run 20 trials per surface; record application version and outcome, not private text. Include empty fields, caret in the middle, selection replacement, Unicode, multiple lines, Undo, typing or moving the caret during recording, switching apps and switching back, cancellation, unchanged clipboard for native insertion, transcript retained on the clipboard for Microsoft insertion, and repeated shortcut presses during finalization. Confirm successful insertion keeps destination focus and never submits the message.

Check secure fields and known terminal apps remain in preview. Unsupported fields must explain the fallback; uncertain writes must not repeat. Required result: zero wrong-target insertions and no command execution. Compatibility, undo/formatting preservation and latency are unmeasured until these checks run. macOS cross-process reads and writes are not atomic.

The Microsoft path still requires readable text and a readable selection. It never retries after a direct-write failure or uncertain paste. Focus may change between a final check and the target processing a queued event; process targeting and preflight checks reduce but cannot eliminate that race. Do not describe automatic tests as proof of Microsoft editor compatibility.

## Local follow-on: actionable field failures

After the plan commit, the local build distinguishes absent/non-text focus, protected or disabled fields, unsupported direct insertion, unreadable field text, missing selection and invalid selection. These reasons appear in the existing preview message; no new permission, per-app setting, logging or retained destination text was added.

The full test command above passed 29 tests with zero failures. Result: `.build/Logs/Test/Test-Yada-2026.09.06_02-46-17-+0530.xcresult`. Added production-policy checks cover Microsoft paste rejection for protected/disabled/non-text fields, normal Microsoft paste eligibility, and distinct native unsupported-field behavior. Physical shortcut and Office acceptance remain pending.
