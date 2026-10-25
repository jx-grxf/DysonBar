#!/usr/bin/env python3
"""Fetch the local MQTT credentials for every Dyson device on a MyDyson account.

The password goes straight into the login Keychain (service "dyson-bar",
account = serial). Non-secret device data lands in
~/Library/Application Support/DysonBar/devices.json.
"""
import base64
import getpass
import json
import pathlib
import subprocess
import urllib.parse
import urllib.request
from typing import Any

API = "https://appapi.cp.dyson.com"
PARAMS = urllib.parse.urlencode({"country": "DE", "culture": "de-DE"})
HEADERS = {"User-Agent": "android client", "Content-Type": "application/json"}
# Fixed key from the Android app; every client (libdyson, opendyson) uses the same one.
AES_KEY = bytes(range(1, 33)).hex()
AES_IV = "00" * 16
KEYCHAIN_SERVICE = "dyson-bar"
CONFIG_DIR = pathlib.Path.home() / "Library/Application Support/DysonBar"


def call(method, path, body=None, token=None, query=True) -> Any:
    url = f"{API}{path}" + (f"?{PARAMS}" if query else "")
    headers = dict(HEADERS)
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else None


def decrypt(encrypted_b64):
    out = subprocess.run(
        ["openssl", "enc", "-d", "-aes-256-cbc", "-nopad", "-K", AES_KEY, "-iv", AES_IV],
        input=base64.b64decode(encrypted_b64),
        capture_output=True,
        check=True,
    ).stdout
    # Some devices append a second JSON blob after the first one.
    return json.JSONDecoder().raw_decode(out.decode().rstrip("\b\x00"))[0]


def store_password(serial, password):
    subprocess.run(
        ["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE,
         "-a", serial, "-l", f"Dyson {serial}", "-w", password],
        check=True,
    )


def main():
    call("GET", "/v1/provisioningservice/application/Android/version", query=False)

    # Typing "@" fails in some terminal setups, so "name at domain" works too.
    email = input("MyDyson E-Mail (statt @ geht auch ' at '): ").strip()
    email = email.replace(" at ", "@").replace("(at)", "@")
    challenge = call("POST", "/v3/userregistration/email/auth", {"email": email})
    print("Dyson hat dir einen Code per Mail geschickt.")
    otp = input("Code aus der Mail: ").strip()
    password = getpass.getpass("MyDyson Passwort: ")

    login = call("POST", "/v3/userregistration/email/verify", {
        "challengeId": challenge["challengeId"],
        "email": email,
        "otpCode": otp,
        "password": password,
    })
    token = login["token"]

    devices = call("GET", "/v3/manifest", token=token, query=False)
    saved = []
    for device in devices:
        serial = device.get("serialNumber")
        mqtt = (device.get("connectedConfiguration") or {}).get("mqtt") or {}
        if not serial or not mqtt.get("localBrokerCredentials"):
            print(f"übersprungen: {device.get('name') or serial} (kein lokales MQTT)")
            continue
        creds = decrypt(mqtt["localBrokerCredentials"])
        store_password(serial, creds["apPasswordHash"])
        saved.append({
            "serial": serial,
            "name": device.get("name"),
            "type": device.get("type"),
            "model": device.get("model"),
            "variant": device.get("variant"),
            "mqttRootTopic": mqtt.get("mqttRootTopicLevel"),
            "remoteBroker": mqtt.get("remoteBrokerType"),
        })
        print(f"gespeichert: {device.get('name')} {serial} "
              f"(Topic {mqtt.get('mqttRootTopicLevel')})")

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    (CONFIG_DIR / "devices.json").write_text(json.dumps(saved, indent=2))
    print(f"\nFertig. Gerätedaten: {CONFIG_DIR / 'devices.json'}")
    print(f"Passwörter im Keychain unter \"{KEYCHAIN_SERVICE}\".")


if __name__ == "__main__":
    main()
