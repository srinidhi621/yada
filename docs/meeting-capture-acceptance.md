# Manual meeting recording: first slice

Implemented locally on 7 September 2026. This is an experimental capture and saved-file transcription slice, not verified meeting compatibility.

## Behavior

The Meetings tab lists Core Audio processes only when the user chooses Refresh. Select the process carrying the meeting audio, acknowledge participant permission, then Record meeting. AVAudioEngine captures the microphone and a private Core Audio process tap captures only the selected process. No screen frames, global audio fallback, driver, calendar monitoring, speaker identification or model summary is involved. Helper processes are listed separately; a browser process can contain multiple tabs.

Pause releases both capture paths. Resume creates new capture paths on the same timeline. Stop drains buffered packets, closes audio files and checkpoints the manifest. Quit waits for capture/transcription cleanup, including pause/resume transitions. Dictation controls and its shortcut are blocked while a meeting is active, including paused meetings. The menu exposes meeting Pause/Resume/Stop and transcription cancellation. Microphone and selected-app meters show activity; neither is proof of correct routing or intelligible speech. Check both tracks in a real test.

Meeting audio is saved under `Application Support/Yada/Meetings/<UUID>/`, or `Yada Development/Meetings/<UUID>/` for Debug. Ordinary dictation still saves no audio. Each capture callback copies into a bounded stream; overflow stops capture with an error. A serial writer saves separate CAF chunks and an atomic JSON manifest. Chunk length is at most five seconds for valid input; a discontinuity or format change closes a chunk early. File permissions are owner-only. Pause gaps remain in the host-clock timeline.

Saved meetings can be reopened, transcribed, revealed in Finder for local export, or permanently deleted after confirmation. Transcribe uses the selected Dictation speech language, installed Apple speech assets, and no network fallback. It processes chunks independently, retains originals on failure, and writes `transcript.md` only after completion. Exports include capture-source labels, chunk/result timestamps and explicit gap/overlap markers. They do not identify people. Words crossing chunk boundaries can be incomplete or repeated; this limitation must be evaluated before relying on long meetings.

## Evidence

- Full app suite: 58 tests passed, zero failures. Result: `.build/meeting-tests/Logs/Test/Test-Yada-2026.09.07_01-29-09-+0530.xcresult`.
- Meeting tests use generated PCM and fake capture, exercise separate readable CAF tracks, five-second chunk boundaries, manifest checkpoints, pause gaps, permission/consent/dictation exclusion, errors preserving audio, quit during resume, and Stop during pause-save. They also reject traversal in manifests before inference.
- A synthetic offscreen Meetings view rendered without invoking capture. This is a layout smoke test, not interactive native UI acceptance; native UI automation has been failing in this environment.
- `scripts/MeetingFileProbe.swift` exercised production chunk writing with a generated speech file. The speech service rejected transcription at its installed-module guard for en-US and en-IN. A read-only probe listed English locales as installed, but `AssetInventory.status` returned `supported`, not `installed`, for the transcription module. No readiness guard was bypassed and no assets were downloaded. Successful end-to-end speech transcription remains unverified.
- Final meeting-specific rerun: all nine tests passed after status/menu refinements, at `.build/meeting-tests/Logs/Test/Test-Yada-2026.09.07_01-29-56-+0530.xcresult`.
- Core Audio backend and transcription service typechecked against Swift 6 and the installed SDK. No live microphone or selected-process capture was invoked by the agent.

## Repeatable synthetic commands

From the repository:

```sh
xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/meeting-tests test
mkdir -p .build/meeting-file-probe
say -o .build/meeting-file-probe/synthetic.aiff 'The meeting is on Thursday. Do not send the draft.'
xcrun swiftc -swift-version 6 Yada/Meetings/MeetingArchive.swift Yada/Meetings/MeetingAudioSource.swift Yada/Meetings/MeetingTranscriber.swift scripts/MeetingFileProbe.swift -o .build/meeting-file-probe/probe
.build/meeting-file-probe/probe .build/meeting-file-probe .build/meeting-file-probe/synthetic.aiff en-IN
```

`say -o` creates a speech file without playback. Use only synthetic files with this probe. A nonzero result is an explicit failure, not a passed transcription test. Build/probe outputs remain under ignored `.build`; no real recordings belong in the repository.

## Physical acceptance, still pending

1. Open the new Debug build at `.build/meeting-tests/Build/Products/Debug/Yada.app`. Do not run two dictation apps with the same hotkey. Development has separate permissions/data; existing production data is preserved.
2. In Dictation setup, grant microphone access and check the desired speech language. If assets are missing, explicitly request the download. Verify a short ordinary dictation first. Do not change settings automatically during agent verification.
3. Use headphones. With participants' permission, start a short controlled call or synthetic audio playback. In Meetings, refresh processes, choose the audio-producing process and start. Grant macOS System Audio Recording access when requested. The app declares `NSAudioCaptureUsageDescription`.
4. Verify both activity meters, then Stop. Listen locally to both CAF tracks and confirm the intended application was captured, the microphone is separate, and no unrelated process was included. Record only numeric timings/route metadata in shared evidence. Never upload private recordings.
5. Test Pause/Resume, immediate Stop during pause-save, quit during resume, meeting-app exit, sleep, Bluetooth disconnection and permission denial. Confirm no continuing capture after Pause or Stop and no duplicate audio after resume. Muting Teams alone does not mute Yada's microphone.
6. Transcribe a short saved recording and compare it against the audio, especially five-second boundaries. Verify correct offsets, pause gaps, both track labels and cancellation/retry. Confirm missing-track feedback appears when one track has no packets.
7. Force-terminate a synthetic recording at several offsets and reopen it. Measure recoverable duration, inspect partial/unindexed CAF behavior and test low-disk failure. The five-second chunk policy is NOT a proven maximum crash-loss window: active files, queue backlog and filesystem durability still need measurement. Saved sessions with `recording`/`paused` manifests after a crash are treated as interrupted, not complete.
8. Only after short routing tests pass, run a consented 30 to 60 minute test. Measure alignment/drift, first/last-word loss, storage, memory and transcript completeness. Confirm local deletion removes the session audio/manifest/transcript and export is deliberate.

Core Audio route selection, hardware clocks, long recordings, disk exhaustion, hard-crash recovery and signed-build permissions remain open gates. Source: [Apple's process-tap capture guidance](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps).
