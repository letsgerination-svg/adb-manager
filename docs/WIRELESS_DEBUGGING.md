# Android Wireless Debugging protocol plan

This document records requirements for Android 11+ (API 30+) Wireless Debugging. It is an implementation plan, not a claim that pairing or TLS transport is already implemented.

## Two separate network connections

Android Wireless Debugging exposes two different TCP services:

1. **Pairing service** — temporary port shown by Android's “Pair device with pairing code” screen. The client connects here and proves possession of the six-digit code.
2. **ADB TLS transport** — separate port shown by the wireless debugging service or discovered through mDNS. This is the port used for later ADB commands.

The pairing port must not be reused as the ADB transport port.

## Pairing protocol (AOSP)

The AOSP pairing implementation performs these steps:

1. Open TCP to the pairing port.
2. Complete TLS using a client X.509 certificate and private key. AOSP's pairing code accepts the peer certificate at this stage; the pairing secret authenticates the peer afterward.
3. Export 64 bytes of TLS keying material and append those bytes to the six-digit pairing code before the PAKE step. This binds the pairing exchange to the TLS session.
4. Run SPAKE2 using the roles and context strings used by AOSP (adb pair client / adb pair server).
5. Exchange a versioned pairing header and the SPAKE2 message.
6. Derive the authenticated-encryption key, then exchange encrypted 8192-byte PeerInfo structures. The peer info includes the ADB RSA public key.
7. Persist the peer identity/certificate information required for subsequent TLS ADB connections.

Pairing packet header is packed and contains:
- version: 1 byte (current version 1)
- type: 1 byte (SPAKE2_MSG = 0, PEER_INFO = 1)
- payload: 4-byte big-endian payload length

The SPAKE2 message is not a substitute for TLS. Both layers are required by the AOSP protocol.

## Subsequent ADB TLS transport

After pairing, connect to the distinct ADB TLS port. The ADB transport begins with the ADB wire protocol and upgrades to TLS using the STLS command. The TLS 1.3 peer certificate is checked against the paired ADB identity. Once the TLS transport is established, normal ADB packets (CNXN, OPEN, OKAY, WRTE, CLSE) are carried inside TLS.

The existing ADBSession implements the legacy plaintext TCP + RSA AUTH path only. It does not yet implement the STLS upgrade, TLS certificate verification, or Android 11+ pairing.

## Required implementation components

- A maintained BoringSSL-compatible implementation for AOSP-compatible SPAKE2 and TLS key exporter support. CryptoKit alone does not expose the AOSP SPAKE2 primitive or the exact TLS exporter interface needed here.
- iOS TLS client certificate/private-key handling and X.509 certificate creation.
- A pairing packet codec with strict version/type/length validation and bounded payloads.
- AOSP-compatible SPAKE2 roles/context strings and authenticated-encryption framing.
- Secure persistence of the generated ADB identity and paired peer metadata.
- A separate TLS ADB transport that performs STLS and validates the paired peer.
- UI fields/actions for pairing IP, pairing port, six-digit code, and later ADB connect port.

## Acceptance tests

1. Pairing packet codec tests: valid headers, unsupported version/type, truncated header, oversized payload.
2. Cryptographic interoperability test against an AOSP adb pair implementation using a test pairing code.
3. Verify a wrong pairing code fails without persisting a peer.
4. TLS transport interoperability test against Android Wireless Debugging.
5. Run shell commands after pairing and reconnect successfully using persisted credentials.
6. Verify legacy RSA/TCP mode remains separate and continues to work on devices explicitly configured for adb tcpip.

## AOSP references

- pairing_connection.cpp: TLS setup, 64-byte TLS exporter binding, SPAKE2 exchange, and encrypted peer-info exchange.
- pairing_auth.cpp: SPAKE2 roles/context and authenticated-encryption setup.
- pairing.proto: packet type values.
- pairing_connection.h: peer-info structure and pairing API contract.
- transport.cpp: TLS transport certificate handling and ADB transport setup.

The implementation must be validated against AOSP source and real Android devices; matching packet names alone is not sufficient.
