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

## September 7 installed-app follow-up

Progress is on `main` in `cb8c584`. The user reported that Control-Y does nothing outside Yada and that two Accessibility entries remain. The later audit found one running process and the correct saved Control-Y shortcut; the root cause of the global-key failure has not been confirmed.

The app now checks shortcut registration, shows failure feedback and retries registration on activation. Meeting/language busy gates bring Yada forward instead of silently ignoring a start request. The simplified app and local package passed 62 automated app tests. These changes have not yet demonstrated working global event delivery on the installed app.

Next session: install the local DMG at `/Applications/Yada.app`, complete user-managed permission repair if needed, then test Control-Y start/stop in TextEdit, Notes, Outlook email body and Teams compose. Follow with quit/relaunch and same-path upgrade checks. Do not mark compatibility or permission persistence passed until observed. No permission reset or deletion of user data was performed.

## September 25 core-dictation verification

Xcode's macOS 26.7 test report shows 62 synthetic app tests passed, including `testShortcutStartsThenStopsAndInsertsWithoutRecapturingTarget`. Ten Python packaging/tooling tests also passed. The command-line Xcode runner could not load CoreSimulator through the workspace sandbox; running the suite in the Xcode app completed successfully. No installed-app keyboard, microphone, Accessibility or cross-app check was performed in this run. The first shareable version is limited to core dictation; the physical acceptance matrix above remains the release gate.

## September 25 shortcut and duplicate-entry investigation

The current Mac had no `/Applications/Yada.app` when inspected. The enabled and disabled Accessibility rows in the user's screenshot therefore cannot both refer to a currently installed canonical app. Prior ad-hoc builds or different launch locations are the likely source, but the exact historic paths are unconfirmed. Yada cannot remove macOS Accessibility records itself.

Code inspection found a separate shortcut lifecycle defect: registration ran only from the main window's `onAppear`. It now runs from `applicationDidFinishLaunching`, including a menu-only launch. Release builds refuse to start outside `/Applications/Yada.app` and report a differently located running copy instead of silently activating it. Xcode passed 63 synthetic tests, including the canonical-installation check. Xcode built the Release app and its hardened-runtime signature and microphone entitlement were verified. The workspace denied copying it into `/Applications`, so there is still no live proof of Control-Y or insertion. Copy the single app from `.build/ready-to-install/` as described in `docs/releases.md`, repair only stale Yada Accessibility rows, and run the physical matrix above.
