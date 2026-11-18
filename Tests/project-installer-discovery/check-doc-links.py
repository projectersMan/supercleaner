from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
FILES = ['README.md', 'doc/architecture.md', 'doc/development.md', 'docs/architecture.md',
         'docs/development.md', 'docs/production-release-checklist.md',
         'doc/project-installer-discovery-plan.md', 'doc/release-0.4.20.md',
         'Tests/project-installer-discovery/README.md']
missing = []
for name in FILES:
    source = ROOT / name
    for target in re.findall(r'\]\(([^)]+)\)', source.read_text()):
        if '://' in target or target.startswith('#'):
            continue
        clean = re.sub(r':\d+$', '', target.split('#')[0].strip('<>'))
        if not (source.parent / clean).exists():
            missing.append((name, target))
for item in missing:
    print('MISSING', *item)
assert not missing, missing
print(f'PASS: current documentation local links in {len(FILES)} files')
