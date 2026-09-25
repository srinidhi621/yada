# Yada build plan

Updated: September 25, 2026. This is the delivery checklist; `Yada_Product_and_Technical_Spec.md` contains the detailed product design. A built feature is not automatically a verified feature.

## Current position

Version 0.1.0 is on `main`. It includes local Apple transcription, a configurable start/stop shortcut (currently Control+Y), Dock and menu-bar access, a recording pill, local history of 50 transcripts, conservative cleanup and automatic insertion. Native accessible fields use selected-text writes; installed Outlook and Teams use a guarded paste path. No message is sent automatically.

On September 25, Xcode passed 62 synthetic app tests on macOS 26.7 and 10 Python tooling tests passed. The September 7 local DMG build passed Release compilation, ad-hoc signature and DMG verification. These checks do not prove real speech or cross-app delivery. The reported failure of Control+Y outside Yada has not been resolved or retested on the installed app. Apple Developer enrollment, Developer ID signing and notarization remain deferred.

**First shareable version:** core dictation only. Press Control+Y in another app, speak, press it again and get one correct insertion in the intended field. Meeting recording, speaker labels, notes and model rewriting are outside this release gate. The current DMG is a local test build, not a completed release.

## Immediate priority: prove the installed dictation flow

1. Install one local testing copy at `/Applications/Yada.app` from the verified DMG. Quit obsolete copies first. Use the installed copy, not a DerivedData build, for everyday testing.
2. Through macOS settings, repair only stale Yada Accessibility entries if needed. Preserve transcripts, meetings and preferences. The user grants microphone, Accessibility and missing speech assets.
3. Test shortcut registration and key delivery before insertion. If Control+Y still does nothing outside Yada, capture the app state and exact status message, then fix that path and rerun the physical test.
4. Run the TextEdit, Notes, Outlook and Teams insertion matrix in `docs/mvp2-acceptance.md`. Include stop by shortcut, selection replacement, Undo, cancellation and changed focus. Never send a test message.
5. Measure cold/warm readiness and finalization, offline speech, first/last-word retention, microphone denial/device changes and Fn coexistence using `docs/mvp1-acceptance.md`.
6. Quit/relaunch and replace the app at the same path. Confirm settings/history and record any permission repair needed across the ad-hoc update. Then test a fresh installation on a second supported Mac.

**Gate:** no silent shortcut failure, wrong-target insertion, duplicate delivery or unintended submission; acceptable speech quality and recovery in the tested apps; repeatable setup and upgrade behavior. An ad-hoc build may still need permission repair on upgrade. A completed release also needs Developer ID signing, notarization and second-Mac acceptance if distributed beyond a controlled tester.

## Ground rules

- Audio processing, future cleanup and meeting notes stay on this Mac. No hosted fallback, telemetry or cloud transcript uploads.
- Keep Control+Y start/stop and Wispr's Fn independent. Successful dictation needs no extra insertion button or per-app toggle.
- Preserve raw text. Unsupported or changed destinations receive a clear preview fallback. Never retry an uncertain insertion automatically.
- Password fields and known terminals remain excluded from automatic insertion. Never send Return or execute dictated text.
- Use existing Swift/AppKit/Speech code. Add dependencies only for a measured capability gap.
- Agents use synthetic test inputs, never private transcript history, messages or audio. The user grants macOS permissions and runs personal speech tests.
- Keep source, tests, plans and evidence in this repository. Keep build products and private data out of Git. Use personal GitHub identity and delegate Git writes.

## Ordered delivery steps

### 1. Finish reliable everyday dictation: in progress

1. Add actionable explanations for unsupported active fields. Distinguish a non-text focus, unavailable field text, missing cursor information and unsupported insertion instead of one generic failure.
2. Add deterministic coverage for those decisions; leave speech and successful insertion behavior unchanged.
3. Run the full native test suite and record evidence in the acceptance document.
4. Complete the physical keyboard and app matrix above when the user returns. Fix demonstrated failures in the existing delivery path before expanding compatibility.
5. Measure readiness and finalization on cold/warm runs, offline recognition, first/last-word retention, microphone denial/device changes, and Fn coexistence.

