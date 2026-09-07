#!/usr/bin/env python3
"""Build a non-notarized testing DMG. Does not install, upload or alter permissions."""
import hashlib
import plistlib
import tempfile
from pathlib import Path

from release import ROOT, BUNDLE_ID, run, version_info


def main():
    version, build = version_info()
    output = ROOT / '.build/local-packages'
    output.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix=f'{version}-{build}-', dir=output))
    common = ['xcodebuild', '-project', 'Yada.xcodeproj', '-scheme', 'Yada',
              '-destination', 'platform=macOS,arch=arm64',
              '-derivedDataPath', directory / 'DerivedData',
              '-onlyUsePackageVersionsFromResolvedFile']
    for name, arguments in [
        ('tests', ['-configuration', 'Debug', 'test']),
        ('build', ['-configuration', 'Release', 'build', 'CODE_SIGN_STYLE=Manual',
                   'CODE_SIGN_IDENTITY=-', 'DEVELOPMENT_TEAM=',
                   'ENABLE_HARDENED_RUNTIME=YES', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO',
                   f'CODE_SIGN_ENTITLEMENTS={ROOT / "config/release.entitlements"}'])
    ]:
        print(f'Running {name}; logs: {directory}', flush=True)
        try:
            result = run(*common, *arguments)
        except RuntimeError as error:
            (directory / f'{name}.log').write_text(str(error))
            raise
        (directory / f'{name}.log').write_text(result)
    app = directory / 'DerivedData/Build/Products/Release/Yada.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID:
        raise RuntimeError('Local package must use the production bundle identity.')
    run('codesign', '--verify', '--deep', '--strict', app)
    stage = directory / 'DMG'
    stage.mkdir()
    run('ditto', app, stage / 'Yada.app')
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'READ ME.txt').write_text(
        'Yada — local testing build, not notarized by Apple.\n\n'
        'Requires Apple Silicon and macOS 26.\n'
        'Quit any running Yada copy. Drag Yada to Applications, replacing the old copy.\n'
        'Eject this disk and open Yada from Applications. Use this installed copy only.\n'
        'If macOS blocks opening, use Privacy & Security > Open Anyway for Yada,\n'
        'only if you trust this download. Managed Macs may not allow this.\n'
        'Grant microphone and Accessibility access when needed.\n'
        'Click a text field, press Control-Y, speak, and press Control-Y again.\n\n'
        'This build uses ad-hoc signing. Upgrades may require permission repair.\n'
        'Installing does not delete your history or recordings.\n'
    )
    dmg = directory / f'Yada-{version}-{build}-arm64-local.dmg'
    run('hdiutil', 'create', '-volname', 'Yada Local Test', '-srcfolder', stage, '-format', 'UDZO', dmg)
    run('hdiutil', 'verify', dmg)
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    dmg.with_suffix('.dmg.sha256').write_text(f'{digest}  {dmg.name}\n')
    print(f'Local test DMG (NOT notarized): {dmg}\nNo installation or upload performed.')


if __name__ == '__main__':
    main()
