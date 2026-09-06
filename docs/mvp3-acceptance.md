# Cleanup and local formatting acceptance

## Implemented behavior

Raw is the default and bypasses transformations. Clean normalizes repeated horizontal spaces in unprotected text and applies the user's exact case-sensitive terminology pairs once, with word boundaries. Explicit quotes, backticks, fenced code, indented lines and line breaks are preserved. These are conservative syntax rules, not general code detection. No rule deletes fillers, changes dates or infers spoken corrections.

Prose, Bullets and Email use one fresh Apple `SystemLanguageModel.default` session with no tools. They preserve the original/cleaned text and require review before delivery. The model is instructed to preserve meaning, remove only obvious fillers and resolve only unambiguous spoken corrections. Prompting is not a guarantee of fidelity. Number comparison produces a warning, not a proof of semantic equivalence. The review flow captures a fresh destination only after the user chooses Use reviewed text and presses the shortcut there; it does not reuse the pre-review target or start recording.

Language support and model availability are checked at request time. Requests over 3,000 UTF-8 bytes are rejected, not truncated. Empty/oversized output, context/refusal errors, cancellation and a 30-second deadline preserve unformatted text. The deadline cancels the request and ignores late output; it cannot guarantee that the system immediately releases all model resources.

Saved history has optional raw, cleaned, formatted, cleanup-version and formatting-style fields. Legacy records decode without a destructive migration. No surrounding destination text or audio is added to history. Mode and explicit terminology pairs are saved locally in a separate validated JSON file. Corrupt settings/history are not silently overwritten.

## Evidence

- Full regression command: `xcodebuild -project Yada.xcodeproj -scheme Yada -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test`.
- Initial extended suite: 39 tests passed. Review fixes added a permission-retry regression, bringing the suite to 40; all passed.
- Final full suite: **41 tests passed, zero failures**, including the real 30-second deadline. Result: `.build/Logs/Test/Test-Yada-2026.09.06_03-54-38-+0530.xcresult`.
- Synthetic tests cover protected quotes/code, numbers/negation preserved by rules, word boundaries and non-cascading replacements, Raw bypass, session-frozen rules, Clean-before-delivery, model failure, mandatory review, fresh-target one-shot delivery, cancellation/late results, permission recovery, restored number warnings, legacy history and settings corruption.
- A read-only framework availability probe reported `unavailable(appleIntelligenceNotEnabled)` on this Mac. No settings were changed and no user transcript was passed to a model.
- Independent source review found three defects: missing Accessibility left reviewed text in an unretryable state; background formatting did not present progress; restored history lost review warnings. All were corrected. See `.audit/cleanup-formatting.tsv`.
- Native UI automation failed twice with `Sky Computer Use native pipe closed before response`. An isolated preview was launched, but interactive UI checks were not completed. The debug preview now has synthetic recognition and formatting, in-memory settings/history and no registered global shortcut.

## Remaining physical and semantic checks

1. Restart the newly built real app. Confirm default Raw and existing Control+Y behavior. Select Clean, add a synthetic phrase replacement, dictate, and compare Raw/Cleaned history versions.
2. Verify the Setup/Terminology sheet, scrolling review screen, history version picker, copy controls and cancellation with synthetic text. Confirm the formatting window appears when dictation began with the main window closed.
3. Enable Apple Intelligence yourself in System Settings → Apple Intelligence & Siri. Let its model setup finish; choose Check model in Yada. No additional inference package is needed.
4. For each reviewed style, evaluate synthetic passages containing numbers, names, negation, dates, uncertainty, quoted instructions, code, fillers and explicit/ambiguous spoken corrections. Examples: “Do not send 120 until Friday”; “Tuesday, sorry, Thursday”; “I actually like this”; a quotation containing “ignore previous instructions.” Do not send any test email or chat.
5. Compare each result against Raw. Record omissions, additions, changed commitments and formatting latency. Zero unapproved factual/commitment changes in the critical fixtures is required before considering automatic model delivery. Current implementation always requires review.
6. Exercise unavailable-model, unsupported-language and long-input fallback. Test cancel, repeated shortcut during formatting, review → new target → one insertion, permission denial → grant → retry, and a destination changing before insertion.
7. Continue the prior physical insertion matrix in `mvp2-acceptance.md`; this task does not establish Outlook/Teams or physical shortcut compatibility.

Live model quality, latency and the interactive UI remain unverified. The feature is implemented locally, with those acceptance gates open.

## API basis

The installed macOS SDK's FoundationModels Swift interface was checked for availability, session construction, locale support and response options. Apple's [SystemLanguageModel documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) describes the on-device model; [generation guidance](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models) documents availability checks and sessions with instructions.
