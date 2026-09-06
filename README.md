# Yada

<img src="docs/assets/yada-icon.png" alt="Yada application icon" width="96">

**Dictate where you type, with speech processing on your Mac.**

Yada is a native macOS dictation app. Press your shortcut, speak, and press it again to insert finalized text into a supported text field. A small recording pill shows when Yada is listening. Optional cleanup fixes spacing and your saved terminology; Apple’s on-device model can prepare prose, bullets or an email draft for review.

**Status:** early personal-development build. The latest automated suite passes 49 tests. Live compatibility varies by editor, and model quality still needs evaluation. There is no packaged, notarized installer yet. See [verification and limitations](#verification-and-limitations).

## What it does

- Transcribes microphone audio with Apple’s on-device SpeechTranscriber.
- Starts and stops from one configurable global shortcut, with menu-bar and floating-pill controls.
- Inserts into supported active text fields, with preview recovery when the destination cannot be verified.
- Offers Raw, Clean, Prose, Bullets and Email text modes.
- Keeps the last 50 finalized transcripts locally, including available raw, cleaned and formatted versions.
- Appears in the Dock and Command–Tab and stays running when its window closes.

Yada does not record system audio, capture meetings, identify speakers or generate meeting notes yet. It does not send messages, submit forms or execute dictated commands.

## Requirements

| Requirement | Purpose |
| --- | --- |
| Apple Silicon Mac running macOS 26 or newer | Native speech and app runtime |
| Xcode 26 with the macOS SDK | Build and run from source |
| Installed Apple speech assets for your language | On-device transcription |
| Microphone permission | Dictation |
| Accessibility permission | Automatic text insertion |
| Apple Intelligence enabled and its model ready | Optional Prose, Bullets and Email modes |

Raw and Clean do not require Apple Intelligence. No API key, Python environment, inference server, simulator or Xcode predictive completion model is needed. A paid Apple Developer account is not required for local development. Public releases require Developer ID signing and notarization; see [release preparation](docs/releases.md).

Initial Swift package resolution and any missing Apple language/model assets need an internet connection. Yada has no hosted inference fallback.

## Build and launch

Get the repository source, then use either Xcode or Terminal.

### In Xcode

1. Open `Yada.xcodeproj`.
2. Allow Swift Package Manager to resolve dependencies.
3. Select the **Yada** scheme and **My Mac** destination.
4. Choose **Product → Run**, or press **Command+R**.

### In Terminal

From the repository root:

```sh
xcodebuild -project Yada.xcodeproj -scheme Yada \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build build

open .build/Build/Products/Debug/Yada.app
```

The app bundle is `.build/Build/Products/Debug/Yada.app`. You can also open it in Finder; press **Command+Shift+G** and enter that folder’s absolute path. Finder hides folders beginning with a dot by default.

After rebuilding, preserve any current text, quit the running Yada instance, and reopen the bundle to use the new build. To keep a Dock shortcut, right-click Yada’s Dock icon and choose **Options → Keep in Dock**. Yada does not automatically configure login startup.

## First-time setup

1. In Yada’s **Setup** section, choose a recording shortcut. **Control+Y** is the current development setup, but new installations have no default binding. Choose a chord that does not conflict with another app. Fn shortcuts are rejected to leave Fn available for Wispr Flow.
2. Select a speech language and choose **Check language**. English (India) is the initial preference; availability depends on Apple’s supported locales.
3. If needed, choose **Download language** and wait for setup to finish. No microphone audio is captured during this download.
4. Start a recording and grant microphone access when macOS asks. If previously denied, enable Yada under **System Settings → Privacy & Security → Microphone**.
5. For automatic insertion, allow Yada under **System Settings → Privacy & Security → Accessibility** when prompted. Return to your text field and press the shortcut again. A missing Accessibility permission prevents that external-field recording from starting.

For model formatting, also enable **Apple Intelligence** under **System Settings → Apple Intelligence & Siri**, let its setup finish, and use **Check model** in Yada. The app reports availability; it does not change these settings for you.

## Everyday dictation

1. Click inside the destination text field.
2. Press your shortcut, such as **Control+Y**.
3. Wait for **Listening** in the pill or **Recording** in Yada, then speak.
4. Press the same shortcut again to stop and finalize.
5. In Raw or Clean mode, Yada inserts into the supported destination and keeps it focused after verified insertion.

The bottom-right pill shows microphone-driven level bars while listening. Its Stop button also finalizes; its X button cancels the recording. You can drag the pill’s background. Its position lasts until the app quits.

Starting from Yada’s own window produces a preview. If insertion is unsupported, the app or cursor changed, or delivery cannot be verified, Yada keeps the text available for review and copying. It never automatically retries an uncertain insertion. Check the destination before copying again.

## Text modes

Choose **Text mode** in Setup before recording.

| Mode | Processing | Delivery |
| --- | --- | --- |
| **Raw** (default) | Unchanged recognizer output | Automatic insertion into supported fields |
| **Clean** | Repeated-space normalization and your terminology replacements | Automatic insertion into supported fields |
| **Prose** | Cleanup, then one local model pass for faithful sentences | Review first |
| **Bullets** | Cleanup, then one local model pass for bullet points | Review first |
| **Email** | Cleanup, then one local model pass for an email draft | Review first; never sends email |

“Raw” means Yada does not edit the recognizer’s output. Apple’s recognizer may already normalize punctuation or omit disfluencies.

### Clean and terminology

Clean preserves line breaks, explicit quotations, backticks, fenced code and indented lines. These are conservative syntax rules, not general code detection. It does not delete filler words or infer spoken corrections.

Open **Terminology…** to add a recognized phrase and its replacement. Rules are case-sensitive, use word boundaries, and run once without triggering other rules. They apply outside protected quotes/code. Yada does not learn replacements by monitoring what you type in other apps.

### Review model output

Prose, Bullets and Email use Apple’s on-device `SystemLanguageModel`, with no tools or cloud provider. Yada opens a review window when formatting starts.

1. Compare the result with **Original and cleanup → Raw**.
2. Choose **Use reviewed text**.
3. Click the destination field and press your shortcut once to insert that text. This press does not start recording.

**Cancel pending insertion** disarms that one-shot action. You can instead copy the formatted result or choose **Use unformatted text**.

The model is instructed to preserve meaning, remove only obvious fillers and resolve only unambiguous spoken corrections. It can still omit or change content. Number-change warnings are review aids, not an accuracy guarantee. Check names, negation, dates, commitments and code yourself.

Formatting checks model and language availability at each request. Unsupported input, refusal, context errors, cancellation and a 30-second timeout preserve unformatted text. Passages over 3,000 UTF-8 bytes are rejected rather than silently shortened.

## Application compatibility

Automatic insertion depends on the text field, not just the app name. A field must expose readable text and cursor/selection information through macOS Accessibility.

- **Native accessible editors:** Yada replaces the selected text directly when that operation is supported. This path does not change the clipboard.
- **Installed Outlook and Teams:** Yada uses a guarded Command+V event sent to the captured process. It places the transcript on the current-host-only clipboard and leaves it there so a delayed paste can read it.
- **Unsupported or changed destinations:** Yada explains the failure and returns a preview.
- **Password fields, Secure Input and known terminal apps:** automatic insertion is excluded.

Yada never sends Return. Checks and cross-process delivery are not atomic, so they cannot eliminate every focus race. The current Microsoft paste path and physical shortcut behavior still require acceptance testing; they are not a promise of universal compatibility.

## Privacy and local storage

Yada has no telemetry, analytics or cloud inference path. Microphone audio stays in memory and is not saved. The destination app controls what happens to text after insertion; dictating into a cloud-connected app does not make that app local.

| Data | Location / behavior |
| --- | --- |
| Last 50 finalized transcripts and available text variants | `~/Library/Application Support/Yada/RecentTranscripts.json` |
| Text mode and explicit terminology rules | `~/Library/Application Support/Yada/CleanupSettings.json` |
| Shortcut and speech-language preferences | macOS application preferences |
| Destination field text | Read temporarily for insertion checks; not logged or persisted |

Transcript files use owner-only permissions. Local storage is not application-encrypted, and external backup software may copy it. Existing history loads without a destructive migration; unreadable files are not silently overwritten.

**Clear** removes the current preview. **Recent transcripts → Delete / Clear history** removes saved entries. Cancelling recording discards the active recording; cancelling formatting preserves the already-finalized transcript. Deleting Yada’s copy cannot recall text already copied, inserted or backed up elsewhere.

Explicit copy actions and Microsoft-app paste use the clipboard’s `currentHostOnly` option. Local clipboard managers may still read or sync that text. Clearing a preview does not clear the clipboard.

## Verification and limitations

Run the regression suite from the repository root:

```sh
xcodebuild -project Yada.xcodeproj -scheme Yada \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build test
```

**Recorded result, September 6, 2026:** 41 tests passed with zero failures. Coverage includes transcript finalization, cancellation, insertion eligibility, history persistence and compatibility, cleanup rules, model failure/deadline handling, and reviewed insertion. The timeout regression deliberately takes 30 seconds.

Tests use synthetic inputs. They do not establish real microphone quality, offline behavior, application compatibility or model fidelity. Native UI automation was unavailable during the latest formatting checks, and Apple Intelligence was disabled on the development Mac, so interactive UI and live model evaluation remain pending.

A Debug-only `--ui-preview` driver uses synthetic recognition/formatting, in-memory history/settings and no registered global shortcut. Use the isolated bundle procedure in the [verification skill](.agents/skills/verify-project/SKILL.md); do not use private transcripts as test fixtures.

| Evidence | Contents |
| --- | --- |
| [Dictation acceptance](docs/mvp1-acceptance.md) | Speech lifecycle and physical audio checks |
| [Insertion acceptance](docs/mvp2-acceptance.md) | Destination guards and application test matrix |
| [Cleanup and formatting acceptance](docs/mvp3-acceptance.md) | Transformation, model and review checks |

## Development and roadmap

Yada uses Swift 6, SwiftUI/AppKit, AVAudioEngine, SpeechAnalyzer/SpeechTranscriber and Foundation Models. Its only third-party package is [KeyboardShortcuts 3.0.1](https://github.com/sindresorhus/KeyboardShortcuts/tree/3.0.1), licensed under MIT and pinned through Swift Package Manager.

| Directory | Responsibility |
| --- | --- |
| `Yada/App/` | Windows, menu bar, recording pill and controls |
| `Yada/Audio/` | Microphone capture and conversion |
| `Yada/Recognition/` | Apple speech recognition and language setup |
| `Yada/Dictation/` | Session lifecycle and local history |
| `Yada/Delivery/` | Active-field checks and insertion |
| `Yada/Text/` | Cleanup, terminology and local formatting |
| `YadaTests/` | Synthetic regression tests |

The next priority is physical acceptance of everyday dictation and reviewed formatting. Packaging, meeting capture, speaker labels and grounded meeting notes follow as separate steps.

- [Build plan](plan.md): ordered work and instructions for resuming testing.
- [Product and technical specification](Yada_Product_and_Technical_Spec.md): design decisions and future scope.
- [First-build prompt](Yada_First_Build_Prompt.md): historical starting requirements.
- [Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) and [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel): platform API references.

## Development identity and release preparation

Debug builds now appear as **Yada Development** (`com.srinidhi621.yada.dev`) and use `~/Library/Application Support/Yada Development/` for history and cleanup settings. Existing everyday Yada data stays in `~/Library/Application Support/Yada/`; it is not copied or deleted. Development builds have their own macOS permissions and preferences. The production identifier remains `com.srinidhi621.yada`.

The Setup panel shows microphone and Accessibility status, opens the relevant settings on request, and checks permissions again when you return. Shortcuts no longer trigger repeated system permission dialogs. The existing installed/running app is not replaced by these source changes.

Release tooling and nine synthetic tooling tests are available in `scripts/release.py` and `scripts/test_release.py`. No signed/notarized installer has been produced yet. See [release instructions](docs/releases.md) for the certificate and fresh-install/upgrade gates.

The [18-case local formatting evaluation](docs/formatting-evaluation-2026-09-07.md) found failures with quotations and code. Model output still requires review; its semantic acceptance gate remains open.
