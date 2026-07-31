---
name: release-model-meter
description: Prepare and publish Model Meter releases through GitHub Actions, including app versioning, Sparkle key handling, tag validation, Apple signing configuration, and post-release checks. Use when cutting a release, changing updater signing, importing or rotating release keys, configuring release secrets, or diagnosing the release workflow.
---

# Release Model Meter

Keep releases reproducible and keep private signing material out of the repository and command output.

## Prepare the release

1. Inspect `git status`, recent tags, and `Resources/Info.plist`.
2. Set `CFBundleShortVersionString` to the intended semantic version.
3. Increment numeric `CFBundleVersion`; never reuse a published build number.
4. Keep the tag exactly equal to `v<CFBundleShortVersionString>`.
5. Preserve `SUFeedURL`, `SUPublicEDKey`, `SURequireSignedFeed`, and `SUVerifyUpdateBeforeExtraction` unless performing a deliberate key or feed migration.
6. Invoke `$verify-model-meter` for the full test and bundle checks.
7. Commit release-preparation changes atomically with Conventional Commit syntax.

## Handle credentials

- Never print, log, or commit a private key, certificate, or password.
- Use Sparkle account `io.jbro.modelmeter`.
- Store the exported Sparkle private key in 1Password and the GitHub Actions repository secret `SPARKLE_PRIVATE_KEY`.
- Give the private key only to maintainers authorized to publish. Pull requests and ordinary contributors do not need it.
- Verify an imported key against `SUPublicEDKey`:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.jbro.modelmeter \
  -p
```

Import a secured 1Password export on another Mac with:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.jbro.modelmeter \
  -f /secure/path/to/model-meter-sparkle-private-key
```

Treat Apple release credentials as an all-or-nothing set:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

The workflow publishes an Ed25519-secured ad-hoc build when none are configured and a Developer ID signed, notarized build when all are configured.

## Publish

1. Confirm the release commit is on `master`.
2. Create an annotated `v<version>` tag only when the user asks to publish.
3. Push the commit and tag. The tag starts `.github/workflows/release.yml`.
4. Let CI generate `appcast.xml`; never hand-edit a signed appcast.
5. Confirm the workflow publishes both `Model-Meter-<version>.zip` and `appcast.xml`.
6. Verify the latest-release appcast URL resolves and references the versioned archive.

Use `gh run` and `gh release` for read-only status checks. Do not expose secrets while diagnosing failures.

## Recover from failures

- Rerun a failed workflow if no release was published and the source is unchanged.
- Leave a failed draft release unpublished until its assets are complete and verified.
- Never move or recreate an already published version tag. Fix forward with a new version and build number.
- Rotate the Sparkle key only through an intentional migration that preserves update trust.
