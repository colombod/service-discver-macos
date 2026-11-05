import subprocess
import sys
import xml.etree.ElementTree as ET

root = ET.parse('dist/release/appcast.xml')
signature = root.find('.//enclosure').attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
subprocess.run([sys.argv[1], '--account', 'service-discver-macos', '--verify', sys.argv[2], signature], check=True)
