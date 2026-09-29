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

## September 25 web-editor focus follow-up

The user confirmed physical Control-Y capture and dictation in Yada, Notes and TextEdit, but Outlook, Teams and Codex opened a preview. The screenshot's exact message was “No active text field was found,” which means Yada failed to obtain the focused Accessibility element before choosing an insertion method. This does not establish that paste itself failed.

The updated app checks the system-wide focused element when the application-level query fails, and verifies that the returned element belongs to the frontmost process. If focus is still unavailable, it asks an Electron-style application to expose its Accessibility tree and retries. Text fields that cannot accept a direct Accessibility write now use guarded paste regardless of app name; secure, disabled and non-text controls remain excluded, and the existing field snapshot and no-retry checks still apply. Xcode passed 63 synthetic tests after this change; the updated Release app's ad-hoc hardened-runtime signature and microphone entitlement were verified. Physical insertion in Outlook, Teams and Codex remains pending. A later failure message may identify another unsupported editor attribute without risking an unguarded paste.

## September 25 Outlook and Teams retest

The user installed the updated app; its code-signing hash matched the prepared build. Outlook and Teams still produced “No active text field was found” in user screenshots. Empty compose views exposed text-entry controls through macOS Accessibility, so the remaining failure is in Yada's focused-element lookup or ownership filter, before paste. No message was sent or pasted during inspection.

An experimental build trusted a focused control returned by the front application's own Accessibility tree, even if its editor runs in a helper process. It also checked the application's focused window before the system-wide fallback. Xcode passed all 63 synthetic tests, but the user reported that Control-Y started recording only while Yada was frontmost. The experimental build was withdrawn from the ready-to-install location, and the previous known-working build was restored there for a physical rollback check. The cause of the shortcut regression remains unverified. Outlook, Teams and Codex insertion remain unverified; no compatibility pass is claimed.

The installed `/Applications/Yada.app` code-signing hash then matched the restored build. The user tested the same Control-Y dictation flow in TextEdit, Notes, Outlook and Teams and reported successful speech capture and insertion into each text box. This is a physical smoke-test pass for those four apps on this Mac and installed build. It does not cover the full trial matrix above, Codex, relaunch, permission retention after an upgrade, or a second Mac. The experimental focus-lookup source change was removed; the restored installed build and source now use the same lookup. The earlier Outlook/Teams failure remains unexplained, so repeatability needs checking before release.

## Restart regression reported September 25

After quitting and reopening the installed app, the user reported that Control-Y no longer started recording in TextEdit, Notes, Outlook or Teams. Screenshots show Yada reporting missing Accessibility access despite one enabled and one disabled Yada row in macOS Settings. In this state, field capture stops before microphone startup, so the recording pill cannot appear. The user also selected English (India) and reported that Download language appeared to do nothing. No real language download or permission repair was performed by the coding agent.

Source changes align the asset check and download with the recording transcriber configuration, make a missing locale list no longer disable Download language, show checking/download errors, and provide a manual access recheck. These changes are not an installed-app fix until they build and the user tests the installed copy. At this point, the workspace sandbox had blocked Xcode's CoreSimulator framework, so the synthetic suite and a new package had not run for these changes. Physical acceptance must cover quit/relaunch, visible access status, Control-Y pill and insertion in an empty TextEdit document, then Notes, new and inline Outlook compose, and new and inline Teams compose. Confirm the language status and download progress or actionable error without exposing transcript contents.

The user then repaired the Yada Accessibility entries and reported that Control-Y again records, opens the pill and inserts in Notes and TextEdit. Both new and inline Outlook and Teams compose still returned “No active text field was found”; no paste was attempted in those cases. A source follow-up accepts focused elements exposed by the front application's own Accessibility tree or focused window, including helper-hosted editors, while retaining a strict process check for the system-wide fallback and rechecking the frontmost application before recording and before delivery. This is a hypothesis-driven fix, not a verified Microsoft compatibility result. Recheck the complete physical matrix with the new build before changing the installed app's status in this document.

## September 28 source and environment review

The focused-editor change still requires the front application at capture and delivery, compares the same focused Accessibility element and unchanged field snapshot, excludes Secure Input, protected fields and known terminals, and never retries an uncertain write. The paste path sends Command-V only. Accepting a helper-hosted editor does not prove that Outlook or Teams will deliver paste to it; event routing and field behavior require installed-app tests in both new and inline compose.

The English (India) language check, download and recording now use the same resolved locale and transcriber configuration. The setup UI allows an explicit readiness check, shows download status or an error, and allows a manual Accessibility recheck. Source review found no further defect in those paths. Asset availability, download progress, permission persistence, and shortcut registration after a real quit/relaunch remain unverified.

At the first September 28 check, `/usr/bin/git` and `xcodebuild -list -project Yada.xcodeproj` exited 69 because the Xcode license was not accepted. The user then reviewed and accepted the license in Xcode. Xcode 27.0 (27A266a) is selected on macOS 26.7 arm64, with the macOS 27.0 SDK; this differs from the `verify-project` skill's macOS 26 SDK requirement. Direct reads of CoreSimulator and DVTDownloads framework metadata succeeded. Xcode reported a CoreSimulator version mismatch and was denied writing `/Users/srinidhi.ramanujam/Library/Logs/CoreSimulator/CoreSimulator.com.apple.dt.xcodebuild.log`; neither prevented the macOS-destination test or Release build below.

The first native test attempt stopped before compilation because the shell could not resolve `github.com` to fetch KeyboardShortcuts. The pinned 3.0.1 checkout and repository under `.build/SourcePackages` matched `Package.resolved`. The user approved a narrow exception for `/Users/srinidhi.ramanujam/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading`; the offline rerun redirected XDG, Clang and SwiftPM module caches into `.build` and used the existing locked checkout without fetching packages.

Xcode 27's Swift 6.4 compiler rejected the `Mutex` capture in `AudioCapture.swift` at the converter callback. The workaround replaced it with a local Boolean guard: the first callback supplies the input buffer, and later calls return `.noDataNow`. The offline native macOS suite then passed 63 tests with zero failures. Result: `.build/offline-tests-post-audio-guard/Logs/Test/Test-Yada-2026.09.28_11-12-31-+0530.xcresult`.

The Release build succeeded at `.build/reviewable-release/Build/Products/Release/Yada.app` with production bundle ID `com.srinidhi621.yada`. `codesign --verify --deep --strict` passed; the ad-hoc signature includes the hardened runtime and audio-input entitlement. This app was not installed or launched, and these checks do not establish physical compatibility, permission persistence, English (India) asset download, or Control-Y after quit/relaunch. Outlook and Teams new and inline compose remain unverified with this build.
