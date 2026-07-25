# Model Meter

Model Meter is a small native macOS menu-bar utility for seeing Claude Code and Codex usage in one place. It asks the CLIs you already use, so there are no API keys to paste into another app and no provider credentials stored by Model Meter.

## What it shows

- Claude subscription quota windows from the built-in `/usage` command
- Claude token activity, streak, lifetime sessions/messages, and interactive/background session count
- Codex rolling and weekly quota windows, including model-specific buckets
- Available Codex usage-limit reset credits and their expiry dates
- Codex tokens used today, lifetime tokens, plan, and streak
- Exact and relative reset times for quota windows when the CLI reports enough timing data
- Independent stale/error states, so one provider can fail without hiding the other
- A persistent Used / Remaining toggle for every graph and the menu-bar percentage
- Configurable Claude-first or Codex-first ordering across every dashboard
- Floating glass dashboards in either combined mode or independent Claude and Codex windows
- Native Liquid Glass cards and controls on macOS 26, with a material fallback on earlier supported releases
- Configurable native macOS alerts at one or more remaining-quota thresholds, with optional sound
- Session-aware Auto-Continue for Kitty: resume selected Claude or Codex tabs when an exhausted 5-hour window recovers
- Automatic refresh (1–30 minutes), manual refresh, and configurable CLI paths

The menu-bar item identifies the provider and quota window currently under the most pressure, using the selected Used or Remaining mode.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode 16 or newer to build
- Claude Code and/or Codex CLI already installed and authenticated

Model Meter auto-detects common Apple Silicon and Intel Homebrew paths plus `~/.local/bin` and `PATH`. Finder-launched apps do not receive your full shell environment, so explicit paths can be set under Settings.

## Build and run

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

Auto-Continue can type `continue` and press Return in enrolled Kitty sessions after Model Meter observes that provider's 5-hour window reach 100% and later become available again. It is off by default.

Enable Kitty's local-socket remote control by adding this to `kitty.conf`, then restart Kitty:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/model-meter-kitty
```

If Kitty already has a `listen_on` address, keep it—Model Meter discovers the address from `kitty.conf` and follows Kitty's PID-suffixed socket automatically. You can also enter an explicit address in Advanced settings.

Open Model Meter Settings, enable Auto-Continue, and use **Scan** on the Claude or Codex card. Kitty tab titles are cleaned up and shown in the session list. The default **Selected Sessions** mode sends only to the sessions you explicitly enroll. **All Sessions** opts that provider into every live Kitty window matching its foreground process or title. Advanced matching accepts Kitty's native match syntax or Model Meter's `smart:<provider>` matcher.

Model Meter verifies saved window IDs against live provider-matching Kitty windows before sending. It sends once per observed exhaustion/recovery cycle, persists an armed recovery across relaunches, wakes near the provider's reported reset time, and leaves a continuation armed if no enrolled session is available.

## Privacy and sandboxing

Model Meter never reads or logs provider credentials. It passes requests to the installed CLIs and parses only their usage responses. App Sandbox is intentionally not enabled because sandboxing would prevent the child CLIs from using their existing config/keychain access and would block Claude's cross-process session discovery.

Claude's fallback session-registry check reads only status timestamps. Its stats integration reads only Claude Code's aggregate stats cache. Model Meter never opens Claude or Codex transcript content.

Auto-Continue uses Kitty's configured local Unix socket. It does not use Accessibility permissions, scrape terminal contents, or activate a terminal window.

## Project layout

The project is a dependency-free Swift package. An AppKit status item and SwiftUI dashboard provide the native menu-bar experience; provider adapters feed a shared snapshot model; parser tests use redacted fixtures and never contact either provider.
