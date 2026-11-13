#!/usr/bin/env python3
"""Derives the BizPOS super admin keys from the master password.

Usage:  python3 tool/admin_key.py "your master password"

Prints:
* the Ed25519 public key to put in lib/core/license.dart (LicenseKeys.trusted)
* the authenticator (TOTP) secret for super admin 2-factor login

The password itself is never stored anywhere. Must match LicenseKeys in Dart:
PBKDF2-HMAC-SHA256, salt "bizpos-super-admin-v1", 60000 iterations, 32 bytes.
"""
import base64
import hashlib
import hmac
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

SALT = b"bizpos-super-admin-v1"
ITERATIONS = 60000


def derive(password: str):
    seed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), SALT, ITERATIONS, 32)
    priv = Ed25519PrivateKey.from_private_bytes(seed)
    pub = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    totp = hmac.new(seed, b"totp", hashlib.sha256).digest()[:20]
    return seed, pub, base64.b32encode(totp).decode().rstrip("=")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    _, pub, totp = derive(sys.argv[1])
    print("public key :", base64.urlsafe_b64encode(pub).decode().rstrip("="))
    print("totp secret:", totp)
