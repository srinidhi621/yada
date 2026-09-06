# Yada: local-first Mac dictation and meeting notes

**Working name:** Yada  
**Specification version:** 0.1  
**Research checked:** September 6, 2026  
**Status:** Proposed implementation plan, not an implemented or benchmarked application.

## Current user-approved extension — September 6, 2026

After reporting successful live transcription and copy/paste, the user requested Dock/Command–Tab presence, persistent menu-bar access, a floating recording pill with audio-level animation, and recent transcripts. The user explicitly selected saving transcripts locally between launches. This supersedes the initial no-history default for this personal build: keep the last 50 finalized text results in local Application Support JSON, with individual deletion and Clear history; save no audio. Cancelled sessions are excluded. Preserve the chosen Control+Y shortcut and Wispr's Fn binding. The pill must not take keyboard focus. The user subsequently approved automatic insertion from the global shortcut across supported active applications, without per-app switches. The current implementation uses direct Accessibility selected-text writes with target and text verification for native fields. Following reported failures in installed Outlook/Teams compose fields, these apps use a guarded, process-targeted Command+V with current-host-only clipboard text. The clipboard retains the transcript; no Return or automatic retry is sent. Live compatibility is pending; see docs/mvp2-acceptance.md. Other later slices remain deferred.

The user has now authorized both conservative cleanup and local model formatting. The local implementation adds Raw/Clean and three reviewed formatting modes, exact user-managed terminology, history variants, and a one-shot shortcut to deliver reviewed output to a freshly captured field. Apple Intelligence was disabled at implementation time; live semantic evaluation remains pending. See docs/mvp3-acceptance.md.

## 1. Decision

Build a small native macOS menu-bar app. Start with Apple’s on-device speech recognition, add reliable insertion into the apps used every day, then conservative cleanup and optional local formatting. Add meeting capture only after dictation is genuinely useful.

The initial stack is Swift, SwiftUI/AppKit, AVAudioEngine, Apple SpeechAnalyzer/SpeechTranscriber, and one global-shortcut package. Use Foundation Models’ explicitly on-device SystemLanguageModel for the first formatting experiment. Add an external speech or language model only when a measured limitation warrants it.

Do not start with Electron, a Python backend, an inference server, a plugin marketplace, or a multi-model selector. The unit of progress is one end-to-end user workflow with acceptance evidence, not another integrated library.

**First usable outcome:** choose a shortcut, speak, stop, inspect a faithful transcript, and copy it without an audio or text upload.

**First replacement outcome:** perform that workflow in ChatGPT/Codex compose boxes, email, Teams, and a controlled terminal surface without opening Yada’s editor, with safe recovery when insertion cannot be verified.

## 2. Recovered context and boundaries

The recovered August 21–22 discussions covered two relevant threads: an open-source survey for a personal local Wispr Flow replacement, and an architecture/product review of Muesli. The prior requirements included hotkey recording, low latency, terminology correction, filler removal, active-app insertion, microphone plus system-audio meeting capture, diarization, summaries and action items, search, and Markdown/PDF export. Writing-style adaptation, role/project relevance, calendar integration, and possible future productization were also mentioned.

The complete old survey response was not recoverable. The reference register below is freshly checked primary-source research, not a claim that every listed item appeared in an earlier conversation. No relevant standalone survey/specification was recovered from the file-library search.

The current request supersedes the earlier allowance for “very cheap” cloud processing: **Yada’s audio, transcripts, cleanup, and summarization must remain local.** Cloud fallback is out of scope, including when an on-device model is unavailable.

Historical hardware references conflict between an M3 MacBook Air and an M5 MacBook Pro with 24 GB memory. Do not resolve that conflict by inventing a benchmark or hard-coding a chip. Inspect the actual development Mac before implementation. The architecture targets Apple Silicon and checks capabilities at runtime.

Wispr Flow remains installed during evaluation. Yada must not register, intercept, or change the Fn shortcut used by Wispr Flow. The user selects a different chord during onboarding; do not assume a globally conflict-free default.

