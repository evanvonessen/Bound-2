#!/bin/bash

# Fail if error occurs
set -e

SCHEME="Systems"
PLATFORM="iOS"
if [[ "${PLATFORM_NAME}" == "iphonesimulator" ]]; then PLATFORM="iOS Simulator"; fi

BUILD_DIR=".build"

case $PLATFORM in
"iOS")
CONFIG_FOLDER="${CONFIGURATION}-iphoneos"
;;
"iOS Simulator")
CONFIG_FOLDER="${CONFIGURATION}-iphonesimulator"
;;
esac

OUTPUT_DIR="$BUILD_DIR/Build/Products/$CONFIG_FOLDER"

xcodebuild -workspace Systems.xcworkspace -scheme $SCHEME -configuration ${CONFIGURATION} -destination "generic/platform=$PLATFORM" -derivedDataPath $BUILD_DIR BITCODE_GENERATION_MODE=bitcode IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}" CODE_SIGNING_ALLOWED=NO ARCHS="${ARCHS:-arm64}" ONLY_ACTIVE_ARCH=YES
        
cp -Rf "$OUTPUT_DIR/Systems.framework" "${BUILT_PRODUCTS_DIR}/"
