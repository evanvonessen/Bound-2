#!/bin/bash
# Optional offline source-integrity check. Ordinary Xcode Run needs no preparation.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 PrototypeTools/verify_sources.py