### Product privacy boundary

Yada owns capture, recognition, transformation, its storage, and delivery to the chosen text surface. The destination application’s subsequent handling of the text is outside Yada’s control. Local transcription does not make a cloud-connected email or AI application local.

One-time, explicit model/language downloads are allowed as setup, not as part of the audio-processing path. No user audio or transcript may be attached to those requests. Runtime failures return a local error or the last faithful text rather than selecting a hosted provider.

## 3. Verified implementation options

### Apple-first baseline

SpeechAnalyzer with SpeechTranscriber provides on-device recognition, asynchronous results, and system-managed language assets. Apple distinguishes provisional results from finalized results and requires finalization when input ends. Language availability and installed assets must be checked rather than assumed. This is the first ASR implementation to test. [S1, S2]

Foundation Models’ SystemLanguageModel is the explicitly on-device language-model choice. Availability depends on the actual device and system configuration. Apple’s newer framework also exposes Private Cloud Compute, so merely importing Foundation Models does not establish locality. Do not instantiate a cloud model. [S3, S4]

Use the stable APIs available on the installed macOS and Xcode. The recommended baseline uses macOS 26-generation speech and language APIs; do not require a beta OS for the MVP. When the chosen local API is unavailable, explain why and either provision supported assets or explicitly select one local alternative.

### External ASR, only after a failed baseline

**FluidAudio + Parakeet** is the first alternative to benchmark for English dictation and a useful later source of VAD and diarization. Its current documentation separates batch/sliding-window ASR, offline diarization, and streaming diarizers. Parakeet v2 is English-only; v3 adds 25 European languages. That does not establish support for Indian-language code-switching. [S5]

**WhisperKit**, now in `argmaxinc/argmax-oss-swift`, is the native Swift Whisper alternative. The OSS SDK also includes SpeakerKit; do not assume every capability advertised for Argmax Pro is part of the OSS package. **whisper.cpp** is the other local Whisper runtime to examine when its model support or portable C/C++ integration is a better fit. Choose one, not both. [S6, S7]

Previously surfaced names such as Nemotron, Qwen3-ASR, SenseVoice, Indic ASR, and Cohere Transcribe remain an evaluation watchlist, not required dependencies. Muesli’s current implementation lists multiple such providers, but supporting its full catalogue would contradict this MVP’s purpose. [S8]

### External cleanup or formatting, only after measurement

**S1-mini by Superwhisper** is a particularly relevant specialist: a 0.6B English transcript-normalization model based on Qwen3-0.6B. Its publisher recommends short inputs, supplies GGUF weights, and specifies an input/control format with thinking disabled. It is not a general meeting-summary model. Its license includes an additional naming condition, so do not describe it as unmodified Apache-2.0. [S9]

A small quantized Qwen or Gemma instruction model remains appropriate for broader organization or meeting summarization. Do not pick the largest model that fits in RAM. Begin the experiment in roughly the 2–4B class, then increase only for a demonstrated quality gain. Exact model/version/quantization selection is deliberately deferred.

For a Swift app, **MLX Swift LM** is the first embedded-runtime candidate. **llama.cpp** is the alternative when a selected GGUF model or implementation is more straightforward. Use only one external language runtime in the application. Neither is needed in the first two MVPs. [S10, S11]

Ollama may be useful as a temporary local comparison harness, but should not become a required background service by default. A local URL alone is not sufficient evidence of local model execution; verify the selected provider and keep cloud providers disabled.

### Open-source applications worth reading

