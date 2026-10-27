"""Retain the exact notices shipped by resolved dependencies in the app bundle."""
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
checkouts = root / 'build/SourcePackages/checkouts'
text = ['Simplex Music Player 2.0.0\nOpen-source software acknowledgements\n\nSFBAudioEngine: https://github.com/sbooth/SFBAudioEngine\nTagLib: https://taglib.org\n']
for repo in sorted(checkouts.glob('*')):
    for file in sorted(repo.rglob('*')):
        if file.is_file() and (file.name.lower().startswith(('license', 'copying', 'copyright', 'acknowledg')) or file.suffix == '.license'):
            if file.stat().st_size < 200000:
                try: text.append('\n\n===== ' + str(file.relative_to(checkouts)) + ' =====\n' + file.read_text())
                except UnicodeError: pass
(root / 'app/Acknowledgements.txt').write_text('\n'.join(text))
