"""Package a compiled physical-iPhone app; never compiles source or fakes an IPA."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import zipfile

def device_architecture(executable):
    with executable.open('rb') as stream:
        header=stream.read(32)
        if len(header)!=32: raise ValueError('Invalid Mach-O header')
        magic,cpu,_,filetype,count,size,_,_=struct.unpack('<8I',header)
        if magic!=0xFEEDFACF or cpu!=0x0100000C or filetype!=2:
            raise ValueError('Expected a thin arm64 executable')
        if size>1024*1024 or count>16384: raise ValueError('Invalid load command bounds')
        commands=stream.read(size)
        if len(commands)!=size: raise ValueError('Truncated load commands')
    platform=None;offset=0
    for _ in range(count):
        if offset+8>size: raise ValueError('Truncated load command')
        command,length=struct.unpack_from('<2I',commands,offset)
        if length<8 or offset+length>size: raise ValueError('Invalid load command length')
        if command==0x32:
            if length<24: raise ValueError('Invalid platform command')
            platform=struct.unpack_from('<I',commands,offset+8)[0]
        offset+=length
    if offset!=size: raise ValueError('Invalid load command size')
    if platform!=2: raise ValueError('Mach-O platform must be physical iOS, not simulator/macOS')
    return 'arm64'

def package(app,output):
    app=Path(app).resolve();output=Path(output).resolve()
    if app.suffix!='.app' or not app.is_dir(): raise ValueError('Expected compiled .app directory')
    info=plistlib.loads((app/'Info.plist').read_bytes())
    if info.get('DTPlatformName')!='iphoneos' or 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms',[]):
        raise ValueError('Info.plist must identify an iphoneos build')
    executable=info.get('CFBundleExecutable','')
    if not executable or Path(executable).name!=executable or '/' in executable or '\\' in executable or '$' in executable:
        raise ValueError('Invalid or unresolved executable name')
    if not info.get('CFBundleIdentifier') or '$' in info['CFBundleIdentifier']: raise ValueError('Unresolved bundle ID')
    architecture=device_architecture(app/executable)
    items=sorted(app.rglob('*'))
    for path in items:
        if path.suffix in {'.appex','.xctest'}: raise ValueError('LiveContainer package must not include app/test extensions')
        if path.is_symlink() and not path.resolve().is_relative_to(app): raise ValueError('Bundle symlink escapes app')
    if output.is_relative_to(app): raise ValueError('Output must be outside app')
    output.parent.mkdir(parents=True,exist_ok=True)
    temporary=output.with_suffix('.ipa.tmp');members={}
    try:
        with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
            for path in items:
                if path.is_dir() and not path.is_symlink(): continue
                name='Payload/'+app.name+'/'+path.relative_to(app).as_posix()
                data=os.readlink(path).encode('utf-8') if path.is_symlink() else path.read_bytes()
                item=zipfile.ZipInfo(name);item.create_system=3
                mode=(stat.S_IFLNK|0o777) if path.is_symlink() else (stat.S_IFREG|(0o755 if path.name==executable or path.stat().st_mode&stat.S_IXUSR else 0o644))
                item.external_attr=mode<<16;item.compress_type=zipfile.ZIP_DEFLATED
                archive.writestr(item,data);members[name]=hashlib.sha256(data).hexdigest()
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None: raise ValueError('IPA CRC failed')
            for name,digest in members.items():
                if hashlib.sha256(archive.read(name)).hexdigest()!=digest: raise ValueError('IPA member hash mismatch')
        temporary.replace(output)
    finally:
        if temporary.exists(): temporary.unlink()
    return {'file':output.name,'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'architecture':architecture,'platform':'iphoneos','bundle_id':info['CFBundleIdentifier'],
            'version':info.get('CFBundleShortVersionString'),'build':info.get('CFBundleVersion'),
            'minimum_ios':info.get('MinimumOSVersion'),'sdk':info.get('DTSDKName'),'xcode':info.get('DTXcode'),
            'signature':'ad-hoc (LiveContainer supplies launch signing)','crc_and_member_hashes_verified':True,'members':members}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args();report=package(args.app,args.output)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    args.output.with_suffix('.ipa.sha256').write_text(report['sha256']+'  '+args.output.name+'\n',encoding='ascii')
    print(json.dumps({k:v for k,v in report.items() if k!='members'},indent=2))

if __name__=='__main__': main()
