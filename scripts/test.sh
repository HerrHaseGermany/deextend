#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
swiftc -swift-version 5 Sources/Localization.swift Sources/DisplayController.swift Tests/main.swift -o build/policy-tests
build/policy-tests
swiftc -swift-version 5 Sources/Localization.swift Sources/DisplayController.swift Tests/ControllerTests.swift -o build/controller-tests
build/controller-tests
python3 Tests/check_localizations.py
TEST_ROOT=$(mktemp -d /tmp/deextend-languages.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_APP="$TEST_ROOT/LocalizationTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
cp Resources/Info.plist "$TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LocalizationTests' "$TEST_APP/Contents/Info.plist"
for LOCALIZATION in Resources/*.lproj; do
    ditto "$LOCALIZATION" "$TEST_APP/Contents/Resources/${LOCALIZATION:t}"
done
swiftc -swift-version 5 -parse-as-library Sources/Localization.swift Tests/LocalizationTests.swift -o "$TEST_APP/Contents/MacOS/LocalizationTests"
"$TEST_APP/Contents/MacOS/LocalizationTests" -AppleLanguages '(de)' de
"$TEST_APP/Contents/MacOS/LocalizationTests" -AppleLanguages '(en)' en
"$TEST_APP/Contents/MacOS/LocalizationTests" -AppleLanguages '(fr)' en
