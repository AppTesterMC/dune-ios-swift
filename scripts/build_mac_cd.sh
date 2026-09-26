#!/bin/zsh
# The macOS app with the CD release's data: builds the Mac target, then
# swaps the bundled floppy DuneFiles for DuneFilesCD (DUNE.DAT and
# DNCDPRG.EXE) and re-signs ad hoc. Result: builds/Dune CD.app
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
[[ -f DuneFilesCD/DUNE.DAT && -f DuneFilesCD/DNCDPRG.EXE ]] || { print -u2 "DuneFilesCD/ needs DUNE.DAT and DNCDPRG.EXE"; exit 1; }
xcodebuild -project SwiftDune.xcodeproj -scheme SwiftDune -configuration Release -sdk macosx -arch arm64 \
  -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build -quiet
app="builds/Dune CD.app"
rm -rf "$app"
mkdir -p builds
ditto build/mac/Build/Products/Release/Dune.app "$app"
rm -rf "$app/Contents/Resources/DuneFiles"
ditto DuneFilesCD "$app/Contents/Resources/DuneFilesCD"
codesign --force --deep --sign - "$app"
print "APP=$repo_root/$app"