| Reference | Useful lessons | How to use it in Yada |
|---|---|---|
| Muesli, MIT [S8] | Native combined dictation/meeting workflow, capture, provider boundaries, insertion | Closest product reference. Study specific implementations, not its entire feature set. Its optional hosted providers and text sync do not meet Yada’s strict defaults. |
| VoiceInk, GPL-3.0 [S12] | Native dictation UX, shortcut handling, terminology and app-specific modes | Read for interaction patterns. Record the exact license before reusing source, especially if later distributing Yada. |
| Handy, MIT [S13] | Small offline shortcut-to-text workflow | Compare its interaction and failure behavior. Do not adopt cross-platform architecture merely because it is available. |
| OpenWhispr, MIT [S14] | Dictation lifecycle, insertion, settings and local/cloud separation | Another implementation reference; its Electron stack is not the proposed Yada stack. |
| Meetily, MIT repository [S15] | Meeting capture, transcription and summary workflow | Read when the meeting slice starts. Verify community versus paid capabilities rather than assuming feature parity. |
| KeyboardShortcuts [S16] | Configurable global shortcut recording and registration | The one small third-party dependency justified in MVP 1. |

These are reference implementations, not evidence that Yada must be built from scratch. If subscription replacement alone becomes the objective, a reviewed and restricted Muesli fork may be less work. A small independent app is justified here by the additional goals of learning, explicit control, and a narrower auditable runtime.

Pin any reused dependency or source to a release/commit. Record model revisions, hashes and licenses separately from SDK licenses. Avoid copying across incompatible licenses without review.

## 4. Minimal architecture

```text
User-selected global shortcut
    -> session controller
    -> microphone capture
    -> on-device ASR
    -> finalized raw transcript
    -> optional conservative cleanup
    -> optional local formatting
    -> delivery safety check
    -> preview / active text field / local copy

Later meeting mode:
Explicit recording action
    -> microphone track + selected system-audio track
    -> bounded durable recording and timestamped transcription
    -> optional offline speaker clustering
    -> editable speaker labels
    -> source-linked local summary
    -> local save / export
```

These are responsibilities inside one app, not separate services. Start with an app target and a test target. Introduce a thin recognition boundary for replay tests and future replacement. Add a transformation boundary when MVP 3/4 needs it. Avoid building a general provider/plugin framework.

A practical eventual folder layout is:

```text
Yada/
  App/                 menu bar, onboarding, settings, preview
  Dictation/           controller and transcript assembly
  Audio/               capture, formats, device events
  Recognition/         Apple adapter; another only if justified
  Delivery/            target validation and insertion
  Transforms/          conservative cleanup and local formatting
  Meetings/            added only when meeting work begins
  Storage/             added as durable data is introduced
YadaTests/
docs/
  spec.md
  decisions.md
  acceptance.md
  sources.md
```

Do not create empty implementations for future folders. Keep personal recordings, transcripts and downloaded weights outside the repository and outside directories supplied to cloud coding assistants.

### Session state and ownership

The initial lifecycle is `idle -> preparing -> recording -> finalizing -> ready`, with explicit cancellation and recoverable failure. MVP 2 adds `delivering` and an `outcomeUnknown` state for an unacknowledged paste.

Only one dictation session owns the microphone pipeline at a time. Stop/release ends input, drains pending audio and finalizes recognition. Cancellation must not accidentally perform insertion. Do not cancel the recognition task before requesting its final output.

Partial results are replaceable UI state, not append-only transcript text. Final segments have stable IDs/time ranges. Never insert live partial text into another app in the MVP.

Audio callbacks must not perform model inference, UI work, or blocking disk operations. Use bounded queues. Buffer exhaustion is a visible capture fault, not silent dropped speech. Negotiate the recognizer’s required audio format rather than assuming every recognizer accepts 16 kHz input.

## 5. Vertical slices and release gates

### MVP 1 — Hear me and show what I said

**Workflow:** select a shortcut once; trigger recording from any app; receive an unmistakable recording-ready indicator; speak; trigger stop; see a finalized transcript in Yada; copy it locally.

**Include:** menu-bar app, shortcut recorder, microphone permission, input-device status, waveform or level indication, cancel/stop controls, Apple ASR, final transcript preview, local copy, and metadata-only diagnostics. Start with toggle recording. Hold-to-talk may be a small follow-on, not a prerequisite.

**Exclude:** automatic insertion, filler editing, language-model inference, meeting audio, transcript history, calendar, text-context scraping, and external model selection UI.

