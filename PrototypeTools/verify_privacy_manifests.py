"""Check locally audited SDK source snapshots and actual archive resources."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import sys


def verify(root, archive=None):
    audit = json.loads((root / "PrivacyManifests/source-audit.json").read_text())
    errors = []
    inventory = audit["sha256"]
    for source_root in audit["sourceRoots"]:
        for path in (root / source_root).rglob("*"):
            if path.is_file() and path.suffix in audit["sourceExtensions"]:
                name = path.relative_to(root).as_posix()
                if name not in inventory:
                    errors.append(f"Unreviewed source: {name}")
    for name, expected in inventory.items():
        path = root / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            errors.append(f"Source changed; privacy review required: {name}")

    for item in audit["manifests"]:
        expected = {"NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": category, "NSPrivacyAccessedAPITypeReasons": reasons}
            for category, reasons in item["declarations"].items()
        ]}
        paths = [root / item["source"]]
        if archive is not None:
            paths.append(archive / "Products/Applications/Bound.app" / item["archiveRelativePath"])
        for path in paths:
            try:
                actual = plistlib.loads(path.read_bytes())
                if actual != expected:
                    errors.append(f"Manifest differs from reviewed declarations: {path}")
            except (OSError, ValueError, plistlib.InvalidFileException) as error:
                errors.append(f"Missing or invalid manifest: {path}: {error}")

    if archive is not None:
        bundle = archive / "Products/Applications/Bound.app/SDWebImage_Privacy.bundle"
        try:
            metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
            if metadata != plistlib.loads((root / "PrivacyManifests/SDWebImage_Privacy.bundle/Info.plist").read_bytes()):
                errors.append("Archived SDWebImage privacy bundle metadata differs from source")
            if metadata.get("CFBundlePackageType") != "BNDL" or "CFBundleExecutable" in metadata:
                errors.append("SDWebImage privacy bundle must contain resources only")
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            errors.append(f"Missing or invalid SDWebImage privacy bundle metadata: {error}")
    return errors, len(inventory), len(audit["manifests"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Locally built Bound.xcarchive")
    args = parser.parse_args()
    failures, sources, manifests = verify(Path(__file__).resolve().parent.parent, args.archive)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print(f"Verified {sources} source/integration hashes and {manifests} SDK manifests"
          + (" in source and archive." if args.archive else " in source."))
