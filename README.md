# Model Meter

Model Meter is a small native macOS menu-bar utility for seeing Claude Code and Codex usage in one place. It asks the CLIs you already use, so there are no API keys to paste into another app and no provider credentials stored by Model Meter.

## What it shows

- Claude subscription quota windows from the built-in `/usage` command
- Claude token activity, streak, lifetime sessions/messages, and interactive/background session count
- Codex rolling and weekly quota windows, including model-specific buckets
- Available Codex usage-limit reset credits and their expiry dates
- Codex daily and lifetime token activity, current and best streaks, peak day, and longest-running turn
- Exact and relative reset times for quota windows when the CLI reports enough timing data
- Independent stale/error states, so one provider can fail without hiding the other
- A persistent Used / Remaining toggle for every graph and the menu-bar percentage
- Configurable Claude-first or Codex-first ordering across every dashboard
- Floating glass dashboards in either combined mode or independent Claude and Codex windows
- Native Liquid Glass cards and controls on macOS 26, with a material fallback on earlier supported releases
- Configurable native macOS alerts at one or more remaining-quota thresholds, with optional sound
- Session-aware Auto-Continue for Kitty, iTerm2, and Ghostty: resume enrolled Claude or Codex sessions when an exhausted 5-hour window recovers
- Signed in-app updates from GitHub Releases, including a manual Check for Updates action
- Automatic refresh (1–30 minutes), manual refresh, and configurable CLI paths

The menu-bar item identifies the provider and quota window currently under the most pressure, using the selected Used or Remaining mode.

## Requirements

- macOS 14 or newer
- Claude Code and/or Codex CLI already installed and authenticated

Model Meter auto-detects common Apple Silicon and Intel Homebrew paths plus `~/.local/bin` and `PATH`. Finder-launched apps do not receive your full shell environment, so explicit paths can be set under Settings.

## Install

