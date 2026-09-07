# Yada build plan

Updated: September 7, 2026. This is the delivery checklist; `Yada_Product_and_Technical_Spec.md` contains the detailed product design. Update this file as work passes its checks. A built feature is not automatically a verified feature.

## Current position

Version 0.1.0 is on `main` (initial release commit `a75d04d`). It includes local Apple transcription, a configurable start/stop shortcut (currently Control+Y), Dock and menu-bar access, a small recording pill, local history of 50 transcripts, and automatic insertion. Native accessible fields use direct selected-text writes. Installed Outlook and Teams use a guarded paste path that leaves the transcript on the local clipboard. No message is sent automatically.

The latest local build passes 58 automated tests, including the simplification and review fixes. Cleanup/formatting evidence is recorded in docs/mvp3-acceptance.md. Signing, packaging and onboarding are the next milestone; the remaining physical reliability checks stay open. The user has confirmed transcription and insertion through the pill in TextEdit and other native apps on the previous build. The revised keyboard stop and Microsoft insertion path still need physical testing. Do not mark that compatibility work complete based on the unit tests.

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

### 2. Add conservative, optional cleanup: implemented locally, acceptance in progress

1. Create one deterministic transformation path after finalization and before delivery, with Raw as the default/bypass.
2. Start with whitespace normalization. Add disfluency rules only with positive and counterexample fixtures; do not broadly delete words such as “like” or “well.”
3. Add an explicit user-managed terminology replacement list with exact phrase boundaries. Do not infer corrections by observing other apps.
4. Preserve raw and cleaned text, transformation version, and access to the original in history. Migrate existing history without data loss.
5. Add the smallest Raw/Clean control and test it through the same dictation lifecycle.

Current implementation: Raw/Clean mode, whitespace and exact terminology rules, preserved history variants, and settings validation. No deterministic filler deletion is enabled. See docs/mvp3-acceptance.md.

Gate: numbers, negation, dates, names, quotations and code survive; already-clean text stays substantively unchanged; cancellation and insertion checks still pass. No model download is needed.

### 3. Offer local formatting with review: implemented, broader evaluation pending

1. Check the installed Apple on-device model's availability before adding inference; record any user setup needed.
2. Implement one bounded model pass for faithful prose, bullets or email draft. Give it no tools or external access.
3. Preserve raw/cleaned/formatted versions and start with review before insertion.
4. Handle timeout, unavailable model, refusal and invalid output by retaining faithful text with a clear reason.
5. Evaluate synthetic fixtures for meaning, numbers, commitments and instruction-like transcript text. Measure latency locally.

Current implementation: explicit Apple on-device model, three review styles, cancellation/deadline, preserved originals, and one-shot reviewed insertion. Apple Intelligence now reports available. Production LocalFormatter passed one synthetic English (US) smoke check; English (India) was rejected by the framework locale check. Broader semantic quality and interactive UI acceptance remain pending; unit tests cannot close those gates.

Gate: no unapproved factual or commitment changes in the critical evaluation set. Compare one alternative local model only if Apple fails the measured workload; review disk, memory and download requirements first.

### 4. Signing, packaging and onboarding: implementation prepared, release acceptance pending

Outcome: users download a signed, notarized Yada DMG from GitHub Releases, install it in Applications and complete a short guided setup. Xcode is not required for users of the packaged app. Normal upgrades should retain permissions, settings and history.

1. Prepare a local release script with explicit version, bundle identity and signing checks. Build and test before packaging; stop clearly when credentials are missing. Do not present an ad-hoc build as a distributable release.
2. Complete Apple Developer enrollment and create a Developer ID Application certificate. The user handles payment, authentication and account agreements. Keep private keys and notarization credentials outside Git.
3. Keep the everyday installed app at `/Applications/Yada.app` with a consistent Developer ID identity and bundle identifier. Give development builds a separate identity and local data location so tests do not disturb the everyday app. Preserve access to existing history during the transition.
4. Configure release signing, hardened runtime and required entitlements. Submit to Apple's notary service, attach its ticket, validate the signature and Gatekeeper assessment, and package the DMG. Actual submission waits for credentials and authorization.
5. Implement first-run setup for microphone access, Accessibility access, speech assets and a synthetic practice field. Recheck permission when the app becomes active; stop repeated automatic permission dialogs. Explain recovery when macOS does not recognize a grant. Keep Apple Intelligence optional and report locale support clearly.
6. Verify fresh installation on another supported Mac and an upgrade between two signed releases. Check permission persistence, history/settings compatibility, quit/relaunch, and text insertion without sending messages.
7. Prepare release notes, supported hardware/macOS requirements and download instructions. Publish the signed artifact to GitHub Releases only when authorized. Automatic updates and login startup are outside this milestone.

Independent work while enrollment is pending: implement and test the credential-free release preflight/package tooling, implement onboarding state and regression coverage, and expand the synthetic Apple formatting evaluation with per-case latency and meaning checks. Use isolated build output and in-memory or temporary stores; do not restart the user's app, record audio or read private history.


Implemented locally on September 7: guided permission status/actions with activation refresh and no automatic shortcut pop-ups; separate Development identity/storage; release preflight, build/sign/package and explicit notarize commands; nine tooling tests. App suite passes 49 tests. No valid signing identity exists on this Mac, so actual signing/notarization/DMG creation remain unrun. Native UI automation still fails before inspection; onboarding visual acceptance remains pending. See `docs/releases.md`.

Synthetic evaluation completed: 18 production formatter requests, median 406 ms. Five semantic failures and one attribution concern were found; the critical quality gate failed. See `docs/formatting-evaluation-2026-09-07.md`. The next model task is to handle protected quotations/code faithfully and repeat the evaluation before expanding use. Automatic generated-text delivery remains prohibited.

After the three preparation tasks: complete certificate enrollment/setup; verify actual signed/notarized packaging; test fresh installation and signed upgrades; finish the physical dictation/insertion matrix; address formatting evaluation failures; then authorize and publish the first downloadable release. Later product stages 5 through 8 remain pending and are not part of release tooling.

Gate: verified fresh install and signed upgrade with no lost data or repeated permission repair under normal conditions. Stable signing does not bypass the initial macOS permission grant. Tooling-only checks cannot establish notarization or physical onboarding success.

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
