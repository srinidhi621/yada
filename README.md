# Yada

A native macOS dictation app with a Dock icon, menu-bar controls, and a floating recording pill. Yada records microphone audio, transcribes with Apple's on-device SpeechTranscriber, and inserts finalized text into supported active text fields when started with the global shortcut.

## Build and run

Requires Apple Silicon, macOS 26 or newer, and stable Xcode 26 with the macOS SDK. No simulator, predictive completion model, Apple Developer subscription, API key, Python backend, or inference server is required. The local development build uses ad-hoc signing; distribution is out of scope.

From this directory:

```sh
xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build build
xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test
open .build/Build/Products/Debug/Yada.app
```

Alternatively, open `Yada.xcodeproj` in Xcode, choose the Yada scheme and My Mac, then Run. Xcode resolves the sole third-party dependency, KeyboardShortcuts 3.0.1, through Swift Package Manager. Keep the checked-in package lock. Initial dependency resolution needs internet access; recognition does not use a hosted fallback.

## First use

1. Choose a shortcut in the setup window. There is no default global binding. Use a chord separate from Wispr Flow's Fn; Yada rejects shortcuts with the Fn modifier.
2. Select a speech language and Check language. English (India) is the initial preference, subject to Apple's runtime support. Choose a supported alternative if unavailable.
3. If assets are absent, explicitly choose Download language. This contacts Apple for a one-time language download and displays progress. No audio is captured during download. Apple manages the system assets and their updates.
4. Choose Start recording, or use your shortcut. Grant the microphone permission when macOS asks. Wait for **Recording** before speaking; **Preparing** means capture is not ready.
5. Stop using the shortcut or Stop and finalize. Yada drains queued audio, flushes the format converter, finalizes recognition, and waits for final results.
6. When started with the shortcut in a supported external text field, finalized text is inserted automatically. Recording started inside Yada returns a preview. Unsupported or changed destinations also return a preview with Copy. Cancel discards the session; Clear discards current text. Closing the window leaves Yada running. Click its Dock icon or use Show Yada in the menu bar to reopen it. Quit ends the process.

Denied microphone access is recoverable in System Settings → Privacy & Security → Microphone. Yada does not change permissions for you. Shortcut registration needs no Accessibility permission. Automatic insertion does: on the first shortcut in another app, allow Yada in System Settings → Privacy & Security → Accessibility, then return to the text field and use Control+Y again. Yada does not start recording while that permission is missing. This app uses SpeechTranscriber, not the older potentially server-backed SFSpeechRecognizer path; no legacy Speech authorization request is made.

## Scope and privacy

- One app target and one test target, using SwiftUI/AppKit, AVAudioEngine and SpeechAnalyzer/SpeechTranscriber.
- No cloud inference, system audio, meeting features, database, audio files, telemetry, analytics or cloud fallback.
- Audio remains in memory only. At the user’s request, the 50 most recent nonempty finalized transcripts are saved as JSON under `~/Library/Application Support/Yada/RecentTranscripts.json` (directory permissions 0700; file permissions 0600). No audio is saved. Preferences keep the chosen shortcut and speech locale. Starting another session replaces the current preview; older finalized text remains in history until deleted or evicted by the 50-entry limit. Cancel discards the active session without saving it. Clear removes only the current preview. Recent transcripts → Delete/Clear history removes saved copies; copied text elsewhere and external backups are outside this control. Local files are not application-encrypted; external backup software may copy them.
- Copy uses `NSPasteboard`'s `currentHostOnly` option. Clipboard managers can still read or sync copied contents. Yada does not clear the clipboard when its preview clears.
- The preview is deliberately not directly selectable: copying goes through the explicit current-host-only Copy action after finalization.
- “Raw” means unchanged recognizer output. Apple ASR may normalize punctuation or omit disfluencies; it is not necessarily verbatim speech.
- A bounded 32-buffer handoff separates the microphone tap from conversion and recognition. Overflow or device reconfiguration fails visibly instead of silently dropping audio. This is a nonblocking producer handoff, not a hard-real-time or allocation-free guarantee.
- Duration measurements shown in the window are per-session capture readiness and stop-to-final milliseconds, measured with a monotonic clock. They include preparation/permission delay; no benchmark claims are implied.

## Verification

See [automatic insertion acceptance](docs/mvp2-acceptance.md) and [MVP 1 acceptance](docs/mvp1-acceptance.md) for actual results and pending physical tests. The repository verification skill is `.agents/skills/verify-project/SKILL.md`. Tests exercise the production transcript assembler, lifecycle controller and audio converter with synthetic inputs. They do not prove live microphone, offline speech, shortcut coexistence or clipboard behavior.

Keep personal evaluation audio and transcripts outside this repository and outside cloud coding-agent context. There is no diagnostic fixture recording mode in MVP 1.

## Sources and dependency