Treat “raw” as the unedited recognizer result. It is not a promise of a phonetic/verbatim transcript: the ASR engine may already normalize punctuation or omit disfluencies. Preserve what it actually emitted, without trying to reconstruct omitted words.

**Acceptance:** offline after assets are installed; first and last words preserved across a repeatable utterance set; no duplicated partial/final text; recoverable microphone denial and device removal; silence produces no committed invented text; cancellation never inserts or copies; Fn still drives Wispr Flow.

**Deliverable:** a working app and a documented local test, not a console-only recognizer.

### MVP 2 — Put the words where I am typing

**Workflow:** focus a supported text field, dictate, stop, receive the completed text at that selection/caret. Use the raw transcript initially so insertion quality is not confused with rewriting quality.

Current implementation: use direct Accessibility selected-text insertion based on field capabilities, with no application allowlist or per-app opt-in. Outlook and Teams are explicit compatibility exceptions using a guarded paste event; this was added after the user reported their compose fields failing direct insertion. Capture the originating app, PID and accessible focused element before recording. A non-activating recording overlay must not steal that focus.

Before delivery, validate that the target is still eligible and that the user has not moved to a different app/field or edited the target in a detectable way. If certainty is insufficient, keep the transcript in a preview and require an explicit insertion/copy action. UI focus changes can race with delivery; this guard reduces risk rather than establishing a universal atomic operation.

Verify selection and undo behavior of direct Accessibility selected-text insertion in each tested application. Never replace an entire field merely because setting its full value is easier. Accessibility exposes settable attributes, but that does not guarantee uniform behavior in every editor. [S17]

**Delivery ladder:** tested automatic path -> explicit local copy/manual paste. Add app-specific paths only for demonstrated failures. A browser extension, ChatGPT API, Codex API, Teams bot, or email connector is unnecessary for a text-insertion MVP.

If the write cannot be verified by reading the expected resulting text, report “check insertion,” not verified success. Do not automatically retry an uncertain action and risk duplicate text.

**Initial test surfaces:** ChatGPT and Codex compose boxes, email compose, Teams chat, TextEdit as a native control, and the user’s terminal. Test the actual application versions and field implementations rather than promising “every text field.”

**Terminal safety:** default to preview; only enable automatic insertion after testing. Use literal, single-line output. Remove/reject control characters and embedded line breaks, including a trailing newline. Never press Return or execute commands. A multiline paste can be operationally dangerous even without a separate Return keystroke. Keep shell/code identifiers outside prose rewriting.

Do not insert into password/secure fields or circumvent Secure Input. Unknown or unsupported targets fall back to preview.

**Acceptance:** 20 insertion trials per named surface, including selection replacement, undo, Unicode, deliberate focus changes and a changed clipboard. Zero wrong-target insertions and zero command execution in the test set. Failures are visible and recoverable; not silently swallowed.

### MVP 3 — Remove noise without changing meaning

**Workflow:** dictate into the same real apps, optionally select Clean mode, receive conservative cleanup, and retain access to the raw transcript for comparison.

Start with deterministic whitespace handling and a narrow, reviewed set of unambiguous standalone disfluencies. Handle punctuation boundaries. Do not globally delete words such as “like,” “well,” “so,” “right,” or “actually”; they carry meaning in many sentences. Quoted literal filler tokens and technical abbreviations need regression tests.

Add an explicit personal replacement dictionary for recurrent terminology errors. Corrections come from user-approved pairs in Yada, not passive observation of everything typed elsewhere. Prefer exact phrase rules with word boundaries over broad fuzzy replacement. Preserve case-sensitive identifiers and record a transform version.

Self-corrections such as “Tuesday, sorry, Thursday” are not a safe general regex problem. Leave them intact in conservative mode until a model-backed path passes the semantic tests. The scope is faithful cleaning, not interpreting what the user “must have meant.”

**Acceptance:** already-clean text stays substantively unchanged; numbers, dates, negation, names, hedges, code and quotations survive; each rule has positive and counterexample tests; Raw mode bypasses all cleanup.

