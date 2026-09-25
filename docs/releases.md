# Installation and optional signed releases

Yada's release app keeps bundle identifier `com.srinidhi621.yada` and installs at `/Applications/Yada.app`. Debug builds use `com.srinidhi621.yada.dev` and separate development storage. Use the installed release for everyday dictation; rebuilding development copies should not replace its identity or permissions.

The scripts prepare local artifacts. They do not create certificates, change privacy settings, upload to GitHub, or update a user's installed app. Only the explicitly invoked `notarize` command uploads a DMG to Apple. A successful package build is **not** a completed release.

## Local testing without paid enrollment — current path

Apple Developer enrollment is deferred. From the repository root, run:

```sh
python3 scripts/package-local.py
```

This runs the isolated tests, builds the production bundle with ad-hoc signing and the microphone entitlement, verifies its signature, and creates a clearly labelled non-notarized DMG plus SHA-256 file under `.build/local-packages/`. Each run has a fresh output directory. No certificate, installation, privacy reset or upload is performed. Ad-hoc signatures do not provide Apple-verified publisher identity.

1. Quit Yada through its menu-bar menu. Preserve any unfinished text first.
2. Open the generated DMG and drag Yada onto Applications. Replace an existing Yada there; do not keep a second copy under another name.
3. Eject the disk image and open `/Applications/Yada.app`. Remove any old Dock shortcut pointing into the development folder and keep the installed app in the Dock instead.
4. If macOS blocks this trusted testing build, use its per-app **Privacy & Security → Open Anyway** action. Do not disable Gatekeeper globally. Managed Macs may prevent this exception.
5. For stale duplicate Accessibility rows, quit Yada, remove only the old Yada entries with the minus button, then add `/Applications/Yada.app` with the plus button and enable it. Reopen the installed app. This is user-managed permission repair, not an app preference reset; preserve Application Support folders and all other apps' grants.
6. Complete the microphone/language setup if requested, then test Control-Y twice in an empty TextEdit document before testing Notes, Outlook and Teams. No mouse interaction with the pill should be needed.

This procedure consolidates the installation but does not guarantee permission retention across ad-hoc rebuilds. Record relaunch/upgrade results before sharing even with a controlled tester. Existing development history remains in its separate folder; this procedure does not migrate or delete it. The first shareable product is core dictation; the Meetings tab and model formatting are not part of its acceptance gate.

The certificate-based workflow below is optional and deferred. Its stricter checks apply to notarized releases, not the local testing DMG.

## One-time publisher setup

