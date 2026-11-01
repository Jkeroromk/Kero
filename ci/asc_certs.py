#!/usr/bin/env python3
"""Keeps CI from piling up Apple Development certificates.

Every TestFlight run starts on a fresh Mac with an empty keychain, so Xcode's automatic
signing creates a new Apple Development certificate for the archive step. Apple caps how
many an account can have, so each run revokes the one it created.

Usage (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8):
  asc_certs.py snapshot FILE        save the IDs of the current development certificates
  asc_certs.py revoke-new FILE      revoke development certificates not in FILE (made by this run)
  asc_certs.py revoke-created-on YYYY-MM-DD
                                    revoke development certificates created on that day
                                    (one-time cleanup of earlier runs; opt-in)

This repository is public, so only counts are printed — never names or IDs.
"""

import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token():
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"].strip(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def request(method, url):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token()}"})
    with urllib.request.urlopen(req) as response:
        body = response.read()
        return json.loads(body) if body else None


def development_certificates():
    certificates = []
    url = f"{API}/certificates?limit=200&fields[certificates]=certificateType,expirationDate"
    while url:
        page = request("GET", url)
        certificates += [c for c in page["data"] if c["attributes"].get("certificateType") in DEVELOPMENT_TYPES]
        url = page.get("links", {}).get("next")
    return certificates


def revoke(certificates):
    revoked = 0
    for certificate in certificates:
        try:
            request("DELETE", f"{API}/certificates/{certificate['id']}")
            revoked += 1
        except urllib.error.HTTPError as error:
            print(f"::warning title=Certificates::Couldn't revoke a certificate (HTTP {error.code}).")
    return revoked


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    command, argument = sys.argv[1], sys.argv[2]

    try:
        certificates = development_certificates()
    except urllib.error.HTTPError as error:
        print(f"::warning title=Certificates::Couldn't list certificates (HTTP {error.code}); skipping.")
        return 0

    if command == "snapshot":
        with open(argument, "w") as file:
            json.dump([c["id"] for c in certificates], file)
        print(f"::notice title=Certificates::{len(certificates)} development certificate(s) before archiving.")

    elif command == "revoke-new":
        try:
            with open(argument) as file:
                before = set(json.load(file))
        except FileNotFoundError:
            return 0
        new = [c for c in certificates if c["id"] not in before]
        if new:
            print(f"::notice title=Certificates::Revoked {revoke(new)} development certificate(s) this run created.")

    elif command == "revoke-created-on":
        # Development certificates are valid for one year, so "created on D" means "expires on D + 1 year" (±1 day).
        day = datetime.date.fromisoformat(argument)
        expires = day.replace(year=day.year + 1)
        window = {expires - datetime.timedelta(days=1), expires, expires + datetime.timedelta(days=1)}
        matching = [c for c in certificates
                    if c["attributes"].get("expirationDate")
                    and datetime.date.fromisoformat(c["attributes"]["expirationDate"][:10]) in window]
        print(f"::notice title=Certificates::Revoked {revoke(matching)} of {len(certificates)} development certificate(s) created around {argument}.")

    else:
        print(__doc__)
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