Download the universal app archive from the [latest GitHub Release](https://github.com/jbro-io/model-meter/releases/latest), extract it, and move **Model Meter.app** to Applications. No Swift toolchain or local build is required.

Model Meter checks the signed GitHub release feed with Sparkle. You can also choose **Check for Updates…** under Settings. Update archives and the feed are signed with the project’s Ed25519 release key before publication.

## Build and run

Source builds require Swift 6 / Xcode 16 or newer.

```sh
make test
make app
open "dist/Model Meter.app"
```

The normal tests use only redacted fixtures. To also verify both installed CLIs end to end:

```sh
MODEL_METER_LIVE_TESTS=1 swift test --filter LiveProviderTests
```

To install it in the system Applications folder:

```sh
make install
open "/Applications/Model Meter.app"
```

The app is ad-hoc signed for local use. Open the Swift package in Xcode if you prefer to run and debug it there.

## CI and releases

Every push to `master` and every pull request runs the test suite, builds the app bundle, verifies the embedded Sparkle framework, and validates the complete code signature. Pull-request jobs do not receive release secrets.

A tag such as `v0.11.0` triggers the release workflow. The tag must match `CFBundleShortVersionString` in `Resources/Info.plist`, and `CFBundleVersion` must be incremented. The workflow:

1. Tests and builds a universal Apple Silicon/Intel app.
2. Developer ID signs and notarizes it when all Apple credentials are configured; otherwise it creates an ad-hoc signed build.
3. Packages the app without breaking framework symlinks.
4. Signs the archive and appcast with Sparkle’s Ed25519 key.
5. Publishes both assets in a GitHub Release, making the appcast available to installed copies.

`SPARKLE_PRIVATE_KEY` is the only required release secret. Keep the same private key in 1Password for authorized maintainers and set it as a GitHub Actions repository secret. Do not commit it or distribute it to contributors who do not publish releases. To import a 1Password copy on another development Mac:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account io.jbro.modelmeter \
  -f /secure/path/to/model-meter-sparkle-private-key
```

For notarized releases, configure all five optional repository secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

If any Apple signing secret is present, the workflow requires the complete set rather than publishing a partially signed release. Restrict tag creation and release-secret access to maintainers.

## How the integrations work

### Claude

Model Meter runs the supported built-in command in non-interactive safe mode:

```sh
claude --print --output-format json --no-session-persistence --safe-mode /usage
```

It also runs `claude auth status --json` and `claude agents --json`. Safe mode avoids loading project hooks and plugins while retaining the CLI's own authentication. Model Meter does not extract OAuth tokens or call Anthropic's private usage endpoint itself.

For the Activity panel, Model Meter reads Claude Code's aggregate `~/.claude/stats-cache.json`. Detached provider windows render a token pulse graph with 7-day, 30-day, and 3-month ranges; constrained popover cards keep the smaller stat grid.

Claude API-key, Bedrock, Vertex, and Foundry authentication do not expose subscription quota bars through `/usage`. In that case Model Meter still reports concurrent sessions and clearly points API spend reporting to Claude Console.

### Codex

Model Meter starts `codex app-server --stdio`, performs the required initialize handshake, then reads:

- `account/rateLimits/read`
- `account/usage/read`

The app-server returns account-wide data, so concurrent Codex sessions are reflected without parsing individual conversation transcripts. This is the rich-client interface shipped with the CLI; the generated protocol is versioned, and the parser deliberately ignores unknown fields for forward compatibility.

When Codex reports a granted usage-limit reset, Model Meter shows its availability and expiry date. It is display-only; Model Meter never consumes a reset.

Codex account usage requires ChatGPT authentication. Platform API-key spend is not exposed by these Codex CLI methods.

### Auto-Continue

Auto-Continue can type `continue` and press Return in enrolled terminal sessions after Model Meter observes that provider's 5-hour window reach 100% and later become available again. It is off by default. Enrollments are stored separately for each terminal and provider.

Use the terminal button in Model Meter's popover to open Session Autopilot, or use the full Auto-Continue settings. Choose a terminal, scan its live sessions, and explicitly enroll the Claude or Codex sessions that should resume.

#### Kitty

Enable Kitty's local-socket remote control by adding this to `kitty.conf`, then restart Kitty:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/model-meter-kitty
```

If Kitty already has a `listen_on` address, keep it—Model Meter discovers the address from `kitty.conf` and follows Kitty's PID-suffixed socket automatically. You can also enter an explicit address in Advanced settings.

Kitty tab titles are cleaned up and shown as session tiles. The default **Selected Sessions** mode sends only to the sessions you explicitly enroll. **All Sessions** opts that provider into every live Kitty window matching its foreground process or title. Advanced matching accepts Kitty's native match syntax or Model Meter's `smart:<provider>` matcher.

Model Meter verifies saved window IDs against live provider-matching Kitty windows before sending. Each successful scan automatically forgets enrolled window IDs that Kitty no longer reports, so closed tabs do not remain in the enrolled count. It sends once per observed exhaustion/recovery cycle, persists an armed recovery across relaunches, wakes near the provider's reported reset time, and leaves a continuation armed if no enrolled session is available.

#### iTerm2

Run iTerm2, select it in Auto-Continue, and choose **Test Access & Scan**. macOS will ask whether Model Meter may automate iTerm. Grant access under **System Settings → Privacy & Security → Automation** if necessary.

iTerm2 support uses its maintained-for-compatibility AppleScript interface. For safety, only explicitly enrolled sessions are supported. Model Meter uses the foreground executable while scanning, then retains only the session ID, TTY, working directory, provider, and display title needed to reject a stale or reused session ID. Full command lines are never persisted.

#### Ghostty preview

Ghostty 1.3 or newer is required, and its `macos-applescript` setting must remain enabled. Ghostty's AppleScript API is still preview, so Model Meter supports explicitly enrolled sessions only—never broad All Matching delivery.

Because Ghostty does not expose foreground process metadata, eligible terminal titles must be exactly `Claude`, `Claude Code`, or `Codex`, or end in ` — <provider>`, ` - <provider>`, or ` | <provider>`. Model Meter rechecks the exact enrolled title, working directory, and terminal ID before sending.

For iTerm2 and Ghostty, a failed or unauthorized scan never deletes enrollment state. Only a complete user-initiated scan prunes closed sessions. If delivery succeeds for only some enrolled sessions, that progress is persisted and only the unsent sessions are retried. Changing terminals or that provider's enrollments while a recovery is armed invalidates its delivery route so text cannot be sent into a newly selected terminal by accident.

## Privacy and sandboxing

Model Meter never reads or logs provider credentials. It passes requests to the installed CLIs and parses only their usage responses. App Sandbox is intentionally not enabled because sandboxing would prevent the child CLIs from using their existing config/keychain access and would block Claude's cross-process session discovery.

Claude's fallback session-registry check reads only status timestamps. Its stats integration reads only Claude Code's aggregate stats cache. Model Meter never opens Claude or Codex transcript content.

Auto-Continue uses Kitty's configured local Unix socket or in-process macOS Apple Events for iTerm2 and Ghostty. It does not use Accessibility permissions, scrape terminal contents, or activate a terminal window. Apple Events access is requested only from an explicit terminal scan or delivery, and the app checks that the terminal is already running so a scan cannot launch it.

## Project layout

The project is a native Swift package with Sparkle as its sole runtime dependency. An AppKit status item and SwiftUI dashboard provide the native menu-bar experience; provider adapters feed a shared snapshot model; parser tests use redacted fixtures and never contact either provider.
