# IMPORTANT: Clawdbot iOS Companion App Specification

**For: Claude Code / Any AI Assistant Building This App**  
**Date: January 2025**  
**Owner: Ruben Sepulveda**

---

## What Is Clawdbot?

Clawdbot is an AI assistant gateway/orchestration system. Think of it as a bridge between AI models (Claude, GPT, etc.) and the real world — messaging apps, tools, devices.

**Key facts:**
- Open source: https://github.com/clawdbot/clawdbot
- Docs: https://docs.clawd.bot (or local at `/opt/homebrew/lib/node_modules/clawdbot/docs`)
- It was originally called "Clawd" — some references may use either name
- Installed via npm: `npm install -g clawdbot`

**The Gateway** runs on a host machine (in this case, Ruben's MacBook Air) and:
- Manages AI chat sessions
- Connects to messaging channels (Telegram, Discord, WhatsApp, etc.)
- Exposes a WebSocket API for control and node connections

---

## What Are Nodes?

A **node** is a companion device that connects to the Gateway and exposes capabilities to the AI. Nodes are *peripherals*, not gateways — they don't run the gateway service themselves.

**Current nodes:**
- **macOS app**: Already exists, connects to the gateway
- **Android app**: Already exists
- **iOS app**: **This is what you're building**

**What nodes provide:**
- Camera (photos + video clips)
- Canvas (WebView for displaying content)
- Screen recording
- Location
- Notifications
- System commands (for macOS/headless nodes)

---

## YOUR ACTUAL CONNECTION DETAILS

```
Gateway URL:     ws://100.122.199.82:18789
Tailscale IP:    100.122.199.82
Port:            18789
Owner:           Ruben Sepulveda
```

The iPhone must have **Tailscale installed and logged into the same tailnet** as the Mac.

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale Network                        │
│                   (Private VPN Mesh)                        │
│                                                             │
│  ┌──────────────────┐         ┌──────────────────────────┐ │
│  │  MacBook Air     │         │   iPhone                 │ │
│  │  (Gateway Host)  │◄───────►│   (iOS Node - YOU BUILD) │ │
│  │                  │   WS    │                          │ │
│  │  Port: 18789     │         │  Connects to:            │ │
│  │  Tailscale IP    │         │  <tailscale-ip>:18789    │ │
│  └──────────────────┘         └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Tailscale** provides:
- Encrypted mesh VPN between devices
- Each device gets a stable IP (100.x.x.x)
- No port forwarding or public exposure needed
- The iPhone and Mac just need Tailscale installed

**Gateway config** (from the Mac):
```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "allowTailscale": true
    },
    "tailscale": {
      "mode": "serve"
    }
  }
}
```

The `tailscale.mode: "serve"` means the gateway uses Tailscale Serve to expose port 18789 to the tailnet.

---

## The WebSocket Protocol

All communication uses **WebSocket** with **JSON text frames**.

### Connection Flow

1. **Client connects** to `ws://<gateway-ip>:18789`
2. **Server sends challenge:**
```json
{
  "type": "event",
  "event": "connect.challenge",
  "payload": { "nonce": "random_string", "ts": 1737264000000 }
}
```

3. **Client sends connect request:**
```json
{
  "type": "req",
  "id": "unique_request_id",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 3,
    "client": {
      "id": "ios-node",
      "version": "1.0.0",
      "platform": "ios",
      "mode": "node"
    },
    "role": "node",
    "scopes": [],
    "caps": ["camera", "canvas", "screen", "location", "voice"],
    "commands": ["camera.snap", "camera.clip", "camera.list", "canvas.navigate", "canvas.snapshot", "canvas.eval", "canvas.present", "canvas.hide", "screen.record", "location.get"],
    "permissions": {
      "camera.capture": true,
      "screen.record": false,
      "location": true
    },
    "auth": { "token": "device_token_if_paired" },
    "locale": "en-US",
    "userAgent": "clawdbot-ios/1.0.0",
    "device": {
      "id": "stable_device_fingerprint",
      "publicKey": "...",
      "signature": "...",
      "signedAt": 1737264000000,
      "nonce": "nonce_from_challenge"
    }
  }
}
```

4. **Server responds:**
```json
{
  "type": "res",
  "id": "unique_request_id",
  "ok": true,
  "payload": {
    "type": "hello-ok",
    "protocol": 3,
    "policy": { "tickIntervalMs": 15000 },
    "auth": {
      "deviceToken": "persisted_token_for_future",
      "role": "node",
      "scopes": []
    }
  }
}
```

### Frame Types

- **Request**: `{type:"req", id, method, params}`
- **Response**: `{type:"res", id, ok, payload|error}`
- **Event**: `{type:"event", event, payload, seq?, stateVersion?}`

---

## Device Pairing

New devices must be **approved** by the gateway owner.

1. iOS app connects for the first time with a new device ID
2. Gateway creates a pairing request
3. User approves via CLI: `clawdbot devices approve <requestId>`
4. Gateway issues a device token in `hello-ok.auth.deviceToken`
5. **Persist this token** — use it for future connections

### Device Identity

Generate a stable device fingerprint using a keypair:
- Create an Ed25519 or P-256 keypair on first launch
- Store in Keychain
- `device.id` = fingerprint of the public key
- Sign the server's nonce to prove identity

---

## Commands the iOS App Must Handle

The gateway will send `node.invoke` requests. Your app responds.

### camera.list
Returns available cameras.
```json
// Request
{ "type": "req", "id": "...", "method": "node.invoke", "params": { "command": "camera.list" } }

// Response payload
{
  "devices": [
    { "id": "back", "name": "Back Camera", "position": "back", "deviceType": "wide" },
    { "id": "front", "name": "Front Camera", "position": "front", "deviceType": "front" }
  ]
}
```

### camera.snap
Take a photo.
```json
// Params
{
  "facing": "front|back",
  "maxWidth": 1600,
  "quality": 0.9,
  "format": "jpg",
  "delayMs": 0,
  "deviceId": "optional_specific_camera"
}

// Response payload
{
  "format": "jpg",
  "base64": "...",
  "width": 1600,
  "height": 1200
}
```
**Important**: Keep base64 payload under 5MB. Recompress if needed.

### camera.clip
Record a short video.
```json
// Params
{
  "facing": "front|back",
  "durationMs": 3000,
  "includeAudio": true,
  "format": "mp4",
  "deviceId": "optional"
}

// Response payload
{
  "format": "mp4",
  "base64": "...",
  "durationMs": 3000,
  "hasAudio": true
}
```
**Important**: Max 60 seconds. Clamp longer requests.

### canvas.present
Show a WebView with content.
```json
// Params
{ "target": "https://example.com", "x": 0, "y": 0, "width": 400, "height": 300 }
```

### canvas.hide
Hide the WebView.

### canvas.navigate
Navigate the WebView to a URL.
```json
{ "url": "https://example.com" }
```

### canvas.eval
Execute JavaScript in the WebView.
```json
// Params
{ "javaScript": "document.title" }

// Response
{ "result": "Page Title" }
```

### canvas.snapshot
Capture the WebView as an image.
```json
// Params
{ "format": "png|jpg", "maxWidth": 1200, "quality": 0.9 }

// Response
{ "format": "png", "base64": "..." }
```

### screen.record
Record the screen (requires Screen Recording permission).
```json
// Params
{
  "durationMs": 10000,
  "fps": 10,
  "includeAudio": false
}

// Response
{ "format": "mp4", "base64": "..." }
```
**Important**: App must be foregrounded. Max 60 seconds.

### location.get
Get device location.
```json
// Params
{
  "timeoutMs": 10000,
  "maxAgeMs": 15000,
  "desiredAccuracy": "coarse|balanced|precise"
}

// Response
{
  "lat": 42.2088,
  "lon": -72.6166,
  "accuracyMeters": 12.5,
  "altitudeMeters": 50.0,
  "speedMps": 0.0,
  "headingDeg": 0.0,
  "timestamp": "2025-01-28T12:00:00.000Z",
  "isPrecise": true,
  "source": "gps"
}
```

---

## Error Codes

Return these standardized error codes:

| Code | Meaning |
|------|---------|
| `CAMERA_DISABLED` | User disabled camera in app settings |
| `CAMERA_PERMISSION_REQUIRED` | iOS camera permission not granted |
| `RECORD_AUDIO_PERMISSION_REQUIRED` | iOS microphone permission not granted |
| `NODE_BACKGROUND_UNAVAILABLE` | App is backgrounded (camera/canvas/screen require foreground) |
| `LOCATION_DISABLED` | User disabled location in app settings |
| `LOCATION_PERMISSION_REQUIRED` | iOS location permission not granted |
| `LOCATION_BACKGROUND_UNAVAILABLE` | App backgrounded, only "while using" permission |
| `LOCATION_TIMEOUT` | No fix within timeout |
| `LOCATION_UNAVAILABLE` | System error |
| `SCREEN_RECORDING_PERMISSION_REQUIRED` | Screen recording permission not granted |

---

## App Settings UI

The app needs a Settings screen with these toggles:

### Camera
- **Allow Camera**: On/Off (default: On)
  - When off, return `CAMERA_DISABLED`

### Location
- **Location Mode**: Off / While Using / Always (default: Off)
  - Maps to iOS location permission levels
- **Precise Location**: On/Off
  - When off, request coarse location only

### Screen Recording
- **Allow Screen Recording**: On/Off (default: Off)

### Notifications
- **Allow Notifications**: On/Off (default: Off)

### Connection
- **Gateway URL**: Text field for `ws://<ip>:18789`
  - **Default value**: `ws://100.122.199.82:18789`
  - Consider auto-discovery via Tailscale in future
- **Device Token**: Display/copy (for debugging)
- **Connection Status**: Show connected/disconnected state

---

## iOS Permissions Required

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Clawdbot needs camera access to take photos and videos when requested by your AI assistant.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Clawdbot needs microphone access to record audio with video clips.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Clawdbot needs location access to share your location with your AI assistant when requested.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Clawdbot can share your location even when the app is in the background.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Clawdbot may save captured photos and videos to your library.</string>
```

For screen recording, you'll need to use `ReplayKit`.

---

## Xcode Project Setup

When creating the Xcode project:

- **Product Name**: ClawdbotNode
- **Team**: Your Apple Developer account (or Personal Team for testing)
- **Organization Identifier**: com.clawdbot (or your own)
- **Bundle Identifier**: com.clawdbot.node (auto-generated)
- **Interface**: SwiftUI
- **Language**: Swift
- **Storage**: None (we'll use UserDefaults/Keychain directly)
- **Include Tests**: Optional

**Deployment Target**: iOS 16.0+ (for modern async/await and WebSocket APIs)

**Capabilities to add** (in Signing & Capabilities):
- Background Modes → Background fetch (for potential future push-triggered location)
- Keychain Sharing (optional, for secure token storage)

---

## Project Structure (Suggested)

```
ClawdbotNode/
├── ClawdbotNode.xcodeproj
├── ClawdbotNode/
│   ├── App/
│   │   ├── ClawdbotNodeApp.swift
│   │   └── ContentView.swift
│   ├── Gateway/
│   │   ├── GatewayClient.swift          # WebSocket connection
│   │   ├── Protocol/
│   │   │   ├── Messages.swift           # JSON message types
│   │   │   ├── DeviceIdentity.swift     # Keypair + signing
│   │   │   └── Commands.swift           # Command handling
│   ├── Capabilities/
│   │   ├── CameraCapability.swift
│   │   ├── CanvasCapability.swift
│   │   ├── ScreenRecordCapability.swift
│   │   └── LocationCapability.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── AppSettings.swift            # UserDefaults wrapper
│   ├── Canvas/
│   │   └── CanvasWebView.swift          # WKWebView wrapper
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
└── README.md
```

---

## Key Implementation Notes

### 1. WebSocket Library
Use `URLSessionWebSocketTask` (native) or a library like `Starscream`.

### 2. Foreground Requirement
Camera, canvas, and screen commands **only work when the app is in the foreground**. Check `UIApplication.shared.applicationState` and return `NODE_BACKGROUND_UNAVAILABLE` if backgrounded.

### 3. Reconnection
Implement automatic reconnection with exponential backoff. The gateway expects nodes to stay connected.

### 4. Keepalive
The gateway may send periodic pings. Respond to WebSocket pings automatically. The protocol `policy.tickIntervalMs` (default 15000ms) indicates expected heartbeat frequency.

### 5. Token Persistence
Store the device token in Keychain. Use it on subsequent connects to skip re-pairing.

### 6. Base64 Payload Limits
Photos and videos must be encoded as base64. Keep payloads under 5MB for photos. Videos are clamped to 60 seconds. Recompress if needed.

### 7. Permissions Map
Include current permission states in the connect request so the gateway knows what's available:
```json
"permissions": {
  "camera.capture": true,
  "screen.record": false,
  "location": true
}
```

---

## Testing

Once built, test with:

```bash
# Check if gateway is running
clawdbot gateway status

# See connected nodes
clawdbot nodes status

# Approve pairing (when iOS app first connects)
clawdbot devices list
clawdbot devices approve <requestId>

# Test camera
clawdbot nodes camera snap --node <ios-node-name>

# Test location
clawdbot nodes location get --node <ios-node-name>
```

---

## Reference: Existing macOS Node

The macOS companion app already implements this protocol. You can reference how it works:
- It's a menubar app
- Connects to the gateway WebSocket
- Exposes camera, canvas, screen, location, notifications
- Shows in `clawdbot nodes status` when connected

---

## Questions?

If you need more protocol details:
- Check `/opt/homebrew/lib/node_modules/clawdbot/docs/`
- Run `clawdbot --help` for CLI reference
- The source is at https://github.com/clawdbot/clawdbot

---

**Build this as a native Swift/SwiftUI app. Use modern iOS patterns. Make it clean and reliable.**
