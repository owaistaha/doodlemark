# Doodlemark

An iPad app where you doodle an idea with your finger, any stylus or an Apple
Pencil, ink it clean on top, add your name and colors, and export a real vector
logo (SVG + transparent PNG). Fully offline.

## Run it

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

1. **Set your signing team (only needed for running on a real iPad).** Copy
   `Local.xcconfig.example` to `Local.xcconfig` and replace the placeholder
   with your Team ID (Xcode → Settings → Accounts; a free personal team works).
   `Local.xcconfig` is gitignored. Simulator builds work without it.
2. Generate the Xcode project: `xcodegen generate`
3. Open `Doodlemark.xcodeproj` and run the `Doodlemark` scheme on an iPad
   simulator or device.

The `.xcodeproj` is generated from `project.yml`. Don't edit it by hand.
