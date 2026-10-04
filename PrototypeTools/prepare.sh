#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
for source_tool in mogenerator git-lfs; do
    if ! command -v "$source_tool" >/dev/null 2>&1; then
        echo "error: Missing official source tool: $source_tool. Install on this Mac with: brew install mogenerator git-lfs" >&2
        echo "error: Homebrew must already be installed. After installation, Run the ordinary Bound scheme again; no Xcode restart or separate project is needed." >&2
        exit 1
    fi
done
# A downloaded source archive has no .git. Seed only dependency gitlinks from
# the committed manifest; no account settings, credentials or commits are made.
if ! git ls-files --error-unmatch Cores/DeltaCore >/dev/null 2>&1; then
    git init -q
    git add .gitmodules
    python3 - <<'PINS'
import json,subprocess
from pathlib import Path
for path,sha in json.loads(Path('PrototypeConfiguration/dependency-pins.json').read_text()).items():
    subprocess.run(['git','update-index','--add','--cacheinfo','160000,'+sha+','+path],check=True)
PINS
fi
dependency_paths=()
while IFS= read -r dependency; do dependency_paths+=("$dependency"); done < <(python3 -c 'import json; print("\n".join(json.load(open("PrototypeConfiguration/dependency-pins.json"))))')
# Per-command filters also work on a fresh Mac without modifying global Git settings.
git -c filter.lfs.clean='git-lfs clean -- %f' \
    -c filter.lfs.smudge='git-lfs smudge -- %f' \
    -c filter.lfs.process='git-lfs filter-process' \
    -c filter.lfs.required=true \
    -c url.https://github.com/.insteadOf=git@github.com: submodule update --init --recursive --jobs 4 -- "${dependency_paths[@]}"
# Repair pointer-only skins from checkouts created before Git LFS was configured.
# Pull only when these pinned public assets are still pointers, not on every Build.
python3 - <<'LFS'
from pathlib import Path
import subprocess
for core in ('Cores/MelonDSDeltaCore', 'Cores/NESDeltaCore'):
    skins = Path(core) / Path(core).name / 'Controller Skin'
    needs_download = False
    for asset in skins.glob('*'):
        if asset.is_file():
            with asset.open('rb') as stream:
                if stream.read(100).startswith(b'version https://git-lfs.github.com/spec/v1'):
                    needs_download = True
                    break
    if needs_download:
        subprocess.run(['git', '-C', core, 'lfs', 'pull'], check=True)
LFS
apply_recorded_patch() {
    local source_repo="$1" patch_file="$2"
    patch_file="$(pwd)/$patch_file"
    if git -C "$source_repo" apply --check "$patch_file" >/dev/null 2>&1; then
        git -C "$source_repo" apply "$patch_file"
    elif git -C "$source_repo" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        : # Already applied exactly.
    else
        echo "Patch cannot apply cleanly; preserve local work and inspect $patch_file" >&2
        exit 1
    fi
}
apply_recorded_patch Vendor/RevenueCat PrototypePatches/revenuecat-5.8.0-swift-memberwise.patch
apply_recorded_patch Cores/SNESDeltaCore/snes9x PrototypePatches/snes9x-const-comparators.patch
apply_recorded_patch Cores/DeltaCore PrototypePatches/deltacore-companion.patch
config_source="${BOUND_PUBLIC_CONFIG:-$(pwd)/PrototypeConfiguration/public-client.json}"
if [[ -f "$config_source" ]]; then
    cp "$config_source" Delta/Bound/cloud-configuration.json
elif [[ ! -f Delta/Bound/cloud-configuration.json ]]; then
    echo 'Set BOUND_PUBLIC_CONFIG to the existing public Bound build configuration JSON.' >&2
    exit 1
fi