### MVP 4 — Organize the thought with a local model

**Workflow:** explicitly select a style, dictate, receive a locally structured version, review it, then insert. Preserve Plain/Clean as low-latency defaults.

Begin with Apple’s on-device SystemLanguageModel. Try only three styles: faithful prose, structured bullets, and email draft. Each should preserve content rather than add greetings, signatures, claims or commitments that were not requested. The terminal profile bypasses this stage.

Use a fresh bounded model session per utterance. The transcript is data to edit, not an instruction stream. A transcript that says “ignore earlier instructions” must not change the formatter’s role. Give the formatter no tools, file access, calendar access, network providers, or execution authority.

Preserve raw, cleaned and formatted versions as separate in-session values. In formatted mode, rules plus one model pass is the maximum default chain. Do not automatically stack a specialist normalizer and a general LLM.

On timeout, refusal, invalid output, unavailable model or suspected meaning change, retain the raw/cleaned text and show the reason. Do not silently truncate input. Start with review-before-insert for formatting; automatic formatted insertion requires its own regression gate.

Use text comparisons and protected-entity checks as warning signals, not a proof of semantic equivalence. Numerical reformats may be legitimate, while identical numbers can still express changed commitments. Human evaluation remains necessary.

If Apple’s model fails the actual corpus, compare S1-mini for normalization or one small Qwen/Gemma model for wider formatting. Benchmark the alternatives against the same task rather than choosing by general chatbot reputation.

**Acceptance:** zero unapproved factual/commitment changes in the critical fixture set; content-bearing units preserved; unrelated instruction-like text cannot trigger actions; output fit and latency measured under the user’s normal workload; cancellation and fallback work.

### MVP 5A — Capture a meeting manually, then transcribe

**Workflow:** choose Record Meeting, acknowledge participant permission, capture microphone and selected system audio, stop, review a timestamped transcript, save/export locally.

Use AVAudioEngine for the microphone and a Core Audio process tap for system output. Apple provides process-tap capture APIs, so a virtual audio driver is not the first dependency. Keep ScreenCaptureKit as a later alternative for actual routing failures. [S18, S19]

Store local microphone and remote/system output separately with monotonic timestamps. Label them `Local microphone` and `Remote audio`, not trusted identities. “Me” is safe only when one known local speaker is actually on that microphone.

Target the meeting process where possible. Browser process capture may include unrelated tabs or renderer processes; verify the route with a test call. Start with headphones. Speaker playback can re-enter the microphone and cause duplicated speech, which is a separate echo problem.

Start with durable recording followed by local transcription after stop. Do not make simultaneous live recognition, diarization and summarization prerequisites for a successful recording. Add incremental transcription later if post-meeting latency is unacceptable.

Write bounded recoverable audio chunks plus a manifest. Select and document a maximum crash-loss window, initially 5 seconds, and verify it experimentally. Mark missing ranges explicitly. Save speaker-independent transcript segments with timestamps so later diarization can enrich them without changing the source text.

**Important:** muting in Teams does not imply Yada’s separate microphone capture is muted. Yada needs its own visible pause/mute control. Similarly, a participant’s recording permission and workplace rules remain prerequisites even when no meeting bot appears.

**Acceptance:** a consented 30–60 minute test call; both tracks present; remote audio captured with headphones; Bluetooth disconnect handled; start/stop and permission changes visible; crash recovery within the declared window; transcript export contains all recorded intervals or explicit gap markers.

### MVP 5B — Distinguish speakers, then let me name them

**Workflow:** run local diarization on the remote track, view Speaker A/B/C labels with timestamps, rename or merge them, and save/export the revised transcript.

Use FluidAudio’s offline diarization path first. Its current documentation distinguishes this from its newer streaming choices. Live diarization is unnecessary for post-meeting notes. [S5]

Diarization determines who spoke when as anonymous clusters; it does not inherently know a participant’s name. Calendar attendees are candidate metadata, not voice-to-name evidence. Keep names unset until explicitly assigned. Do not build persistent cross-meeting biometric speaker enrollment in this MVP.