Files: `Yada/Delivery/ActiveFieldInsertion.swift`, controller/UI only where needed, `YadaTests/YadaTests.swift`, `docs/mvp2-acceptance.md`, verification skill.

Gate: no wrong-target insertion, duplicate retry, unintended submission or command execution; honest recovery for unsupported fields. Physical tests remain pending until actually run. Steps 1.1 and 1.2 are implemented; Step 1.3 passed its 29-test run and is included in the current 62-test suite. See `docs/mvp2-acceptance.md`. Steps 1.4 and 1.5 still require physical acceptance.

### 2. Conservative cleanup: implemented, default flow simplified

1. Create one deterministic transformation path after finalization and before delivery, with deterministic cleanup as the default and the original preserved.
2. Start with whitespace normalization. Add disfluency rules only with positive and counterexample fixtures; do not broadly delete words such as “like” or “well.”
3. Add an explicit user-managed terminology replacement list with exact phrase boundaries. Do not infer corrections by observing other apps.
4. Preserve raw and cleaned text, transformation version, and access to the original in history. Migrate existing history without data loss.
5. Use one automatic cleanup path without a text-mode picker and test it through the same dictation lifecycle.

Current implementation: automatic whitespace and exact terminology rules, preserved history variants, and settings validation. Mode selection has been removed from the everyday UI. No deterministic filler deletion is enabled. See docs/mvp3-acceptance.md.

Gate: numbers, negation, dates, names, quotations and code survive; already-clean text stays substantively unchanged; cancellation and insertion checks still pass. No model download is needed.

### 3. Local model formatting: implementation retained, UI deferred

1. Check the installed Apple on-device model's availability before adding inference; record any user setup needed.
2. Implement one bounded model pass for faithful prose, bullets or email draft. Give it no tools or external access.
3. Preserve raw/cleaned/formatted versions and start with review before insertion.
4. Handle timeout, unavailable model, refusal and invalid output by retaining faithful text with a clear reason.
5. Evaluate synthetic fixtures for meaning, numbers, commitments and instruction-like transcript text. Measure latency locally.

The formatter implementation and tests remain, but model-formatting controls are removed from the everyday UI. Apple Intelligence reported available; English (US) worked in the synthetic probe and English (India) was rejected by the framework locale check. The 18-case evaluation found five semantic failures and one attribution concern, with median latency 406 ms. Do not restore automatic model output or claim semantic acceptance. See `docs/formatting-evaluation-2026-09-07.md`.

Gate: no unapproved factual or commitment changes in the critical evaluation set. Compare one alternative local model only if Apple fails the measured workload; review disk, memory and download requirements first.

### 4. Local packaging and onboarding: package built, installation acceptance pending

Outcome: install one everyday copy at `/Applications/Yada.app` and complete the required macOS setup. A paid Apple account is not a prerequisite for this milestone.

Completed:

- `scripts/package-local.py` runs tests, builds Release with the production bundle identifier and ad-hoc signature, verifies the app, and creates a non-notarized DMG with an Applications shortcut and installation instructions.
- The local package passed 62 app tests, Release compilation, signature verification and `hdiutil verify`. Ten Python tooling tests passed. No artifact was uploaded.
- Setup uses real permission checks; language and shortcut preferences persist. A shared lock prevents two updated normal builds from running together. Shortcut registration failures are visible and retried on app activation.
- `docs/releases.md` covers installation, supported per-app Gatekeeper approval and user-managed repair of obsolete Yada Accessibility entries without deleting history or recordings.

Next:

1. Install the DMG and launch only `/Applications/Yada.app` for everyday testing.
2. Complete the Control-Y and insertion matrix, starting with TextEdit, then Notes, Outlook and Teams.
3. Test quit/relaunch, then replacement at the same path. Record retained settings/history and any permission repair required across ad-hoc updates.
4. After local acceptance, test installation on a second supported Mac before sharing more widely. Publishing a downloadable GitHub release requires separate authorization.

