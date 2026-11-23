"""Check repository-relative links in maintained Markdown; historical archives stay self-contained."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
files = [ROOT / 'README.md', ROOT / 'Tests/README.md', *sorted((ROOT / 'docs').rglob('*.md'))]
missing = []
for source in files:
    for target in re.findall(r'\]\(([^)]+)\)', source.read_text()):
        target = target.strip('<>')
        if target.startswith(('#', '/')) or urlsplit(target).scheme:
            continue
        clean = re.sub(r':\d+$', '', unquote(target.split('#')[0]))
        path = (source.parent / clean).resolve()
        if path.is_relative_to(ROOT / 'build'):
            continue  # Generated artifacts are checked by check-artifacts.py.
        if not path.exists():
            missing.append(f'{source.relative_to(ROOT)}: {target}')
if missing:
    raise SystemExit('Missing local documentation links:\n' + '\n'.join(missing))
print(f'PASS: repository-relative links in {len(files)} maintained Markdown files')
