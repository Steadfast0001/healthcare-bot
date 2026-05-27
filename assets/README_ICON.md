Save the provided image attachment as `assets/app_icon.png` (replace existing file if present).

Steps to generate native app icons (run from project root):

1. Ensure Flutter and Dart are installed and on your PATH.
2. Save the attached image to `assets/app_icon.png`.
3. Get packages:

```bash
flutter pub get
```

4. Run the launcher icon generator:

```bash
flutter pub run flutter_launcher_icons:main
```

This will overwrite native launcher icons for Android, iOS, web, Windows, macOS, and Linux using `assets/app_icon.png`.

If you prefer manual icon placement, replace files under `android/app/src/main/res/mipmap-*` and the iOS `Assets.xcassets/AppIcon.appiconset` with properly sized images.