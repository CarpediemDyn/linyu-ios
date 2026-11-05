"""Preserve VectorDrawable geometry as template SVG asset catalogs (no raster tracing)."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET

ANDROID = '{http://schemas.android.com/apk/res/android}'
MATERIAL = {
    'home': 'action/home', 'person': 'social/person', 'settings': 'action/settings',
    'refresh': 'navigation/refresh', 'arrow_back': 'navigation/arrow_back',
    'arrow_forward': 'navigation/arrow_forward', 'arrow_upward': 'navigation/arrow_upward',
    'arrow_downward': 'navigation/arrow_downward', 'close': 'navigation/close',
    'phone': 'communication/phone', 'lock': 'action/lock', 'check': 'navigation/check',
    'edit': 'image/edit', 'search': 'action/search', 'error': 'alert/error',
    'bluetooth': 'device/bluetooth', 'info': 'action/info',
    'expand_less': 'navigation/expand_less', 'expand_more': 'navigation/expand_more',
    'chevron_right': 'navigation/chevron_right', 'share': 'social/share',
    'delete': 'action/delete', 'file_download': 'file/file_download',
    'keyboard_arrow_right': 'hardware/keyboard_arrow_right',
    'keyboard_arrow_down': 'hardware/keyboard_arrow_down',
    'keyboard_arrow_up': 'hardware/keyboard_arrow_up',
}

def paint(value):
    value = value.removeprefix('#')
    if len(value) == 8:
        return '#' + value[2:], str(int(value[:2], 16) / 255)
    if len(value) == 6:
        return '#' + value, '1'
    raise ValueError('Unsupported drawable paint: ' + value)

def vector_svg(data):
    source = ET.fromstring(data)
    width, height = source.get(ANDROID+'viewportWidth'), source.get(ANDROID+'viewportHeight')
    if source.tag != 'vector' or not width or not height:
        raise ValueError('Expected a vector with viewport')
    root = ET.Element('svg', xmlns='http://www.w3.org/2000/svg', viewBox=f'0 0 {width} {height}', width=width, height=height)
    def children(node, parent):
        for child in node:
            if child.tag == 'group':
                def value(key, default): return child.get(ANDROID+key, default)
                px, py = value('pivotX','0'), value('pivotY','0')
                transforms = f"translate({value('translateX','0')} {value('translateY','0')}) translate({px} {py}) rotate({value('rotation','0')}) scale({value('scaleX','1')} {value('scaleY','1')}) translate(-{px} -{py})"
                group = ET.SubElement(parent,'g',transform=transforms)
                children(child,group)
            elif child.tag == 'path':
                path = ET.SubElement(parent,'path',d=child.attrib[ANDROID+'pathData'])
                for kind in ['fill','stroke']:
                    color = child.get(ANDROID+kind+'Color')
                    if color:
                        hexcolor, alpha = paint(color)
                        path.set(kind,hexcolor)
                        path.set(kind+'-opacity',str(float(alpha)*float(child.get(ANDROID+kind+'Alpha','1'))))
                    else: path.set(kind,'none')
                for src, dst in [('strokeWidth','stroke-width'),('strokeLineCap','stroke-linecap'),('strokeLineJoin','stroke-linejoin'),('strokeMiterLimit','stroke-miterlimit')]:
                    if ANDROID+src in child.attrib: path.set(dst,child.attrib[ANDROID+src])
                if child.get(ANDROID+'fillType') == 'evenOdd': path.set('fill-rule','evenodd')
            else:
                raise ValueError('Unsupported drawable node: '+child.tag)
    children(source,root)
    return ET.tostring(root,encoding='utf-8',xml_declaration=True)

def write_asset(output,name,svg):
    ET.fromstring(svg)
    folder = output/('Android_'+name+'.imageset'); folder.mkdir(parents=True,exist_ok=True)
    (folder/'icon.svg').write_bytes(svg)
    content={'images':[{'filename':'icon.svg','idiom':'universal'}], 'info':{'author':'xcode','version':1}, 'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}}
    (folder/'Contents.json').write_text(json.dumps(content,indent=2)+'\n',encoding='utf-8')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--android-root',type=Path,required=True);parser.add_argument('--output',type=Path,default=Path('LinYuIOS/Assets.xcassets'))
    args=parser.parse_args();records=[]
    for source in sorted((args.android_root/'app/src/main/res/drawable').glob('ic_*.xml')):
        data=source.read_bytes();svg=vector_svg(data);write_asset(args.output,source.stem,svg)
        records.append({'name':source.stem,'source':source.relative_to(args.android_root).as_posix(),'source_sha256':hashlib.sha256(data).hexdigest(),'svg_sha256':hashlib.sha256(svg).hexdigest()})
    for name,path in MATERIAL.items():
        url='https://raw.githubusercontent.com/google/material-design-icons/master/src/'+path+'/materialicons/24px.svg'
        try:
            with urllib.request.urlopen(url,timeout=30) as response: svg=response.read()
        except Exception as error:
            raise RuntimeError('Cannot import '+name+' from '+url) from error
        write_asset(args.output,name,svg);records.append({'name':name,'source':url,'svg_sha256':hashlib.sha256(svg).hexdigest()})
    manifest=Path('docs/ui-parity/ICON_SOURCES.json');manifest.parent.mkdir(parents=True,exist_ok=True)
    manifest.write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
    print('Imported',len(records),'original vector icons')

if __name__ == '__main__': main()
