# Yada build plan

Updated: September 7, 2026. This is the delivery checklist; `Yada_Product_and_Technical_Spec.md` contains the detailed product design. Update this file as work passes its checks. A built feature is not automatically a verified feature.

## Current position

Version 0.1.0 is on `main` (initial release commit `a75d04d`). It includes local Apple transcription, a configurable start/stop shortcut (currently Control+Y), Dock and menu-bar access, a small recording pill, local history of 50 transcripts, and automatic insertion. Native accessible fields use direct selected-text writes. Installed Outlook and Teams use a guarded paste path that leaves the transcript on the local clipboard. No message is sent automatically.

Implementation progress is pushed to `main` through `cb8c584` (September 7): simplified dictation setup, single-instance protection, shortcut registration feedback, and a non-notarized local DMG workflow. The current build passed 62 app tests and 10 Python tooling tests. Release compilation, app signature verification and DMG verification passed. Apple Developer enrollment and notarization are deferred at the user's request.

The next milestone is installed-app reliability. Control-Y outside Yada, insertion in Notes/TextEdit/Outlook/Teams, duplicate Accessibility cleanup and permission retention have not passed physical acceptance. Testing resumes with the checklist below. The experimental meeting slice is implemented, but live routing and successful file transcription remain unverified.

## Everyday-flow simplification, September 7

The user rejected the configuration-heavy dictation UI. The default is now deterministic cleanup and direct insertion with one saved shortcut. Mode selection and model-formatting controls are removed from the main dictation flow. Setup appears only when actual permission/language checks fail or Settings is opened. Language changes persist immediately; existing shortcut and terminology choices survive.

A startup guard covers production and development copies and a shared lock prevents two updated builds from owning the microphone/shortcut. The audit found both an old production-identity debug app and the development app running, each ad-hoc signed. A later process check found neither running. No valid signing certificate exists and no canonical installed release exists. Existing Accessibility rows remain OS-owned; installation consolidation and permission repair are still required. Paid certificate setup is deferred. Do not claim permission persistence has been fixed merely by saving app preferences.

## Immediate priority: one installed app and reliable global dictation

The follow-up audit found one running development build, a persisted Control+Y shortcut in both preference domains, and no valid signing certificate. Two Accessibility entries remain, and the user reports that the global shortcut does nothing outside Yada. The shortcut failure is unresolved; stable signing alone is not proof that it is fixed. The latest simplification suite passed 62 tests, but these do not establish physical shortcut delivery.

1. Apple Developer enrollment is parked at the user's request. Build an explicitly non-notarized local testing DMG without paid credentials; do not block dictation fixes on signing.
2. Build and validate the production identity, then install the everyday app at `/Applications/Yada.app`. Stop launching development build products for everyday testing.
3. Retire obsolete Yada app copies and repair only Yada's obsolete Accessibility entries through supported macOS controls. Preserve transcript history, meetings and preferences. Do this after the installed replacement is ready, to avoid another permission repair cycle.
4. Verify shortcut registration and event delivery independently of insertion permissions. Resolve any registration failure or silent busy-state handling before calling the flow complete.
5. Verify Control+Y starts and stops dictation while Notes, TextEdit, Outlook email body and Teams compose retain focus; verify insertion without clicking the pill or sending a message.
6. Verify quit/relaunch and an upgrade at the same installation path. Preserve settings/history and record any required permission repair: ad-hoc signing cannot promise grant retention across rebuilds. Each recipient grants permissions on their own Mac; Yada cannot grant itself access.

Local packaging now passed 62 app tests and 10 tooling tests and produced a verified non-notarized DMG. Shortcut registration failures are visible and retried on activation; busy meeting/language gates bring the app forward. No permissions or app copies were removed. Physical shortcut delivery and installation/upgrade acceptance remain open; no root cause for the reported cross-app failure has been confirmed.

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
2. Install the local testing DMG following `docs/releases.md`, eject it, then open `/Applications/Yada.app`. Use this one installation for everyday testing.
3. If macOS requests it, enable Yada under System Settings → Privacy & Security → Accessibility. Microphone permission is separate. No new library installation is needed for this step.
4. Open a new TextEdit document and click in it. Press Control+Y, wait for Listening, speak a short non-sensitive sentence, and press Control+Y again. Do not click the pill. Confirm one insertion and no duplicate text.
5. Repeat in a new Apple Notes note, an unsent Outlook email body and a Teams compose box. Do not send the test message. Confirm the cursor stays in the destination after a verified insertion.
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
6. Commit and push only within the user's authorized scope. The user has authorized pushing the plan and the completed field-diagnostics changes to `main`. Future publication requires authorization for that scope.

Do not start all roadmap phases at once. Complete one slice and its observable behavior before moving to the next; continue independent synthetic work while physical acceptance awaits the user.