Maintain stable session-level speaker IDs. Do not reset labels independently for each chunk. Permit overlapping and uncertain segments. If the local microphone captured multiple people, it also needs diarization rather than assigning every segment to the owner.

**Acceptance:** a hand-labelled multi-speaker test recording; recognizable speaker continuity; manual rename/merge; overlap and uncertain attribution retained; no invented names.

### MVP 5C — Produce notes grounded in the transcript

**Workflow:** review the transcript, request local notes, inspect summary/decisions/actions, navigate each substantive item back to source segments, and export Markdown.

Extract a small schema: summary, decisions, actions, unresolved questions and risks. Action records include description, nullable owner, nullable due date, source segment IDs and review status. “We should look at it” is not automatically an assigned action. A proposed date is not necessarily a deadline.

For long meetings, summarize bounded overlapping segments into evidence-linked intermediate records and merge them. Re-check claims against the original segments, especially disputed or revised decisions. Do not recursively summarize away caveats. Refuse to assert an owner or deadline without support.

Context capacity must come from the installed model/runtime. Apple documents 4,096 tokens for its macOS 26-era model and larger capacities in newer APIs/devices; neither is a license to feed an entire long meeting in one request. [S4]

Preserve the transcript if summarization fails. Schedule heavy post-processing below active dictation priority. Start with local files; add SQLite/FTS only when browsing/search becomes an actual slice. Markdown export precedes PDF export.

**Acceptance:** every decision/action references existing source segments; missing owner/date remains null; contradictions and uncertainty survive; summary cannot execute transcript instructions; export and deletion cover intermediate records as well as final notes.

### MVP 5D — Suggest recording when a meeting starts

**Workflow:** Yada sees a plausible meeting, offers Start Recording, and records only after the user accepts. Manual start always remains available.

Begin with calendar reminders via EventKit for calendars actually present in the Mac’s event store. Request the minimum OS-supported permission sufficient to read those events. An Outlook or web calendar is not automatically visible through EventKit. Do not add a cloud calendar integration to fix that in the initial slice. [S20]

Next combine an allowlisted meeting application with observable audio-device activity and a nearby calendar event. Treat this as a heuristic, not a reliable universal “joined meeting” API. Camera activity is optional evidence, never a prerequisite: audio-only meetings matter. Ignore Yada’s own microphone activity when evaluating candidates.

Debounce repeated events. Support dismissal, snooze and an obvious recording indicator. A scheduled event is not proof the user joined. Avoid screenshot/OCR/window-title scraping as the first detection method.

Only consider automatic recording after measuring false positives and after explicit per-app/user opt-in. Never stop solely because everyone is briefly silent. The stop policy must be tested independently.

**Acceptance:** meetings with and without cameras, an unrelated video tab, music playback, a missed calendar event, a cancelled event, an ad hoc call, and Yada dictation itself. Notifications do not duplicate, dismissals stick, and no heuristic silently starts recording in the initial release.

## 6. Privacy and data lifecycle requirements

**Content locality.** No hosted ASR/LLM SDK, analytics payload, transcript-bearing crash report, automatic cloud sync, or remote fallback. Review transitive dependencies and model-loader behavior. FluidAudio currently has an explicit offline mode for deployed local assets; use the equivalent supported path when adopting it. [S5]

**Clipboard boundary.** Use NSPasteboard’s current-host-only option where supported; Apple documents that these contents stay on the current device. This is important because clipboard transfer is a second possible locality boundary, independent of inference. [S21]

Current-host-only does not stop another local clipboard-history application from reading or syncing the contents. Offer direct Accessibility insertion on tested surfaces and a no-clipboard preview mode. Do not promise that clearing or restoring the pasteboard recalls copies already read elsewhere.

If restoring a prior clipboard, preserve supported types, wait until the tested target has consumed the paste, and restore only when the pasteboard change count is still owned by Yada. Never overwrite a clipboard the user changed meanwhile. Clipboard preservation is best-effort and must not mask an uncertain delivery.

