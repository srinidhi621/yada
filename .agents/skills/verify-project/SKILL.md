---
name: verify-project
description: Build and verify Yada's native macOS MVP 1, including deterministic dictation lifecycle tests and explicit physical-Mac acceptance checks.
---

Run from the Yada repository. Read docs/mvp1-acceptance.md for the current evidence and pending physical tests.

1. Doctor: run `xcodebuild -version`, `xcode-select -p`, and `git status --short`. Require stable Xcode with macOS 26 SDK and macOS 26 on Apple Silicon. The project pins KeyboardShortcuts through Swift Package Manager. Never install an OS or change privacy settings.
2. Drive/prove: run `xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test`. This runs the real app's transcript assembler and session controller with a deterministic recognition boundary. Require zero failures. No microphone permission or private fixtures are needed.
3. Launch: `open .build/Build/Products/Debug/Yada.app`. Verify the setup window, menu-bar status, and disabled Copy before a final transcript. Do not capture user speech merely to inspect the UI.
4. Physical tests: follow docs/mvp1-acceptance.md. Let the user choose the shortcut, grant microphone access and explicitly request missing language assets. Keep Fn untouched. Use only non-sensitive utterances for observations; never save or report their text to a cloud assistant.
5. Observe timing in the app: capture readiness and stop-to-final milliseconds. Record cold/warm context and numeric measurements only. Never substitute vendor figures or label unrun checks passed.
6. Cleanup: Quit Yada, which releases process-owned audio/text. Clear only build artifacts under `.build` when needed; preserve source, specs, package lock and user work. No commit, push or privacy reset is part of verification.

MVP 1 proof map: revised/late transcript results and end-of-stream behavior → TranscriptTests; rapid toggles, cancellation, stale sessions and finalization → LifecycleTests; real audio, offline behavior, device changes, permissions, clipboard and Fn coexistence → manual acceptance matrix. Automated success does not prove physical audio success.

## Desktop and local-history extension

The user approved saving the last 50 finalized transcripts between launches. Real history is private at `~/Library/Application Support/Yada/RecentTranscripts.json`: do not open it or capture real transcript UI for verification. Tests inject isolated temporary history files and cover restart, deletion, corrupt data, failed writes, retention and cancellation. The panel test renders only a synthetic view to `.build/pill-preview.png`.

For native UI checks, use a separate Debug preview bundle so the user's current app and text remain untouched:

```sh
mkdir -p .build/UIPreview
ditto .build/Build/Products/Debug/Yada.app '.build/UIPreview/Yada Preview.app'
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.srinidhi621.yada.preview' '.build/UIPreview/Yada Preview.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Yada Preview' '.build/UIPreview/Yada Preview.app/Contents/Info.plist'
codesign --force --deep --sign - '.build/UIPreview/Yada Preview.app'
open -n '.build/UIPreview/Yada Preview.app' --args --ui-preview
```

Inspect only `com.srinidhi621.yada.preview` using native UI automation. Start/Stop/Cancel use a synthetic recognition session; the actual controller, views and panel run. History remains in memory and no global shortcut is registered. Check the Recent transcripts tab with synthetic entries. Quit the preview afterward. Do not treat generated levels/timings as microphone evidence. The real app requires the user's restart to preserve any unsaved current preview. Dock pinning and login startup are separate from the app's regular activation policy.

## Automatic insertion extension

Read docs/mvp2-acceptance.md for delivery evidence and pending application tests. Run the same test command above: insertion lifecycle tests cover finalization, cancellation, missing permission, uncertain writes and changed targets; FieldSnapshot tests cover Unicode and selection validity. These use synthetic boundaries and do not establish real-app compatibility.

Only the user grants Accessibility permission. Never alter privacy settings. Use synthetic destination documents for physical insertion checks; do not read private surrounding field text or transcript history. Check direct selected-text insertion, unchanged clipboard, destination focus, Undo, changed target fallback and no retry on uncertain outcomes. The preview driver does not exercise real Accessibility delivery. Record each tested app/version; never describe untested apps as verified.

Version 0.1.0 regression: verify key-down start/stop using the same shortcut handler, including setup refresh while recording. Outlook/Teams use a process-targeted paste with current-host-only clipboard text retained afterward; native insertion keeps the clipboard unchanged. Tests cover route selection, not physical delivery. Check both paths against docs/mvp2-acceptance.md without sending email/chat or reading private messages.