1. Enroll in the Apple Developer Program using the intended publisher account. Record its 10-character Team ID.
2. Create a **Developer ID Application** certificate and its private key in the signing Mac's Keychain. Keep exactly one intended valid identity for this team available to the build. Do not use ad-hoc, Apple Development, Mac App Distribution, or a self-signed certificate for downloadable releases.
3. Store notarization credentials in a named Keychain profile using Apple's interactive `xcrun notarytool store-credentials` flow. Never commit certificates, private keys, passwords, or exported Keychain data. This tooling accepts a profile name rather than a password.
4. Back up the signing identity securely through the account owner's approved process. Keep the same publisher/team and bundle identifier across upgrades; test permissions when certificates rotate. Signing does not grant Accessibility or microphone access on a user's behalf.

Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/) and [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The app enables hardened runtime and declares only its audio-input entitlement in `config/release.entitlements`. Runtime signing checks also reject debugger entitlements and missing timestamps.

## Local preparation

Run from this repository on Apple Silicon with Xcode and the macOS 26 SDK. Python 3 uses only its standard library. Substitute your actual Team ID for `YOURTEAMID`.

```sh
python3 -m unittest discover -s scripts -p test_release.py
python3 scripts/release.py preflight --team YOURTEAMID
```

Preflight checks Xcode, numeric app version/build metadata, and the intended valid Developer ID identity. A missing identity is a stopping condition, not permission to package an ad-hoc app. It does not inspect private-key material. It cannot prove enrollment status or successful notarization.

Before each release, update `CFBundleShortVersionString` and `CFBundleVersion` in `Yada/Info.plist`; use three numeric version components and a positive, increasing build number. Compare with the previous published release manually. The script validates syntax and the built app's metadata; it does not query GitHub or enforce monotonicity against remote releases.

```sh
python3 scripts/release.py build --team YOURTEAMID
```

The build stage:

1. Runs preflight before creating artifacts.
2. Runs the deterministic Xcode test suite with the locked Swift package versions in an isolated DerivedData directory.
3. Builds Release using the chosen certificate, team, secure timestamp, hardened runtime, and microphone entitlement.
4. Checks app signature, team, entitlements, bundle ID and version.
5. Creates a signed compressed DMG containing Yada and an Applications shortcut.

Artifacts and test/build logs are under `.build/releases/<version>-<build>/`. Existing directories are never overwritten; after a failed run, inspect its logs and move that artifact directory aside before retrying. Tests do not grant permissions or exercise a real microphone. Xcode may fetch locked source packages and signing obtains Apple's timestamp over the network. No app user data is included in packaging.

## Notarization — separate authorized action

Run only when the account is configured and the publisher authorizes submission. Example paths must match the actual release version:

```sh
python3 scripts/release.py notarize .build/releases/0.1.0-1/Yada-0.1.0-1-arm64.dmg --team YOURTEAMID --profile yada-notary
```

This verifies the DMG signature/team, submits it to Apple, saves the response, requires `Accepted`, staples and validates the ticket, checks Gatekeeper, and writes a SHA-256 checksum. The final stapled DMG is the distribution artifact; do not distribute the unstapled build app separately. If submission is interrupted, inspect its status with Apple's tools before retrying; this simple script does not automatically resume interrupted submissions.

Nothing is published to GitHub. Publishing the DMG, checksum and release notes remains an explicitly authorized GitHub release operation.

## Required acceptance before a completed release

- Install the notarized DMG on a second Mac with no prior Yada installation. Check Gatekeeper launch, Applications drag installation, microphone and Accessibility guidance, language assets, menu bar and shortcut.
- Use only synthetic text in TextEdit, Notes, Teams chat compose and Outlook email body. Verify stop/paste, focus protection and Undo without sending a message.
- Install one signed version, grant permissions, create synthetic settings/history, then replace it with a second signed version from the same publisher. Verify permissions, settings and history survive.
- Confirm Apple Intelligence unavailable/unsupported-language paths preserve Raw and Clean dictation; model formatting remains optional and reviewed.
- Test offline launch of the installed notarized app and preserve the final artifact's checksum.

Existing ad-hoc users may need a one-time permission repair when moving to the signed release. Normal upgrades should preserve authorization with a consistent identity, but this is an acceptance criterion to demonstrate, not a guarantee established by unit tests.

## Current evidence

The tooling's nine isolated tests cover certificate/team selection, metadata rejection, signed entitlement validation, failure gates, and notarization result handling. They use mocked signing/notarization commands and never upload artifacts. On this development Mac, preflight remains blocked by the absence of a valid Developer ID Application identity. Developer ID packaging and notarization are deferred. The credential-free local testing package below has been produced; its installation and upgrade checks remain pending.

An isolated local-only Release smoke build also passed with hardened runtime and the microphone entitlement, using ad-hoc signing solely for compilation validation. This is not a distributable release and does not verify Developer ID signing, timestamping, notarization or Gatekeeper acceptance. Final Debug metadata is `com.srinidhi621.yada.dev` / `Yada Development`; Release is `com.srinidhi621.yada` / `Yada`.

## Duplicate-instance migration

Updated app builds refuse a second production/development instance before registering the global shortcut. They also use a shared process lock. This does not delete existing macOS Accessibility rows, transfer a grant between bundle IDs, or make ad-hoc signatures stable. The September 7 audit found two running copies and no valid signing identity. Use one production install at `/Applications/Yada.app` for everyday testing; paid signing is deferred and ad-hoc update permission repair remains possible; stop directing everyday users to different DerivedData copies. Existing stale grants require user-managed cleanup during that migration. Never write the TCC database or use a bundle-ID-only ad-hoc signing requirement to bypass identity checks.

### Local package evidence, September 7

`package-local.py` completed on September 7: 62 app tests passed, Release built, app signature verification passed, and `hdiutil verify` accepted the generated DMG. On September 25, Xcode independently passed the same 62 synthetic app tests on macOS 26.7, and ten Python tooling tests passed. Packaging was not rerun on September 25. The artifact is non-notarized. No installed-app launch, cross-app dictation or permission persistence was established by these checks.

Source and documentation for the local workflow are on `main`. The generated DMG remains local at `.build/local-packages/0.1.0-1-sy9tj63b/Yada-0.1.0-1-arm64-local.dmg`; it is not stored in Git. Installed-app dictation and second-Mac acceptance remain pending. Start with the installation steps above and the ordered checklist in `plan.md`.

### Updated local build, September 25

After the shortcut lifecycle fix, Xcode passed 63 app tests and built a production-ID Release app. The copy at `.build/shortcut-fix-package/Yada.app` has a verified ad-hoc hardened-runtime signature and microphone entitlement. Its archive at `.build/shortcut-fix-package/Yada-0.1.0-1-arm64-local.zip` passed ZIP integrity checking; the adjacent `.sha256` file records its checksum. The workspace denied both DMG creation and installation at `/Applications/Yada.app`; do not use the older DMG to test this fix.

For a single unambiguous app, use `.build/ready-to-install/Yada.app` directly. This folder contains only that app; there is no archive to extract. In Finder, use **Go → Go to Folder** to open `.build/ready-to-install/` under this repository. Quit every running Yada copy, move any extra `Yada 2.app` from Applications to Trash, and drag this `Yada.app` to Applications. Choose **Replace** if Finder finds an existing `/Applications/Yada.app`. Launch only `/Applications/Yada.app`, then follow steps 4–6 above for Gatekeeper, user-managed permissions, and a TextEdit Control-Y trial. Finder can name a second ZIP extraction `Yada 2.app` when an earlier extraction sits beside it; do not install that extra copy. The app refuses to run from a build folder so new Accessibility requests use the installed location. Do not delete application data or grant unrelated apps access. This local build is not a shareable finished release until physical dictation and insertion pass.
