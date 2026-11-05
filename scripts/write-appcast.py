"""Create the Sparkle appcast from sign_update output; never handles private keys."""
import email.utils
import os
import xml.etree.ElementTree as ET

namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
version = os.environ['RELEASE_VERSION']
build = os.environ['RELEASE_BUILD']
archive = os.environ['RELEASE_ARCHIVE']
signature = ET.fromstring(f'<enclosure xmlns:sparkle="{namespace}" {os.environ["RELEASE_SIGNATURE"]} />')
signature.set('url', f'https://github.com/colombod/service-discver-macos/releases/download/v{version}/{archive}')
signature.set('type', 'application/octet-stream')
signature.set(f'{{{namespace}}}version', build)
signature.set(f'{{{namespace}}}shortVersionString', version)
root = ET.Element('rss', version='2.0')
channel = ET.SubElement(root, 'channel')
ET.SubElement(channel, 'title').text = 'Service Discovery for macOS'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Service Discovery {version}'
ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
ET.SubElement(item, f'{{{namespace}}}minimumSystemVersion').text = '14.0'
item.append(signature)
ET.indent(root)
ET.ElementTree(root).write('dist/release/appcast.xml', encoding='utf-8', xml_declaration=True)
