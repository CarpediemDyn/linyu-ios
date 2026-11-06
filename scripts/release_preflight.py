"""Cheap release checks. No Xcode, network, device commands or IPA creation."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct

ROOT = Path(__file__).resolve().parents[1]


def check():
    app = plistlib.loads((ROOT / 'LinYuIOS/Info.plist').read_bytes())
    widget = plistlib.loads((ROOT / 'LinYuWidgets/Info.plist').read_bytes())
    version = app['CFBundleShortVersionString']
    build = app['CFBundleVersion']
    assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Invalid release version'
    assert re.fullmatch(r'[1-9]\d*', build), 'Invalid build number'
    assert widget['CFBundleShortVersionString'] == version, 'Widget/app version mismatch'
    assert widget['CFBundleVersion'] == build, 'Widget/app build mismatch'
    assert app['CFBundleDisplayName'] == '淋浴', 'Unexpected application rename'
    assert {'NSBluetoothAlwaysUsageDescription', 'NSCameraUsageDescription'} <= app.keys()
    assert 'bluetooth-central' in app['UIBackgroundModes']
    assert len(app['UISupportedInterfaceOrientations']) >= 3
    assert len(app['UISupportedInterfaceOrientations~ipad']) == 4

    configs = [(ROOT / name).read_text(encoding='utf-8') for name in ['project.yml', 'project-livecontainer.yml']]
    for config in configs:
        assert 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' in config
        assert 'IPHONEOS_DEPLOYMENT_TARGET: "16.0"' in config
        assert 'TARGETED_DEVICE_FAMILY: "1,2"' in config
        assert 'path: CoreTests' in config
    assert 'org.linyu.prototype.app' in configs[0]
    assert 'org.linyu.prototype.livecontainer' in configs[1]
    assert 'LinYuWidgets:' not in configs[1], 'LiveContainer must not embed a Widget extension'

    catalogs = list((ROOT / 'LinYuIOS/Assets.xcassets').rglob('Contents.json'))
    referenced_files = 0
    for contents in catalogs:
        data = json.loads(contents.read_text(encoding='utf-8'))
        for image in data.get('images', []):
            if 'filename' not in image:
                continue
            file = (contents.parent / image['filename']).resolve()
            assert file.parent == contents.parent.resolve() and file.is_file(), str(file)
            referenced_files += 1
            if contents.parent.name != 'AppIcon.appiconset':
                continue
            png = file.read_bytes()
            assert png[:8] == b'\x89PNG\r\n\x1a\n' and png[12:16] == b'IHDR'
            width, height = struct.unpack('>II', png[16:24])
            expected_width, expected_height = map(float, image['size'].split('x'))
            scale = float(image['scale'][:-1])
            assert (width, height) == (expected_width * scale, expected_height * scale), file.name
            assert png[25] in [0, 2], 'AppIcon must not have alpha'

    icons = json.loads((ROOT / 'docs/ui-parity/ICON_SOURCES.json').read_text(encoding='utf-8'))
    for icon in icons:
        file = ROOT / ('LinYuIOS/Assets.xcassets/Android_' + icon['name'] + '.imageset/icon.svg')
        # Git's Windows checkout may use CRLF; the provenance hash records the LF blob.
        assert hashlib.sha256(file.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == icon['svg_sha256'], icon['name']
    assert 'MIT License' in (ROOT / 'LICENSE').read_text(encoding='utf-8')
    assert 'Cra3y' in (ROOT / 'NOTICE.md').read_text(encoding='utf-8')
    assert 'yehu-imei' in (ROOT / 'NOTICE.md').read_text(encoding='utf-8')
    result = {'version': version, 'build': build, 'minimum_ios': '16.0',
              'asset_catalogs': len(catalogs), 'resource_references': referenced_files,
              'verified_svg_hashes': len(icons), 'status': 'passed'}
    print(json.dumps(result, ensure_ascii=False))
    return result


if __name__ == '__main__':
    check()
