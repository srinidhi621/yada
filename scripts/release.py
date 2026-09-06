#!/usr/bin/env python3
"""Explicit local release stages. Only `notarize` submits an artifact to Apple."""
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = 'com.srinidhi621.yada'


def run(*args):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}):\n{result.stdout}')
    return result.stdout


def version_info():
    with (ROOT / 'Yada/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise RuntimeError('Info.plist release version must be three numeric components.')
    if not re.fullmatch(r'[1-9]\d*', build):
        raise RuntimeError('Info.plist build number must be a positive integer.')
    return version, build


def choose_identity(output, team):
    if not team or not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise RuntimeError('Supply --team with your 10-character Apple Developer Team ID.')
    matches = re.findall(r'([A-Fa-f0-9]{40}) "(Developer ID Application: [^"\n]+)"', output)
    identities = [(fingerprint, name) for fingerprint, name in matches if name.endswith(f'({team})')]
    if len(identities) != 1:
        raise RuntimeError(f'Expected one valid Developer ID Application identity for team {team}; '
                           f'found {len(identities)}. Install/select the intended certificate and private key in Keychain.')
    return identities[0]


def preflight(team):
    print(run('xcodebuild', '-version').strip())
    version, build = version_info()
    print(f'Yada {version} ({build}); Apple Silicon; macOS 26 minimum')
    identity, name = choose_identity(run('security', 'find-identity', '-v', '-p', 'codesigning'), team)
    print(f'Signing: {name}')
    return version, build, identity


def verify_signature(path, team, app=False):
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', path)
    details = run('codesign', '-d', '--verbose=4', path)
    if f'TeamIdentifier={team}\n' not in details or 'Authority=Developer ID Application:' not in details:
        raise RuntimeError(f'{path.name}: wrong signing team or certificate; ad-hoc builds cannot be distributed.')
    if 'Timestamp=' not in details:
        raise RuntimeError(f'{path.name}: missing secure timestamp.')
    if app:
        if '(runtime)' not in details:
            raise RuntimeError('Hardened runtime is missing.')
        # codesign writes its human-readable header to stderr; locate the XML payload.
        output = run('codesign', '-d', '--entitlements', ':-', path)
        start = output.find('<?xml')
        if start < 0:
            raise RuntimeError('Signed app has no XML entitlements.')
        entitlements = plistlib.loads(output[start:].encode())
        if entitlements.get('com.apple.security.device.audio-input') is not True:
            raise RuntimeError('Microphone hardened-runtime entitlement is missing.')
        if entitlements.get('com.apple.security.get-task-allow'):
            raise RuntimeError('Release must not permit debugger attachment.')


def build_release(team):
    version, build, identity = preflight(team)
    directory = ROOT / '.build/releases' / f'{version}-{build}'
    directory.mkdir(parents=True, exist_ok=False)
    derived = directory / 'DerivedData'
    common = ['xcodebuild', '-project', 'Yada.xcodeproj', '-scheme', 'Yada',
              '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', derived,
              '-onlyUsePackageVersionsFromResolvedFile']
    for phase, command in [
        ('tests', common + ['-configuration', 'Debug', 'test']),
        ('build', common + ['-configuration', 'Release', 'build',
                           'CODE_SIGN_STYLE=Manual', f'CODE_SIGN_IDENTITY={identity}',
                           f'DEVELOPMENT_TEAM={team}', 'ENABLE_HARDENED_RUNTIME=YES',
                           'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
                           'OTHER_CODE_SIGN_FLAGS=--timestamp',
                           f'CODE_SIGN_ENTITLEMENTS={ROOT / "config/release.entitlements"}'])
    ]:
        print(f'Running {phase}...', flush=True)
        try:
            output = run(*command)
        except RuntimeError as error:
            (directory / f'{phase}.log').write_text(str(error))
            raise
        (directory / f'{phase}.log').write_text(output)
    app = derived / 'Build/Products/Release/Yada.app'
    with (app / 'Contents/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (BUNDLE_ID, version, build):
        raise RuntimeError('Built app identity/version differs from release metadata.')
    verify_signature(app, team, app=True)
    stage = directory / 'DMG'
    stage.mkdir()
    run('ditto', app, stage / 'Yada.app')
    (stage / 'Applications').symlink_to('/Applications')
    dmg = directory / f'Yada-{version}-{build}-arm64.dmg'
    run('hdiutil', 'create', '-volname', 'Yada', '-srcfolder', stage, '-format', 'UDZO', dmg)
    run('codesign', '--sign', identity, '--timestamp', dmg)
    verify_signature(dmg, team)
    print(f'Signed, NOT notarized: {dmg}\nDo not distribute until notarization and physical acceptance pass.')


def notarize(dmg, team, profile):
    dmg = dmg.resolve()
    if not dmg.is_file() or dmg.suffix != '.dmg':
        raise RuntimeError('Supply an existing signed .dmg.')
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise RuntimeError('Invalid Apple Developer Team ID.')
    verify_signature(dmg, team)
    response = json.loads(run('xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', profile,
                              '--wait', '--output-format', 'json'))
    (dmg.parent / f'{dmg.stem}-notarization.json').write_text(json.dumps(response, indent=2) + '\n')
    if response.get('status') != 'Accepted':
        raise RuntimeError(f'Notarization not accepted: {response.get("status")}; review submission {response.get("id")}.')
    run('xcrun', 'stapler', 'staple', dmg)
    run('xcrun', 'stapler', 'validate', dmg)
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
    checksum = hashlib.sha256()
    with dmg.open('rb') as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b''):
            checksum.update(chunk)
    digest = checksum.hexdigest()
    dmg.with_suffix('.dmg.sha256').write_text(f'{digest}  {dmg.name}\n')
    print(f'Notarized and stapled: {dmg}\nPhysical installation and upgrade checks are still required. Nothing was published.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('preflight', 'build'):
        command = commands.add_parser(name)
        command.add_argument('--team', required=True)
    command = commands.add_parser('notarize', help='Uploads the signed DMG to Apple; requires explicit release authorization.')
    command.add_argument('dmg', type=Path)
    command.add_argument('--team', required=True)
    command.add_argument('--profile', required=True, help='Existing notarytool Keychain profile; never pass a password.')
    args = parser.parse_args()
    try:
        if args.command == 'preflight':
            preflight(args.team)
        elif args.command == 'build':
            build_release(args.team)
        else:
            notarize(args.dmg, args.team, args.profile)
    except (RuntimeError, OSError, ValueError) as error:
        parser.exit(1, f'Release stopped: {error}\n')


if __name__ == '__main__':
    main()
