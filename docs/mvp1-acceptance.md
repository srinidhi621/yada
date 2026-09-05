# MVP 1 acceptance

Status: MVP 1 implementation builds; 13 automated tests pass. Native setup and missing-assets error were checked. Physical speech acceptance remains pending.

## Environment

Checked September 6, 2026: Apple M5 Pro, 24 GiB RAM, arm64, macOS 26.6.2; Xcode 26.6 (17F113), Swift 6.3.3, macOS SDK 26.5. No OS, privacy settings, Wispr configuration or GitHub content changed.

## Automated evidence

Final automated run: **13 tests passed, 0 failures**, September 6, 2026 at 01:50 IST. Swift 6 compilation and ad-hoc signing succeeded as part of `xcodebuild test`.

Evidence: `.build/Logs/Test/Test-Yada-2026.09.06_01-50-42-+0530.xcresult`. Xcode emitted non-failing App Intents metadata and system `linkd.autoShortcut` diagnostics; the test runner completed successfully. Project and Info.plist validation passed. New-file whitespace review passed. The verification skill was inspected directly; its bundled validator could not run because the tool runtime lacks PyYAML. No extra app dependency was added for that optional validator.

The app has one native target and one test target. Tests cover:

- Repeated provisional revisions; final replacement; multiple finalized segments; exact preservation of emitted whitespace; late/duplicate results; empty and unfinalized audio.
- Preparing/recording/finalizing ordering; Copy unavailable before final drain; rapid toggles; cancellation during preparation and finalization; old-session callbacks; repeated sessions; recoverable failure.
- Actual AVAudioConverter with synthetic samples: resampling tail drains at EOF, integer/float level reading, and empty input termination.

Build/test commands are in README.md. Build outputs and test result bundles are local under `.build`; do not attach private speech to them.

## Physical-Mac checks

Use non-sensitive speech that may safely be observed locally. Do not send recordings or transcript contents to the coding agent. Record only pass/fail, counts and timings here.

| Check | Procedure and expected result | Status |
| --- | --- | --- |
| Setup UI and menu | Launch app. Setup/preview and menu-bar item appear. Copy disabled. Close and reopen through menu. | Setup/preview visually checked, Copy disabled; window close/menu reopening still pending |
| Language availability | Check selected locale; unsupported locale has an actionable message. | English (India) reported supported with missing assets; unsupported-locale behavior pending |
| Missing assets | Select a supported uninstalled language. Start fails clearly. Explicit Download shows progress/errors; recording never starts during download. | Missing-assets Start error verified in native UI before microphone permission; download progress/error still pending |
| Microphone denied | Deny the permission at first recording. No capture/Copy. Enable manually and retry successfully. Do not reset system permissions automatically. | Pending |
| Fn coexistence | Choose a separate chord. Fn still operates Wispr; Yada's chord toggles only Yada. Test from another application. | Pending |
| End-to-end speech | Speak a short non-sensitive utterance after Recording. Stop; finalized preview appears; explicit Copy pastes expected text locally. | Pending |
| First/last word | Repeat 10 short utterances with deliberate first/last words; compare locally for truncation and duplicates. | Pending |
| Silence | Record silence and stop. No invented committed text; empty final result leaves Copy disabled. Report ASR hallucination if observed. | Pending |
| Multi-minute speech | Speak for several minutes. No unexplained loss/duplication or queue-overflow silence. Stop remains responsive. | Pending |
| Cancel | Cancel during preparation, recording and finalization. No Copy or insertion; text clears; later recording works. | Pending |
| Input removal | Disconnect active input or change sample rate mid-recording. Visible recoverable error, no silent continuation with missing audio. | Pending |
| Sleep/wake | Sleep during recording; session is discarded with a visible reason. After waking, new session works. | Pending |
| Offline | Install assets first. User disables network, performs complete shortcut → speech → stop → copy flow, then restores network. | Pending |
| Online locality | Review dependency/provider path and observe network/system speech services during synthetic dictation. No content upload. Offline success alone does not establish this. | Source review passed; runtime pending |
| Clipboard | Copy only final text. Inspect current-host-only use in source; physical Universal Clipboard/clipboard manager behavior remains separate. | Source review passed; runtime pending |

## Timing

Cold capture readiness: **unmeasured**. Warm capture readiness: **unmeasured**. Stop-to-final latency: **unmeasured**.

Read metadata-only timings in the window. Measure one first-use session separately from at least 10 warm sessions under the usual workload, noting utterance duration and whether permissions/download affected preparation. Do not infer p95 from a single trial.

## Known limits

Apple's recognition quality, locale assets, microphone permissions and physical audio path need the above user-driven checks. A passing unit suite is not evidence that Wispr can be replaced. Automatic insertion and all later phases remain out of scope. No benchmark or privacy-network validation is claimed before it is run.

## Dock, recording pill and history extension

User evidence (September 6, 2026): the first setup steps, live transcription and copy/paste into other applications worked. The user selected Control+Y. This is user-reported evidence, not an agent-observed microphone benchmark. The user then explicitly approved transcript history saved between launches.

Implemented: regular Dock/Command–Tab presence while running; existing menu-bar controls plus recent entries; a draggable non-activating pill across spaces; actual input-level bars; locally saved last 50 finalized transcripts with review/copy/delete/clear. No audio persistence or automatic insertion.

Automated extension checks: history round-trip and exact text preservation; 0600 file permissions; 50-entry retention; empty/cancelled sessions excluded; recall does not duplicate saved entries; deletion and Clear persist; corrupt history is preserved until explicit Clear; failed writes are visible; panel cannot become key/main, is visible during recording, joins spaces and hides after cancellation. Synthetic panel render is under `.build/pill-preview.png`.

Native UI checked in an isolated Debug preview app with generated levels/text: Start → Recording, finalized preview, recent-entry selection/detail and deleting one synthetic entry. No real user transcript was read or copied during these checks. The isolated preview has in-memory history and does not establish disk persistence; the storage tests do.

Physical checks still pending for the updated real app: Command–Tab/Dock reopening, user pinning via Keep in Dock, exact menu-bar placement/visibility on this display, dragging the pill beside Wispr, full-screen/multiple-monitor behavior, and waveform responsiveness to real microphone input. Original offline, device removal and latency tests remain pending. Synthetic timings are not speech latency measurements.

Final extension run: **19 tests passed, 0 failures**, September 6, 2026 at 02:07 IST. Result bundle: `.build/Logs/Test/Test-Yada-2026.09.06_02-06-55-+0530.xcresult`. The synthetic pill render was visually inspected: rounded capsule, audio-level bars, Listening label, Stop and Cancel are legible and unclipped.

## Compact pill and application icon

September 6, 2026: pill reduced from 310 × 64 to 230 × 44 points, with unchanged right/bottom screen offsets and the same recording controls. User-supplied `yada.png` preserved; large logo isolated into a transparent master and packaged as a macOS AppIcon asset catalog. Verified generated `CFBundleIconFile = AppIcon` and bundled `Resources/AppIcon.icns`.

**19 tests passed, 0 failures** at 02:13 IST. Result bundle: `.build/Logs/Test/Test-Yada-2026.09.06_02-13-16-+0530.xcresult`. The smaller synthetic panel render was inspected with no text/control clipping. This pass did not capture real microphone audio or restart the user's running app; the new pill and Dock icon load after quitting and reopening Yada.