**Dictation retention.** Default to transient audio and current-session text only. Keep an explicitly shown retry/preview state until dismissed, then clear it. Persistent history and recording retention are opt-in. Do not make silent diagnostic audio dumps.

**Meeting retention.** Save only through explicit recording/save workflows under a nonsynced Application Support location. Exclude sensitive caches from supported backups and disclose that external backup agents may have their own policies. Offer a raw-audio retention choice and a delete operation covering audio, transcript, speaker labels, summaries, indexes, temporary chunks and exports still managed by Yada. Files explicitly exported elsewhere leave the app’s deletion boundary.

**Local protection.** Use owner-restricted file permissions. Do not claim ordinary JSON/SQLite is encrypted merely because it is local. Stronger at-rest protection is a separately testable requirement if needed for client material.

**Permissions.** Ask only when the feature needs them: microphone in MVP 1, Accessibility for MVP 2 delivery, system-audio capture for meetings, and calendar access for detection. The shortcut package documents that registration itself requires no permission dialog. Verify any additional Speech authorization required by the exact selected API path. [S16, S22]

**Development privacy.** Do not put private recordings or actual client transcripts into Git, bug reports, remote CI artifacts, or cloud coding-agent context. Synthetic or consented non-sensitive fixtures belong in the repository. Personal evaluation media stays outside it.

## 7. Evaluation and replacement criteria

These are proposed acceptance targets, not claimed performance of any model or Mac.

### Dictation corpus

Create 60 consented, non-sensitive samples: 15 everyday/email messages, 15 technical utterances, 10 numbers/dates/names/negations, 10 disfluency/self-correction/quotation cases, and 10 noise/silence/device-edge cases. Include the user’s natural Indian English and terms such as PostgreSQL, Qwen, Gemma, Codex and company/product names. Add real code-switching only if it is part of the actual usage.

Keep a small holdout set untouched while tuning rules. Record ASR errors separately from transform errors and delivery failures. Corrected text, not aesthetic preference, determines fidelity.

Measure capture-ready latency, stop-to-final latency, stop-to-delivery latency, cold versus warm model behavior, transcript word error rate, critical entity/negation errors, correction effort, insertion success, peak process and system memory, CPU/GPU activity, memory pressure and battery impact. System-managed models may not appear wholly in Yada’s process memory.

Initial targets: a visible preparing state immediately; recording-ready within roughly 300 ms on the warm path; finalized raw text within 1.5 seconds p95 after stop for 5–30 second utterances; optional formatting within 3 seconds p95. Missing a speed target calls for diagnosis, not silently weakening fidelity. Longer utterances and cold starts are reported separately.

Use a provisional clean-English WER goal around 5%, but inspect error severity and actual editing effort rather than treating one percentage as the product decision. Critical regressions include altered amounts, negations, dates, names and commitments. Aim for zero such transform-induced changes in the critical test set, while recognizing finite tests cannot prove universal correctness.

### Integration and failure tests

Exercise microphone denial, unsupported locale, missing/corrupt assets, disconnecting AirPods, sample-rate changes, sleep/wake, rapid hotkey toggles, silence, long pauses, model timeout, long input, secure input, changed focus, changed clipboard, locked screen and cancellation during every state.

For offline validation, pre-provision assets, disable network connectivity and complete the full workflow. Also inspect network behavior with connectivity enabled and review configured providers. Offline success alone does not prove there is no opportunistic upload when online. Include relevant system services in the assessment when inference runs out of process.

Benchmark with the user’s normal browser/IDE/meeting workload, not just an otherwise idle machine. Compare Wispr Flow only on synthetic or explicitly approved non-sensitive material, because using it as the benchmark would itself submit that speech to its configured processing path.

### Replacement gate

Keep Wispr Flow until Yada has been used for a defined trial of ordinary work with no lost or wrong-target text, no unsafe command behavior, tolerable correction effort and acceptable latency. A suggested trial is one working week, not a delivery-time estimate. Meeting features are not a prerequisite for replacing the dictation subscription.

