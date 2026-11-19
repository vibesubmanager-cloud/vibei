import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def _key_bytes() -> bytes:
    raw = os.environ.get("MASTER_ENCRYPTION_KEY", "")
    if not raw:
        # Local-dev only; production must set MASTER_ENCRYPTION_KEY.
        raw = "local-dev-master-key-not-for-prod"
    return hashlib.sha256(raw.encode("utf-8")).digest()


def encrypt_secret(plaintext: str) -> str:
    if not plaintext:
        return ""
    aes = AESGCM(_key_bytes())
    nonce = os.urandom(12)
    ct = aes.encrypt(nonce, plaintext.encode("utf-8"), None)
    return base64.b64encode(nonce + ct).decode("ascii")


def decrypt_secret(blob: str) -> str:
    if not blob:
        return ""
    raw = base64.b64decode(blob.encode("ascii"))
    nonce, ct = raw[:12], raw[12:]
    aes = AESGCM(_key_bytes())
    return aes.decrypt(nonce, ct, None).decode("utf-8")


def mask_secret(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 4:
        return "****"
    return "••••" + value[-4:]
