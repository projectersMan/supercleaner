"""Create isolated scanner input; no user files are read or removed."""
import os
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[2] / 'Tests/temporary/large-files/home/Downloads'
root.mkdir(parents=True, exist_ok=True)
copy = os.urandom(12_000_000)
(root / 'a.rip').write_bytes(copy)
(root / 'b.data').write_bytes(copy)
(root / 'setup.dmg').write_bytes(b'installer-fixture' * 800_000)
extracted = root / 'Extracted'
extracted.mkdir(exist_ok=True)
payload = extracted / 'payload.bin'
payload.write_bytes(os.urandom(12_000_000) + bytes(2_000_000))
with zipfile.ZipFile(root / 'packed.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(payload, 'Extracted/payload.bin')
