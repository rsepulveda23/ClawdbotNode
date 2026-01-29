# ClawdbotNode - iOS Companion App

A modern iOS companion app for the [Clawdbot](https://github.com/clawdbot/clawdbot) AI gateway system. This app connects to your Clawdbot gateway and exposes your iPhone's capabilities to your AI assistant.

## Features

- **Camera** - Take photos and record video clips on demand
- **Canvas** - Display web content via WebView
- **Location** - Share your device location with configurable precision
- **Screen Recording** - Record screen content using ReplayKit

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Tailscale installed and connected to the same tailnet as your gateway

## Setup

### 1. Install Tailscale
Your iPhone and the Mac running the Clawdbot gateway must be on the same Tailscale network.

### 2. Open in Xcode
```bash
open ClawdbotNode.xcodeproj
```

### 3. Configure Signing
- Select the project in Xcode
- Go to Signing & Capabilities
- Select your development team

### 4. Build and Run
- Connect your iPhone or select a simulator
- Press Cmd+R to build and run

### 5. Configure Connection
The app is pre-configured to connect to:
```
ws://100.122.199.82:18789
```

If your gateway is at a different address, tap Settings and update the Gateway URL.

### 6. Approve the Device
On first connection, the gateway will require approval. On your Mac:
```bash
clawdbot devices list
clawdbot devices approve <requestId>
```

## Project Structure

```
ClawdbotNode/
├── App/
│   ├── ClawdbotNodeApp.swift     # App entry point
│   └── ContentView.swift          # Main UI
├── Gateway/
│   ├── GatewayClient.swift        # WebSocket connection
│   └── Protocol/
│       ├── Messages.swift         # JSON message types
│       └── DeviceIdentity.swift   # P-256 keypair management
├── Capabilities/
│   ├── CameraCapability.swift     # Photo & video capture
│   ├── LocationCapability.swift   # GPS/location services
│   └── ScreenRecordCapability.swift # ReplayKit recording
├── Canvas/
│   └── CanvasWebView.swift        # WKWebView wrapper
├── Settings/
│   ├── AppSettings.swift          # UserDefaults storage
│   └── SettingsView.swift         # Settings UI
└── Resources/
    ├── Info.plist                 # App permissions
    └── Assets.xcassets/           # App icons & colors
```

## Supported Commands

| Command | Description |
|---------|-------------|
| `camera.list` | List available cameras |
| `camera.snap` | Take a photo |
| `camera.clip` | Record a video clip (max 60s) |
| `canvas.present` | Show a WebView with URL |
| `canvas.hide` | Hide the WebView |
| `canvas.navigate` | Navigate to a URL |
| `canvas.eval` | Execute JavaScript |
| `canvas.snapshot` | Capture WebView as image |
| `location.get` | Get device location |
| `screen.record` | Record screen (max 60s) |

## Testing

Once connected, test from your Mac:
```bash
# Check if node is connected
clawdbot nodes status

# Take a photo
clawdbot nodes camera snap --node ios-node

# Get location
clawdbot nodes location get --node ios-node
```

## Design

The app features a modern dark UI with:
- Gradient backgrounds
- Animated connection status orb
- Capability cards with live status
- Real-time activity log
- Clean settings interface

## Protocol

Uses WebSocket with JSON text frames. Protocol version 3.

Connection flow:
1. Connect to gateway WebSocket
2. Receive `connect.challenge` with nonce
3. Sign nonce with device P-256 key
4. Send `connect` request with signature
5. Receive `hello-ok` with device token
6. Handle `node.invoke` requests

## License

MIT
