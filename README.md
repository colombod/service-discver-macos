# Service Discovery for macOS

A native macOS entry point for systems running [Service Directory](https://github.com/colombod/service-directory). Connect to one directory to browse its federated catalogue, open hosted services, and launch SSH or tmux sessions for each system.

Requires macOS 14 or later and network access to your nodes, usually through Tailscale. The initial build targets Apple silicon. No App Store account or installation is involved.

## Using the app

1. Add your directory’s HTTP or HTTPS URL. The node’s existing federation supplies the system list.
2. Select a system to filter services or configure its SSH hostname/alias, user, port, and tmux session.
3. Select a service, then **Open Service**. Sign in to that service within the app; WebKit retains its website data across launches. **Browser** opens it in your default browser, which has a separate session store.
4. Use **Directory maintenance** to check or request an update to the connected directory. **Service Discovery → Check for App Updates…** updates the Mac app itself.

Services marked `view_kind: json` open in a native JSON inspector with summary fields, expandable objects and arrays, search, a formatted text view, and copy controls. The inspector follows `view_refresh_seconds`; pause automatic refresh whenever you want to inspect a snapshot. **Auto** also recognizes JSON response content types on otherwise unmarked services, while **Web** keeps the browser available for sign-in or ordinary pages. Existing service cookies follow normal host/path/HTTPS boundaries; directory tokens are never used for these requests. Failed refreshes retain the last successful payload with a visible error. The inspector limits responses to 4 MB, 20,000 values, and 64 nesting levels.

Closing the window leaves Service Discovery running in the menu bar. Use its **Services** server icon → **Open Service Discovery** to reopen the window, **Start at Login** to control automatic startup, or **Quit Service Discovery** to exit. Login startup uses macOS Login Items; if macOS requires approval, the menu provides a link to those settings.

Read-gated directories accept a peer token; maintenance actions accept a separate write token. Both are optional for an open catalogue and are saved in macOS Keychain. The client does not mint a peer identity or run a directory server. Directory tokens are never attached to service pages, discovered peers, or redirected API requests. Preferences contain connection URLs and terminal shortcuts, without tokens, in `~/Library/Application Support/ServiceDiscovery`.

SSH uses Terminal and the Mac’s existing SSH config, keys, and agent. The configured host can be an SSH config alias. tmux runs `new-session -A` over SSH to attach or create the named remote session; it must be installed on that system. Saving shortcuts does not connect or execute commands.

The catalogue refreshes every 30 seconds. Failed refreshes preserve the previous snapshot with an error. Node reachability comes from the directory’s perspective. The app fetches each node’s own `/api/health` and verifies its identity, keeping namesake services separate by origin. A peer requiring authentication needs its own saved directory connection and read credential; the entry node’s token is never forwarded. Failed health requests remain unknown. For services reported up, the app also checks the registered `health_url`, falling back to the browser-facing address, with a credential-free HEAD request: proxy errors show Down, TLS failures show Certificate error, and HTTP authentication challenges show Sign-in required. A service that does not support HEAD retains the node’s reported health. Both HTTP and HTTPS registrations are supported; HTTPS certificate validation stays enabled. Neither check proves that every application feature works.

## Build and test

```sh
swift test
bash scripts/build-app.sh
open "dist/Service Discovery.app"
```

Open `Package.swift` in Xcode for development. The packaging script embeds Sparkle and creates the app icon. Development packages use ad-hoc signing. Release packages use Developer ID signing, hardened runtime, notarization, and signed Sparkle archives and feeds; see [Releasing](docs/RELEASING.md).

## Directory maintenance compatibility

The app reads the existing `/api/services`, `/api/federation/nodes`, `/api/instance-info`, and `/api/health` endpoints. It detects the optional maintenance API and explains when an older node does not have it. The server change is tracked in [service-directory PR #22](https://github.com/colombod/service-directory/pull/22).

Remote self-update currently requires a Linux systemd user service, systemd 254+, and a genuine uv tool installation. Other installs retain their CLI upgrade route. Select another saved directory connection with that node’s own credentials to manage it; credentials are never forwarded across the federation. Backend updates are explicit and may briefly disconnect the directory. The client does not update hosted services.

Website sessions last as long as each service permits. Sites may expire logins or require a browser for some authentication methods. In-app website data is separate from Safari and Chrome.
