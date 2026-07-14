# Model Meter

Model Meter is a small native macOS menu-bar utility for seeing Claude Code and Codex usage in one place. It asks the CLIs you already use, so there are no API keys to paste into another app and no provider credentials stored by Model Meter.

## What it shows

- Claude subscription quota windows from the built-in `/usage` command
- Claude interactive and background session count from `claude agents --json`
- Codex rolling and weekly quota windows, including model-specific buckets
- Codex tokens used today, lifetime tokens, plan, and streak
- Exact and relative reset times for quota windows when the CLI reports enough timing data
- Independent stale/error states, so one provider can fail without hiding the other
- A persistent Used / Remaining toggle for every graph and the menu-bar percentage
- Floating glass dashboards in either combined mode or independent Claude and Codex windows
- Native Liquid Glass cards and controls on macOS 26, with a material fallback on earlier supported releases
- Configurable native macOS alerts at one or more remaining-quota thresholds, with optional sound
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

Claude API-key, Bedrock, Vertex, and Foundry authentication do not expose subscription quota bars through `/usage`. In that case Model Meter still reports concurrent sessions and clearly points API spend reporting to Claude Console.

### Codex

Model Meter starts `codex app-server --stdio`, performs the required initialize handshake, then reads:

- `account/rateLimits/read`
- `account/usage/read`

The app-server returns account-wide data, so concurrent Codex sessions are reflected without parsing individual conversation transcripts. This is the rich-client interface shipped with the CLI; the generated protocol is versioned, and the parser deliberately ignores unknown fields for forward compatibility.

Codex account usage requires ChatGPT authentication. Platform API-key spend is not exposed by these Codex CLI methods.

## Privacy and sandboxing

Model Meter never reads or logs provider credentials. It passes requests to the installed CLIs and parses only their usage responses. App Sandbox is intentionally not enabled because sandboxing would prevent the child CLIs from using their existing config/keychain access and would block Claude's cross-process session discovery.

Claude's fallback session-registry check reads only status timestamps and never opens transcript content. Codex conversation logs are not read at all.

## Project layout

The project is a dependency-free Swift package. An AppKit status item and SwiftUI dashboard provide the native menu-bar experience; provider adapters feed a shared snapshot model; parser tests use redacted fixtures and never contact either provider.
