# Signed releases and installation

Yada's release app keeps bundle identifier `com.srinidhi621.yada` and installs at `/Applications/Yada.app`. Debug builds use `com.srinidhi621.yada.dev` and separate development storage. Use the installed release for everyday dictation; rebuilding development copies should not replace its identity or permissions.

The scripts prepare local artifacts. They do not create certificates, change privacy settings, upload to GitHub, or update a user's installed app. Only the explicitly invoked `notarize` command uploads a DMG to Apple. A successful package build is **not** a completed release.

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

## Required acceptance before sharing

- Install the notarized DMG on a second Mac with no prior Yada installation. Check Gatekeeper launch, Applications drag installation, microphone and Accessibility guidance, language assets, menu bar and shortcut.
- Use only synthetic text in TextEdit, Notes, Teams chat compose and Outlook email body. Verify stop/paste, focus protection and Undo without sending a message.
- Install one signed version, grant permissions, create synthetic settings/history, then replace it with a second signed version from the same publisher. Verify permissions, settings and history survive.
- Confirm Apple Intelligence unavailable/unsupported-language paths preserve Raw and Clean dictation; model formatting remains optional and reviewed.
- Test offline launch of the installed notarized app and preserve the final artifact's checksum.

Existing ad-hoc users may need a one-time permission repair when moving to the signed release. Normal upgrades should preserve authorization with a consistent identity, but this is an acceptance criterion to demonstrate, not a guarantee established by unit tests.

## Current evidence

The tooling's nine isolated tests cover certificate/team selection, metadata rejection, signed entitlement validation, failure gates, and notarization result handling. They use mocked signing/notarization commands and never upload artifacts. On this development Mac, preflight remains blocked by the absence of a valid Developer ID Application identity. Signed packaging, notarization and fresh-install/upgrade acceptance await account setup. No ad-hoc distributable was produced.

An isolated local-only Release smoke build also passed with hardened runtime and the microphone entitlement, using ad-hoc signing solely for compilation validation. This is not a distributable release and does not verify Developer ID signing, timestamping, notarization or Gatekeeper acceptance. Final Debug metadata is `com.srinidhi621.yada.dev` / `Yada Development`; Release is `com.srinidhi621.yada` / `Yada`.
