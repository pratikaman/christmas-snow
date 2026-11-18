#!/bin/sh
set -eu
cd "$(dirname "$0")"
bundle="${1:-$PWD/Christmas Snow.app}"
mkdir -p "$bundle/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" main.swift Motion.swift Geometry.swift SnowView.swift DockSantas.swift -o "$bundle/Contents/MacOS/ChristmasSnow"
cp Info.plist "$bundle/Contents/"
mkdir -p "$bundle/Contents/Resources/Santa"
cp Assets/Santa/* "$bundle/Contents/Resources/Santa/"
codesign --force --sign - "$bundle"
