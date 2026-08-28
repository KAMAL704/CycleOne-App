#!/usr/bin/env bash
set -euo pipefail

# Produces installable, optimized APKs per CPU architecture. For a normal
# Android phone install the arm64-v8a artifact is the smallest and most common.
flutter build apk --release --split-per-abi "$@"

echo
echo 'Release APKs:'
ls -lh build/app/outputs/flutter-apk/app-*-release.apk