Paid enrollment, Developer ID signing and notarization are parked. The optional `scripts/release.py` workflow remains available for later. Ad-hoc packaging does not establish Apple-verified publisher identity or guarantee permission retention across rebuilds. Automatic updates and login startup remain outside this milestone.

Gate: physical installation and dictation checks pass with no wrong-target insertion, lost data or silent shortcut failure. Automated tests alone cannot close this gate.

### 5. Record and transcribe a meeting manually: first slice implemented, physical proof pending

1. Add a separate Record Meeting flow with explicit start, participant permission and visible pause/stop.
2. Capture microphone and selected system/process audio as separate timestamped tracks. Start with headphones and a controlled test call.
3. Save recoverable local chunks plus a manifest; target at most five seconds of crash loss and test that claim.
4. Transcribe after stop before attempting live meeting transcription. Mark missing intervals explicitly.
5. Support local transcript export and deletion of all session artifacts.

First-slice evidence: explicit Core Audio process capture plus microphone, separate bounded CAF chunks/manifest, Pause/Resume/Stop/quit recovery, local saved-session transcription and deletion/export controls are implemented. Full suite passes 58 tests using synthetic PCM/fake capture. File transcription stopped at the module readiness guard despite installed locales being listed; no downloads or live capture were performed. See `docs/meeting-capture-acceptance.md`.

Next: user-granted capture permissions and a short synthetic/consented routing test; resolve file-transcription readiness in the app; evaluate chunk-boundary speech and timestamp alignment. Do not claim the target five-second crash-loss window or long-call compatibility until measured.

Gate: consented 30 to 60 minute call, both tracks, disconnect recovery, tested crash-loss limit and accurate interval coverage. The user must grant system-audio permissions. No driver or cloud service is assumed necessary; verify native capture first.

### 6. Add speaker labels

1. Evaluate one local offline diarization implementation against a labelled synthetic/consented recording.
2. Keep stable anonymous speaker IDs across the meeting, including uncertain and overlapping segments.
3. Allow manual rename/merge without inventing identities from calendar attendees.
4. Export revised labels with timestamps.

Gate: measured speaker continuity and working correction controls. Check dependency license, model download and resource use before installation. No persistent voiceprint enrollment.

### 7. Produce grounded meeting notes

1. Generate local summary, decisions, actions, questions and risks from bounded transcript segments.
2. Link substantive items to source segment IDs. Leave owner/date empty when not stated.
3. Preserve contradictions and uncertainty; review against the original transcript.
4. Export Markdown first. Add search/storage indexing or PDF only when the existing workflow needs it.

Gate: every decision/action has valid evidence; no invented owners or deadlines; model failure preserves the transcript; deletion includes intermediate notes.

### 8. Suggest meeting recording

1. Check which calendars are available locally through EventKit before requesting access.
2. Combine a nearby calendar event with meeting-app/audio activity as a suggestion, never proof that a meeting started.
3. Offer Start, Dismiss and Snooze with manual start always available.
4. Measure false suggestions before considering any explicitly opted-in automatic recording.

Gate: no silent capture, no repeated nagging, no cloud calendar connector added merely to bypass local availability.

## Verification and Git sequence for each step

1. Inspect the working tree and relevant implementation; preserve unrelated work.
2. Implement the smallest complete change and meaningful regression fixtures.
3. Run `xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test`.
4. Perform synthetic native UI checks when UI behavior changes. Keep user-driven microphone/permission checks explicitly pending.
5. Review the final diff for leftovers, unnecessary layers and privacy/data-loss risks; update this checklist and the existing acceptance records.
6. Commit or push only when authorized for the specific changes. Verify the personal account, remote and push access first; checking push access alone does not publish these documentation changes.

Do not start all roadmap phases at once. Complete one slice and its observable behavior before moving to the next; continue independent synthetic work while physical acceptance awaits the user.
