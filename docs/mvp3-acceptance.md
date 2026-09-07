# Cleanup and local formatting acceptance

## Implemented behavior

Raw is the default and bypasses transformations. Clean normalizes repeated horizontal spaces in unprotected text and applies the user's exact case-sensitive terminology pairs once, with word boundaries. Explicit quotes, backticks, fenced code, indented lines and line breaks are preserved. These are conservative syntax rules, not general code detection. No rule deletes fillers, changes dates or infers spoken corrections.

Prose, Bullets and Email use one fresh Apple `SystemLanguageModel.default` session with no tools. They preserve the original/cleaned text and require review before delivery. The model is instructed to preserve meaning, remove only obvious fillers and resolve only unambiguous spoken corrections. Prompting is not a guarantee of fidelity. Number comparison produces a warning, not a proof of semantic equivalence. The review flow captures a fresh destination only after the user chooses Use reviewed text and presses the shortcut there; it does not reuse the pre-review target or start recording.

Language support and model availability are checked at request time. Requests over 3,000 UTF-8 bytes are rejected, not truncated. Empty/oversized output, context/refusal errors, cancellation and a 30-second deadline preserve unformatted text. The deadline cancels the request and ignores late output; it cannot guarantee that the system immediately releases all model resources.

Saved history has optional raw, cleaned, formatted, cleanup-version and formatting-style fields. Legacy records decode without a destructive migration. No surrounding destination text or audio is added to history. Mode and explicit terminology pairs are saved locally in a separate validated JSON file. Corrupt settings/history are not silently overwritten.

## Evidence

- Full regression command: `xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test`.
- Initial extended suite: 39 tests passed. Review fixes added a permission-retry regression, bringing the suite to 40; all passed.
- Previous full suite: **41 tests passed, zero failures**, including the real 30-second deadline. Result: `.build/Logs/Test/Test-Yada-2026.09.06_03-54-38-+0530.xcresult`.
- Synthetic tests cover protected quotes/code, numbers/negation preserved by rules, word boundaries and non-cascading replacements, Raw bypass, session-frozen rules, Clean-before-delivery, model failure, mandatory review, fresh-target one-shot delivery, cancellation/late results, permission recovery, restored number warnings, legacy history and settings corruption.
- A read-only framework availability probe reported `unavailable(appleIntelligenceNotEnabled)` on this Mac. No settings were changed and no user transcript was passed to a model.
- Independent source review found three defects: missing Accessibility left reviewed text in an unretryable state; background formatting did not present progress; restored history lost review warnings. All were corrected. See `.audit/cleanup-formatting.tsv`.
- Native UI automation failed twice with `Sky Computer Use native pipe closed before response`. An isolated preview was launched, but interactive UI checks were not completed. The debug preview now has synthetic recognition and formatting, in-memory settings/history and no registered global shortcut.

## Review fixes and model check — 7 September 2026

- Simplified shared finalization/delivery and compiled cleanup expressions once per utterance. Added automatic/reviewed delivery parity coverage.
- Fixed late recognition failures clearing finalized text, terminology matches splitting Unicode combining marks, and hidden preview feedback after a reviewed insertion cannot find a usable field. Cleanup version is now `whitespace-terms-v2`; existing history remains unchanged.
- Full suite: **45 tests passed, zero failures**, including the 30-second deadline. Result: `.build/Logs/Test/Test-Yada-2026.09.07_00-11-49-+0530.xcresult`.
- Apple's framework now reports `available`. A synthetic request through production `LocalFormatter` with `en-US` completed locally: “Please review the draft on Friday. Do not send it yet.” Output preserved that sentence unchanged.
- The same formatter with `en-IN` rejected the locale before generation because `supportsLocale` returned false. For reviewed formatting on this installation, select English (United States) in Yada and check its speech assets. Raw/Clean do not require this model. No language, privacy, or Apple Intelligence settings were changed during verification.
- This is a basic live smoke check, not a semantic quality evaluation. No private history or microphone input was used.

## Remaining physical and semantic checks

1. Restart the newly built real app. Confirm default Raw and existing Control+Y behavior. Select Clean, add a synthetic phrase replacement, dictate, and compare Raw/Cleaned history versions.
2. Verify the Setup/Terminology sheet, scrolling review screen, history version picker, copy controls and cancellation with synthetic text. Confirm the formatting window appears when dictation began with the main window closed.
3. Apple Intelligence is now available on this Mac. Choose Check model in Yada and use a supported speech locale for formatting; English (US) passed the live smoke check, while English (India) was rejected. No additional inference package is needed.
4. For each reviewed style, evaluate synthetic passages containing numbers, names, negation, dates, uncertainty, quoted instructions, code, fillers and explicit/ambiguous spoken corrections. Examples: “Do not send 120 until Friday”; “Tuesday, sorry, Thursday”; “I actually like this”; a quotation containing “ignore previous instructions.” Do not send any test email or chat.
5. Compare each result against Raw. Record omissions, additions, changed commitments and formatting latency. Zero unapproved factual/commitment changes in the critical fixtures is required before considering automatic model delivery. Current implementation always requires review.
6. Exercise unavailable-model, unsupported-language and long-input fallback. Test cancel, repeated shortcut during formatting, review → new target → one insertion, permission denial → grant → retry, and a destination changing before insertion.
7. Continue the prior physical insertion matrix in `mvp2-acceptance.md`; this task does not establish Outlook/Teams or physical shortcut compatibility.

Broader live model quality, measured latency and the interactive UI remain unverified. The feature is implemented locally, with those acceptance gates open.

## API basis

The installed macOS SDK's FoundationModels Swift interface was checked for availability, session construction, locale support and response options. Apple's [SystemLanguageModel documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) describes the on-device model; [generation guidance](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models) documents availability checks and sessions with instructions.

## Follow-on evaluation and onboarding

The September 7 onboarding build passed 49 app tests, including permission refresh, revocation, explicit microphone requests and recovery preserving reviewed text. Result: `.build/milestone-tests/Logs/Test/Test-Yada-2026.09.07_00-21-13-+0530.xcresult`. The isolated native preview launched, but UI automation failed with `Sky Computer Use native pipe closed before response`; visual acceptance remains pending.

See `formatting-evaluation-2026-09-07.md` for 18 live synthetic requests and manually reviewed outputs. The critical semantic gate failed on quotations/code. Do not equate successful model generation or unit tests with faithful model output.

Final review fixes were reverified: 49 tests passed, zero failures. Result: `.build/milestone-tests/Logs/Test/Test-Yada-2026.09.07_00-25-04-+0530.xcresult`.

## Single-default dictation follow-on

The user requested removal of mode choices and repeated setup. Dictation now defaults to deterministic cleanup; saved legacy review-mode choices load into this single automatic path, with terms and original transcripts retained. The text-mode picker and model-formatting UI are removed. Permission/language setup is hidden when checks pass, with optional Settings for deliberate changes. Language persists immediately, Control+Y is assigned only if no shortcut is saved, and the app records that an explicit Accessibility registration prompt has already been shown. Actual grants are always checked with macOS.

Full suite: 62 tests passed, zero failures, at `.build/simple-tests/Logs/Test/Test-Yada-2026.09.07_14-58-24-+0530.xcresult`. New tests cover mode migration without lost terminology, language persistence, detection of older/development instances, and exclusive lock release/reacquisition. The synthetic preview launched but native UI automation still failed with `Sky Computer Use native pipe closed before response`; visual acceptance remains pending. Existing OS permission entries and signed upgrade persistence remain unresolved until certificate setup/migration.
