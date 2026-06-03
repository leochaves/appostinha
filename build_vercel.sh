#!/bin/bash
set -e

FLUTTER_VERSION="3.32.1"
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar xJf - -C "$HOME"
fi

export PATH="$PATH:$FLUTTER_DIR/bin"

flutter config --no-analytics
flutter pub get
flutter build web --release
