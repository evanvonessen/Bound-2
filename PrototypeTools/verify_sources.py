"""Validate pinned source snapshots without downloading or overwriting local edits."""
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / "PrototypeConfiguration/vendored-sources.json").read_text())
errors = []
for name, expected in manifest["sha256"].items():
    path = root / name
    if not path.is_file() and not path.is_symlink():
        errors.append(f"missing: {name}")
    elif hashlib.sha256(os.readlink(path).encode() if path.is_symlink() else path.read_bytes()).hexdigest() != expected:
        errors.append(f"modified: {name}")
if errors:
    print("Source integrity differs; local changes are preserved:", file=sys.stderr)
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Verified {len(manifest['sha256'])} pinned source files; no downloads or changes.")
