# Yada: first coding-agent prompt

Use alongside `Yada_Product_and_Technical_Spec.md`. This prompt implements only MVP 1, not the entire roadmap.

---

You are helping me build Yada, a personal, strictly local Mac dictation application that may later support meeting notes. My goal is to replace my existing Wispr Flow subscription without sending captured speech or transcripts to a cloud service.

Read the accompanying product/technical specification. Treat its later phases as context, not authorization to build ahead. Implement one complete vertical slice: configurable global shortcut -> microphone -> on-device transcription -> finalized preview -> explicit local copy.

## Constraints

Build a native Swift macOS app using SwiftUI/AppKit. Begin with AVAudioEngine and Apple SpeechAnalyzer/SpeechTranscriber on a supported installed macOS. Use the stable SDK already available. Do not require an OS beta or silently change system settings.

Inspect the actual hardware, macOS and Xcode. Historical references to my Mac differ, so do not assume a particular chip, RAM size or benchmark. Do not disclose serial numbers or other unnecessary system identifiers.

Keep Wispr Flow’s Fn binding untouched. Add a shortcut recorder and let me choose a separate chord during onboarding. Do not capture every keystroke or ask for Accessibility merely to register a shortcut. KeyboardShortcuts is the only initial third-party dependency unless you can demonstrate a necessary exception.

All recognition is local. Explicit one-time speech-language asset provisioning is acceptable, with progress and clear errors. Never add a hosted fallback, an API key, analytics, cloud sync, or content-bearing logs.

Do not add an LLM, filler cleanup, automatic insertion, system-audio capture, diarization, meeting detection, a database, a Python backend, an HTTP inference server, a general provider framework, or a browser extension.

## Required behavior

1. A menu-bar app exposes a small setup/preview window and recording status. Toggle recording with the chosen shortcut; an explicit Stop/Cancel control remains available. Indicate “preparing” separately from “recording.” Do not imply capture has started until the audio path is ready.
2. Request microphone permission when needed. Surface permission denial, missing input devices, unsupported locales and absent speech assets clearly.
3. Use a bounded, nonblocking audio handoff to recognition. Convert to the recognizer’s negotiated audio format, not a universal assumed sample rate.
4. Assemble provisional and finalized ASR results without duplicated text. Preserve the recognizer’s final raw output without adding cleanup. Document that ASR output need not be strictly verbatim.
5. On stop, finish audio input and drain/finalize recognition before presenting final text. On cancellation, stop safely and never insert or copy anything.
6. Display final text in Yada and offer explicit Copy. Use current-host-only pasteboard contents where supported. Do not claim this blocks third-party clipboard managers.
7. Default to transient audio and current-session text. No persistent audio/history unless I explicitly turn on a narrowly scoped diagnostic fixture mode later. Keep any private evaluation corpus outside the repository and your cloud context.
8. Wispr Flow remains functional on Fn while Yada uses its own shortcut.

## Engineering and tests

Keep one app target and one test target. Introduce only the small recognition boundary needed for deterministic tests and eventual replacement. Do not scaffold empty future services.

Model the lifecycle explicitly: idle, preparing, recording, finalizing, ready, cancelled and recoverable failure. Test rapid toggles, stale callbacks from an old session, cancellation and repeated start/stop.

Add deterministic tests for transcript assembly: provisional text revised multiple times, finalized text replacing the provisional range, multiple finalized segments, empty audio, late results, and end-of-stream finalization.

Document manual tests for microphone denial, input-device removal, silence, first/last-word capture, a multi-minute utterance, sleep/wake and offline use after asset installation.

Measure actual warm/cold capture readiness and stop-to-final latency where the environment supports it. Mark measurements as unmeasured rather than substituting vendor benchmark claims. Do not put dictated content in diagnostic output.

## Deliverables

A buildable native project, focused tests, a README with exact local build/run instructions, and `docs/mvp1-acceptance.md` distinguishing automated results, physical-Mac tests completed and tests still pending.

Before modifying files, inspect the workspace for existing code and preserve unrelated work. Do not create a GitHub repository, push changes, install a new OS, or change privacy permissions on my behalf.

Work until the MVP 1 code and the checks available in this environment are complete. If macOS APIs or hardware are unavailable, produce the implementation and document the precise unverified checks. Do not claim audio/UI success without running it.

Stop after MVP 1. The next slice will be safe insertion into the actual applications I use, not model selection.
