#!/bin/bash

echo "Starting Vercel build script for Flutter..."

if [ ! -d "flutter" ]; then
  echo "Cloning Flutter stable channel..."
  git clone https://github.com/flutter/flutter.git -b stable
fi

export PATH="$PATH:`pwd`/flutter/bin"

echo "Flutter version:"
flutter --version

echo "Getting dependencies..."
flutter pub get

echo "Building Flutter Web..."
flutter build web --release

echo "Build complete."
