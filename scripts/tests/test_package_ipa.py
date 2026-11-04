import importlib.util
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

class IPAPackagingTests(unittest.TestCase):
    def packager(self):
        self.assertIsNotNone(importlib.util.find_spec('package_ipa'), 'IPA packager has not been implemented')
        import package_ipa
        return package_ipa

    def fixture(self, root, platform=2, cpu=0x0100000C):
        app = Path(root)/'LinYuIOS.app'; app.mkdir()
        info = {'CFBundleIdentifier':'org.linyu.prototype.livecontainer', 'CFBundleExecutable':'LinYuIOS',
                'CFBundleShortVersionString':'0.3.0', 'CFBundleVersion':'3', 'MinimumOSVersion':'16.0',
                'DTPlatformName':'iphoneos', 'CFBundleSupportedPlatforms':['iPhoneOS']}
        (app/'Info.plist').write_bytes(plistlib.dumps(info))
        # Synthetic Mach-O headers only. Never distributed as a build artifact.
        (app/'LinYuIOS').write_bytes(struct.pack('<8I',0xFEEDFACF,cpu,0,2,1,24,0,0)+struct.pack('<6I',0x32,24,platform,16<<16,16<<16,0))
        (app/'LinYuIOS').chmod(0o755)
        (app/'Assets.car').write_bytes(b'fixture-resource')
        return app

    def testDeviceAppProducesPayloadWithExecutableModeAndVerifiedReport(self):
        module = self.packager()
        with tempfile.TemporaryDirectory() as root:
            app = self.fixture(root); output=Path(root)/'app.ipa'
            report=module.package(app,output)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read('Payload/LinYuIOS.app/Assets.car'),b'fixture-resource')
                mode=archive.getinfo('Payload/LinYuIOS.app/LinYuIOS').external_attr>>16
                self.assertTrue(mode & stat.S_IXUSR)
            self.assertEqual(report['architecture'],'arm64')
            self.assertEqual(report['platform'],'iphoneos')
            self.assertEqual(len(report['sha256']),64)

    def testArm64SimulatorIsRejectedEvenWithDeviceInfoPlist(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root,platform=7)
            with self.assertRaisesRegex(ValueError,'platform'):
                module.package(app,Path(root)/'app.ipa')
            self.assertFalse((Path(root)/'app.ipa').exists())

    def testWrongCPUIsRejected(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError,'arm64'):
                module.package(self.fixture(root,cpu=0x01000007),Path(root)/'app.ipa')

    def testUnresolvedExecutableAndTraversalAreRejected(self):
        module=self.packager()
        for executable in ['$(EXECUTABLE_NAME)','../outside','/outside']:
            with self.subTest(executable=executable), tempfile.TemporaryDirectory() as root:
                app=self.fixture(root); info=plistlib.loads((app/'Info.plist').read_bytes())
                info['CFBundleExecutable']=executable; (app/'Info.plist').write_bytes(plistlib.dumps(info))
                with self.assertRaises(ValueError):module.package(app,Path(root)/'app.ipa')

    def testAppExtensionsAreNotAccidentallyIncluded(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root); (app/'PlugIns'/'Widget.appex').mkdir(parents=True)
            with self.assertRaisesRegex(ValueError,'extension'):
                module.package(app,Path(root)/'app.ipa')

    def testSimulatorPlistIsRejected(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root); info=plistlib.loads((app/'Info.plist').read_bytes()); info['DTPlatformName']='iphonesimulator'
            (app/'Info.plist').write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError,'iphoneos'): module.package(app,Path(root)/'app.ipa')

    def testMalformedLoadCommandsCannotProduceAnIPA(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root); binary=app/'LinYuIOS'; data=bytearray(binary.read_bytes()); struct.pack_into('<I',data,36,0); binary.write_bytes(data)
            with self.assertRaisesRegex(ValueError,'command'):module.package(app,Path(root)/'app.ipa')

    @unittest.skipIf(os.name=='nt','POSIX framework symlink fixture runs on macOS')
    def testFrameworkSymlinkIsPreservedAndCannotEscapeBundle(self):
        module=self.packager()
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root); (app/'Frameworks').mkdir(); (app/'Frameworks'/'inside').symlink_to('../Assets.car')
            output=Path(root)/'app.ipa';module.package(app,output)
            with zipfile.ZipFile(output) as archive:
                item=archive.getinfo('Payload/LinYuIOS.app/Frameworks/inside')
                self.assertTrue(stat.S_ISLNK(item.external_attr>>16));self.assertEqual(archive.read(item),'../Assets.car'.encode())
            (app/'Frameworks'/'outside').symlink_to('../../secret')
            with self.assertRaisesRegex(ValueError,'symlink'):module.package(app,Path(root)/'bad.ipa')

if __name__=='__main__':unittest.main()