## 8. First implementation handoff

Inspect, without changing the Mac configuration:

```sh
sw_vers
uname -m
sysctl -n hw.memsize
system_profiler SPHardwareDataType
xcodebuild -version
```

Do not paste unredacted hardware reports containing serial numbers into public issues or cloud prompts. Detect speech-language and SystemLanguageModel availability inside the app rather than trying to infer it from hardware alone.

Then create only the MVP 1 target and tests. Add the shortcut dependency, microphone capture, one Apple ASR adapter, result assembly, visible state and local copy. Give the user explicit model-download progress during onboarding if assets are absent. Stop with an actionable explanation when the local path is unavailable.

The first handoff includes the build command, a manual offline test, passing automated transcript-assembly/state tests, actual measurements where possible, and a clear statement of tests that require the physical Mac. An agent working in a non-Mac environment must not claim macOS UI/audio validation.

After MVP 1 passes, implement the delivery slice before any model experimentation. Keep each slice independently runnable and regression-tested. Record one concise decision whenever adding a dependency, model, permission or persisted data class.

## 9. Deliberately deferred

Cross-platform support, general voice assistants, arbitrary computer control, screen-context ingestion, passive writing-style surveillance, model fine-tuning, speaker biometrics across meetings, semantic/vector search, cloud integrations, organization accounts, multi-device sync, browser extensions, payments and App Store distribution.

Role/project-aware notes, approved dictionary suggestions, history/search and PDF export remain legitimate later slices from the earlier discussions. None is necessary to validate capture, insertion or faithful cleanup.

## 10. Primary-source register

Accessed September 6, 2026. Repository READMEs describe their own implementations and claims; they are not independent performance validation. Check licenses at the exact pinned revision before redistribution.

- **S1. Apple: SpeechAnalyzer introduction and live transcription sample.** https://developer.apple.com/videos/play/wwdc2025/277/
- **S2. Apple: SpeechAnalyzer and SpeechTranscriber documentation.** https://developer.apple.com/documentation/speech/speechanalyzer and https://developer.apple.com/documentation/speech/speechtranscriber
- **S3. Apple: SystemLanguageModel.** https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- **S4. Apple: Foundation Models cloud/on-device distinction and context capacities.** https://developer.apple.com/videos/play/wwdc2026/319/ and https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
- **S5. FluidAudio repository and diarization guide.** https://github.com/FluidInference/FluidAudio and https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md
- **S6. Argmax Open-Source Swift SDK, including WhisperKit and SpeakerKit.** https://github.com/argmaxinc/argmax-oss-swift
- **S7. whisper.cpp.** https://github.com/ggml-org/whisper.cpp
- **S8. Muesli.** https://github.com/Muesli-HQ/muesli
- **S9. S1-mini model card and GGUF distribution.** https://huggingface.co/superwhisper/s1-mini and https://huggingface.co/superwhisper/s1-mini-GGUF
- **S10. MLX Swift LM.** https://github.com/ml-explore/mlx-swift-lm
- **S11. llama.cpp.** https://github.com/ggml-org/llama.cpp
- **S12. VoiceInk.** https://github.com/Beingpax/VoiceInk
- **S13. Handy.** https://github.com/cjpais/Handy
- **S14. OpenWhispr.** https://github.com/OpenWhispr/openwhispr
- **S15. Meetily.** https://github.com/Zackriya-Solutions/meetily
- **S16. KeyboardShortcuts.** https://github.com/sindresorhus/KeyboardShortcuts
- **S17. Apple: Accessibility attribute setting.** https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue and https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable
- **S18. Apple: Capturing system audio with Core Audio taps.** https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- **S19. Apple: ScreenCaptureKit sample.** https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- **S20. Apple: EventKit access and calendar integration.** https://developer.apple.com/videos/play/wwdc2023/10052/ and https://developer.apple.com/documentation/eventkit/ekeventstore
- **S21. Apple: current-host-only pasteboard contents.** https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly?changes=_3&language=objc
- **S22. Apple: System-audio permission description.** https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
