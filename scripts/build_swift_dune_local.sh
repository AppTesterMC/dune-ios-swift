#!/bin/zsh

# Build SwiftDune from a local staged copy, matching Cryogenic's native
# ScummVM workflow.  The external volume remains the source of truth, but the
# compiler and derived data never build in /Volumes or /private/tmp's source
# checkout.  Each run gets its own directory so a reboot cannot destroy the
# last copied app in builds/.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"
stage_root="${SWIFT_DUNE_LOCAL_BUILD_ROOT:-/private/tmp/swift-dune-local-${stamp}}"
stage_source="$stage_root/source"
stage_derived="$stage_root/derived"
output_root="$repo_root/builds"
output_app="$output_root/SwiftDune-local-${stamp}.app"

mkdir -p "$stage_source" "$output_root"

# Copy only build inputs.  Do not copy the repository's generated builds,
# editor state, or large reference/video files into the compiler staging area.
cp -R "$repo_root/SwiftDune.xcodeproj" "$stage_source/SwiftDune.xcodeproj"
cp -R "$repo_root/SwiftDune" "$stage_source/SwiftDune"
cp -R "$repo_root/DuneFiles" "$stage_source/DuneFiles"

cd "$stage_source"
xcodebuild \
  -project SwiftDune.xcodeproj \
  -scheme SwiftDune \
  -configuration Release \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath "$stage_derived" \
  EXCLUDED_SOURCE_FILE_NAMES=Shaders.metal \
  CODE_SIGNING_ALLOWED=NO \
  build

built_app="$stage_derived/Build/Products/Release/Dune.app"
if [[ ! -d "$built_app" ]]; then
  print -u2 "SwiftDune build did not produce $built_app"
  exit 1
fi

ditto "$built_app" "$output_app"

# The current macOS target intentionally excludes Shaders.metal on machines
# whose command-line Metal toolchain is unavailable.  Preserve the compiled
# shader library from the last durable build when the staged build did not
# copy one itself.
if [[ ! -f "$output_app/Contents/Resources/default.metallib" ]]; then
  prior_shader="$(find "$output_root" -maxdepth 4 -path '*/Contents/Resources/default.metallib' -type f -print -quit)"
  if [[ -n "$prior_shader" ]]; then
    mkdir -p "$output_app/Contents/Resources"
    cp "$prior_shader" "$output_app/Contents/Resources/default.metallib"
  fi
fi

print "LOCAL_STAGE=$stage_root"
print "APP=$output_app"
