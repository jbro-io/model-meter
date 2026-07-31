---
name: verify-model-meter
description: Validate Model Meter changes with focused and full tests, bundle integrity checks, updater framework checks, and an optional final reinstall. Use after implementing code changes, before a pull request or release, when diagnosing packaging failures, or whenever the user asks to build, install, or reinstall the app.
---

# Verify Model Meter

Run the smallest relevant checks while iterating, then finish with the complete validation appropriate to the changed surface.

## Inspect

1. Read `git status --short` and preserve unrelated user changes.
2. Review the exact diff and run `git diff --check`.
3. Identify focused XCTest filters for changed behavior.
4. Keep each user-visible unit in its own Conventional Commit.

## Test

Run focused tests while iterating:

```sh
swift test --filter <TestCaseOrMethod>
```

Before handoff, run:

```sh
swift test
./scripts/build-app.sh
```

For release packaging, build both architectures:

```sh
MODEL_METER_ARCHS="arm64 x86_64" ./scripts/build-app.sh
```

## Verify the bundle

Set `APP="dist/Model Meter.app"` and verify:

```sh
plutil -lint "$APP/Contents/Info.plist"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
test -f "$APP/Contents/Resources/Sparkle-LICENSE.txt"
otool -L "$APP/Contents/MacOS/ModelMeter"
codesign --verify --deep --strict --verbose=2 "$APP"
```

Require the executable to load Sparkle through `@rpath`, and require `@executable_path/../Frameworks` in its load commands. For a release build, also run:

```sh
lipo "$APP/Contents/MacOS/ModelMeter" -verify_arch arm64 x86_64
```

## Reinstall

Only install when the user asks for a build/install/reinstall. Make it the final mutation after tests and commits:

```sh
./scripts/install.sh
codesign --verify --deep --strict --verbose=2 \
  "/Applications/Model Meter.app"
```

Confirm the installed `CFBundleShortVersionString`, `CFBundleVersion`, and embedded Sparkle framework. Restart the menu-bar app so the user is running the new binary.

## Report

Report focused/full test results, bundle and signing status, installed version, restart status, and the atomic commits created. Call out skipped live-provider tests or absent Apple notarization credentials explicitly.
