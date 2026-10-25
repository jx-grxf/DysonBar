# Security

## What DysonBar stores

- **Device Wi-Fi key**: one per purifier, in the macOS login Keychain (service `dyson-bar`, account = serial number).
- **Device list**: name, model, serial number and an optional fixed address in `~/Library/Application Support/DysonBar/devices.json`.
- **History**: sensor values per minute for seven days in `~/Library/Application Support/DysonBar/History/`.

Your MyDyson password and the account token are used once during sign-in and never written to disk.

## What goes over the network

- **Sign-in**: HTTPS requests to Dyson's app API (`appapi.cp.dyson.com`, or `.cn` for mainland China) to request the email code and fetch the device list.
- **Everything else**: MQTT on port 1883 between the Mac and the purifier on your local network.
- **Updates**: Sparkle checks `github.com/jx-grxf/DysonBar` once a day. Updates are EdDSA-signed.

## Known limitation

Dyson's purifiers only offer unencrypted MQTT on the local network, and they don't prove their identity. Anyone who can read traffic on your Wi-Fi can see the device key and control the purifier, with or without DysonBar. DysonBar reduces exposure where it can: it only connects to the address that worked last time, the serial number as hostname, or a Bonjour service whose name matches the device exactly. Keep purifiers on a network you trust.

## Reporting a problem

Please report security issues privately through [GitHub's security advisories](https://github.com/jx-grxf/DysonBar/security/advisories/new) instead of a public issue.