- [Apple SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [KeyboardShortcuts 3.0.1](https://github.com/sindresorhus/KeyboardShortcuts/tree/3.0.1), MIT. Its manifest has no additional package dependencies; license remains in the resolved source checkout.
- The installed macOS SDK's Speech and AppKit declarations were checked during implementation.

The first-build prompt describes the initial slice. See [the build plan](plan.md) for current delivery status. The product specification records the subsequent user-approved Dock/pill/local-history extension. The automatic insertion extension is implemented; live application compatibility remains to be verified. Later roadmap phases are not implemented.

## Dock, menu bar and recording pill

After upgrading, copy any current preview you need, quit the old Yada instance, and reopen the built app using the path above. Yada now appears in the Dock and Command–Tab while running. To retain its Dock shortcut after quitting, right-click its Dock icon and choose **Options → Keep in Dock**. No login/startup setting is changed.

The menu-bar waveform icon provides Show Yada, Start/Stop, Cancel, recent transcripts, and Quit. macOS decides its position; Yada does not move another app's menu-bar item. Control+Y remains your existing saved shortcut.

The compact 230 × 44 point recording pill appears near the bottom-right of the active screen, above the Dock. Drag its background to position it beside Wispr's indicator. It stays above ordinary windows and joins desktop spaces without taking keyboard focus. Preparing and Finalizing use a progress indicator; Listening shows bars driven by actual microphone levels, not a looping fake waveform. Stop finalizes; X cancels. It hides when the session ends. The dragged position lasts while Yada is running; it is not saved across app restarts.

Recent transcripts lists the last 50 finalized results from this version onward. Select an entry to inspect, copy, or delete it. The previous build's unsaved transcripts cannot be recovered. History save/read errors are visible and never silently overwrite an unreadable history file.

For UI verification only, a Debug build accepts `--ui-preview`: it uses generated audio levels, synthetic text, in-memory history, and no global shortcut registration or microphone. Use an isolated app bundle identifier when another Yada instance is running. Release builds ignore this argument. This driver does not prove live microphone quality or persistent history; tests cover the persistence path separately.

The Dock/Finder application icon is packaged in `Yada/Assets.xcassets/AppIcon.appiconset`, derived from the Primary App Icon in the user-provided `yada-v1.png` design sheet. The original sheet is preserved. The isolated transparent master is `docs/assets/yada-icon.png`; the asset catalog supplies all standard macOS icon sizes.

## Automatic insertion

Click the destination field, press Control+Y, speak after Listening appears, then press Control+Y to finalize and insert. No per-app setting or extra Insert button is needed. The destination keeps focus after verified insertion. TextEdit is the first manual test case, not an application restriction.

Yada uses macOS Accessibility to replace only the selected text of the captured field. The field must expose readable text and its selection. Native direct insertion also requires writable selected text; Outlook and Teams use the paste path without that requirement. Password fields, Secure Input and known terminal apps stay in preview. Other unsupported fields also fall back to preview. Switching apps, moving the cursor or editing text before delivery cancels automatic insertion. An uncertain write is never retried automatically; check the destination before copying.

Native-field insertion does not change the clipboard. The installed Outlook and Teams apps instead receive a single Command+V event sent to the captured process after the same destination checks. This path puts the transcript on the current-host-only clipboard and leaves it there, avoiding a timed restoration that could race a delayed paste. Clipboard managers may still read or sync it. No Return key is sent. Surrounding field text is read temporarily to compare fingerprints and verify the result; it is not logged or persisted. Only dictated transcripts enter Yada history. Cross-process checks and writes are not atomic, and editor undo/formatting behavior needs live testing.

Version 0.1.0 uses shortcut key-down for start/stop, and a running session can always receive Stop even during a language setup refresh. Automated checks pass; verify the physical shortcut and Microsoft compose fields after restarting the updated build.

## Cleanup and local formatting

Select **Text mode** in Setup before recording:

- **Raw** (default): recognizer output, unchanged. Your shortcut stops and inserts as before.
- **Clean**: collapse repeated horizontal spaces outside explicit quotes/code and apply your saved terminology. It keeps line breaks and indented/code text. It does not delete filler words or infer spoken corrections. Use **Terminology…** to add exact, case-sensitive phrase replacements. Replacements have word boundaries and do not cascade into each other. Clean uses no model.
- **Prose / Bullets / Email**: clean, then make one request to Apple's on-device `SystemLanguageModel`. Yada opens for review rather than inserting automatically. No cloud provider, tools, email sending or additional inference package is used.

For a model result, compare it with **Original and cleanup → Raw**. Choose **Use reviewed text**, click the destination field, and press Control+Y once to insert that reviewed text. That press does not start recording. **Cancel pending insertion** disarms it. You can instead copy formatted text or use the unformatted version. Uncertain insertion is never retried automatically.

This Mac reported `appleIntelligenceNotEnabled` during implementation. Enable Apple Intelligence yourself in System Settings → Apple Intelligence & Siri, allow its model setup to finish, then use **Check model** in Yada. Raw and Clean work without it. Availability is checked again at each format request. Unsupported languages, refusal, context errors, empty output, cancellation or the 30-second timeout retain the original text. Input over 3,000 UTF-8 bytes is rejected rather than truncated. The app does not change Apple Intelligence settings or download a separate model.

Model output can change meaning even when numbers match. A changed-number warning is only a review aid; it is not an accuracy guarantee. Live model quality is not yet verified on this Mac. Keep code, numbers, names, negations and commitments under review. The model is instructed to treat dictated instructions as text, with no tools or execution authority.

History retains raw, cleaned and formatted versions when present, plus cleanup version/style. Existing history entries load as raw-only records without a destructive migration. **Recent transcripts** lets you view and copy each available version. Terminology and mode are stored locally in `~/Library/Application Support/Yada/CleanupSettings.json`; they are not learned from other applications. Settings errors are visible and corrupt files are not silently overwritten.

See [cleanup and formatting acceptance](docs/mvp3-acceptance.md) for measured results and remaining tests. Apple's [Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) identifies this model as the on-device model powering Apple Intelligence.
