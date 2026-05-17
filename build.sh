#!/bin/bash
set -e

# 1. Install Flutter if not exists
if ! command -v flutter &> /dev/null
then
    echo "Flutter not found. Installing..."
    git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
    export PATH="$PATH:$HOME/flutter/bin"
else
    echo "Flutter found: $(flutter --version)"
fi

# 2. Accept Android Licenses
yes | flutter doctor --android-licenses || true

# 3. Get dependencies
flutter pub get

# 4. Build APK
echo "Building APK..."
flutter build apk --release

echo "Build finished. APK location: build/app/outputs/flutter-apk/app-release.apk"
