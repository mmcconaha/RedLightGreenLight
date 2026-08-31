// Encrypts/decrypts Apple ID app-specific passwords for storage in
// apple_credentials.encrypted_password. Server-only — never imported by
// anything that runs in the browser, and the key itself must never be
// NEXT_PUBLIC_.
//
// Requires APPLE_CRED_ENCRYPTION_KEY: a 64-character hex string (32 raw
// bytes) in .env.local / Vercel. Generate one with:
//   openssl rand -hex 32
import crypto from "crypto";

function getKey(): Buffer {
  const hex = process.env.APPLE_CRED_ENCRYPTION_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error(
      "APPLE_CRED_ENCRYPTION_KEY is missing or not a 64-character hex string. Generate one with: openssl rand -hex 32"
    );
  }
  return Buffer.from(hex, "hex");
}

/** Returns "iv.authTag.ciphertext", each base64. */
export function encryptSecret(plaintext: string): string {
  const key = getKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return [iv.toString("base64"), authTag.toString("base64"), ciphertext.toString("base64")].join(".");
}

export function decryptSecret(stored: string): string {
  const key = getKey();
  const parts = stored.split(".");
  if (parts.length !== 3) throw new Error("Malformed encrypted secret");
  const [ivB64, authTagB64, ciphertextB64] = parts;
  const iv = Buffer.from(ivB64, "base64");
  const authTag = Buffer.from(authTagB64, "base64");
  const ciphertext = Buffer.from(ciphertextB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return plaintext.toString("utf8");
}
