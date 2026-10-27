import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
assets = root / 'app/Assets.xcassets'
assets.mkdir(parents=True, exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
for name in ['Aurora', 'Ember', 'Glacier', 'Obsidian']:
    source = root / 'IconSources' / (name + '.png')
    icon = assets / (('AppIcon' if name == 'Aurora' else name) + '.appiconset')
    icon.mkdir(parents=True, exist_ok=True)
    subprocess.run(['sips', '-z', '1024', '1024', str(source), '--out', str(icon / 'icon.png')], check=True, capture_output=True)
    (icon / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'icon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}))
    preview = assets / ('Icon' + name + '.imageset')
    preview.mkdir(parents=True, exist_ok=True)
    subprocess.run(['sips', '-z', '256', '256', str(source), '--out', str(preview / 'icon.png')], check=True, capture_output=True)
    (preview / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'icon.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}))
