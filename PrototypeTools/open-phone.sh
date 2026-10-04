#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PrototypeTools/prepare.sh
open -a "$(xcode-select -p)/../.." Bound.xcodeproj
printf 'Choose Bound and your iPhone, then Run (Release). No signing assets or accounts are created.\n'
