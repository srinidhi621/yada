# Yada build plan

Updated: September 6, 2026. This is the delivery checklist; `Yada_Product_and_Technical_Spec.md` contains the detailed product design. Update this file as work passes its checks. A built feature is not automatically a verified feature.

## Current position

Version 0.1.0 is on `main` (initial release commit `a75d04d`). It includes local Apple transcription, a configurable start/stop shortcut (currently Control+Y), Dock and menu-bar access, a small recording pill, local history of 50 transcripts, and automatic insertion. Native accessible fields use direct selected-text writes. Installed Outlook and Teams use a guarded paste path that leaves the transcript on the local clipboard. No message is sent automatically.

The current build passes 29 automated tests. The user has confirmed transcription and insertion through the pill in TextEdit and other native apps on the previous build. The revised keyboard stop and Microsoft insertion path still need physical testing. Do not mark that compatibility work complete based on the unit tests.

## Ground rules

- Audio processing, future cleanup and meeting notes stay on this Mac. No hosted fallback, telemetry or cloud transcript uploads.
- Keep Control+Y start/stop and Wispr's Fn independent. Successful dictation needs no extra insertion button or per-app toggle.
- Preserve raw text. Unsupported or changed destinations receive a clear preview fallback. Never retry an uncertain insertion automatically.
- Password fields and known terminals remain excluded from automatic insertion. Never send Return or execute dictated text.
- Use existing Swift/AppKit/Speech code. Add dependencies only for a measured capability gap.
- Agents use synthetic test inputs, never private transcript history, messages or audio. The user grants macOS permissions and runs personal speech tests.
- Keep source, tests, plans and evidence in this repository. Keep build products and private data out of Git. Use personal GitHub identity and delegate Git writes.

## When you return: test the current app

1. Preserve any current text, then quit Yada using its menu-bar Quit item.
2. In Finder, press Command+Shift+G and enter the project folder path: `/Users/srinidhi.ramanujam/code-workspace/my_projects/project-yada/.build/Build/Products/Debug/`. Open Yada.app.
3. If macOS requests it, enable Yada under System Settings → Privacy & Security → Accessibility. Microphone permission is separate. No new library installation is needed for this step.
4. Open a new TextEdit document and click in it. Press Control+Y, wait for Listening, speak a short non-sensitive sentence, and press Control+Y again. Do not click the pill. Confirm one insertion and no duplicate text.
5. Repeat in an unsent Outlook email body and Teams compose box. Do not send the test message. Confirm the cursor stays in the destination after a verified insertion.
6. Try replacing selected text, Undo, cancelling, and moving the cursor or switching apps during recording. The latter cases should fall back rather than insert into the wrong destination.
7. If something fails, report the app/version, field type, action and exact Yada status message. Do not include private text. Record numeric timings from Yada if useful.
8. Use `docs/mvp2-acceptance.md` for the full 20-trial-per-surface gate. Delete only your synthetic test drafts afterward.

## Ordered delivery steps

### 1. Finish reliable everyday dictation: in progress

1. Add actionable explanations for unsupported active fields. Distinguish a non-text focus, unavailable field text, missing cursor information and unsupported insertion instead of one generic failure.
2. Add deterministic coverage for those decisions; leave speech and successful insertion behavior unchanged.
3. Run the full native test suite and record evidence in the acceptance document.
4. Complete the physical keyboard and app matrix above when the user returns. Fix demonstrated failures in the existing delivery path before expanding compatibility.
5. Measure readiness and finalization on cold/warm runs, offline recognition, first/last-word retention, microphone denial/device changes, and Fn coexistence.

Files: `Yada/Delivery/ActiveFieldInsertion.swift`, controller/UI only where needed, `YadaTests/YadaTests.swift`, `docs/mvp2-acceptance.md`, verification skill.

Gate: no wrong-target insertion, duplicate retry, unintended submission or command execution; honest recovery for unsupported fields. Physical tests remain pending until actually run. Steps 1.1 and 1.2 are implemented; Step 1.3 passes all 29 tests. See the local follow-on section in docs/mvp2-acceptance.md. The user has authorized publishing these implementation changes to main. Steps 1.4 and 1.5 still require physical acceptance.

### 2. Add conservative, optional cleanup

1. Create one deterministic transformation path after finalization and before delivery, with Raw as the default/bypass.
2. Start with whitespace normalization. Add disfluency rules only with positive and counterexample fixtures; do not broadly delete words such as “like” or “well.”
3. Add an explicit user-managed terminology replacement list with exact phrase boundaries. Do not infer corrections by observing other apps.
4. Preserve raw and cleaned text, transformation version, and access to the original in history. Migrate existing history without data loss.
5. Add the smallest Raw/Clean control and test it through the same dictation lifecycle.

Gate: numbers, negation, dates, names, quotations and code survive; already-clean text stays substantively unchanged; cancellation and insertion checks still pass. No model download is needed.

### 3. Offer local formatting with review

1. Check the installed Apple on-device model's availability before adding inference; record any user setup needed.
2. Implement one bounded model pass for faithful prose, bullets or email draft. Give it no tools or external access.
3. Preserve raw/cleaned/formatted versions and start with review before insertion.
4. Handle timeout, unavailable model, refusal and invalid output by retaining faithful text with a clear reason.
5. Evaluate synthetic fixtures for meaning, numbers, commitments and instruction-like transcript text. Measure latency locally.

Gate: no unapproved factual or commitment changes in the critical evaluation set. Compare one alternative local model only if Apple fails the measured workload; review disk, memory and download requirements first.

### 4. Package a repeatable personal build

1. Document one build/test/install procedure with a stable app location so launching and permission maintenance are predictable.
2. Verify version display, graceful quit, clean upgrade, history compatibility and recovery from corrupt local data.
3. Add login startup only as an explicit user-controlled preference if requested.
4. Decide personal ad-hoc installation versus signed distribution before adding Developer ID signing/notarization. A paid developer account is not required for current local development.

Gate: a fresh build can be installed, launched and upgraded using the documented steps without losing history or silently resetting permissions. External distribution is a separate release decision.

### 5. Record and transcribe a meeting manually

1. Add a separate Record Meeting flow with explicit start, participant permission and visible pause/stop.
2. Capture microphone and selected system/process audio as separate timestamped tracks. Start with headphones and a controlled test call.
3. Save recoverable local chunks plus a manifest; target at most five seconds of crash loss and test that claim.
4. Transcribe after stop before attempting live meeting transcription. Mark missing intervals explicitly.
5. Support local transcript export and deletion of all session artifacts.

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
6. Commit and push only within the user's authorized scope. The user has authorized pushing the plan and the completed field-diagnostics changes to `main`. Future publication requires authorization for that scope.

Do not start all roadmap phases at once. Complete one slice and its observable behavior before moving to the next; continue independent synthetic work while physical acceptance awaits the user.
