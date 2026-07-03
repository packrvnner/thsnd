# THSND — Base MAINNET Deployment (current) — July 2, 2026

Brand migration: MUY → **Thousand ($THSND)**. Same code (renamed strings/identifiers), same Safe treasury.

**Treasury + owner of all contracts: Safe `0x539DE6F65dECEB2F491237e3DC030494E517877C`**

| Contract | Address |
|---|---|
| THSND (token, name "Thousand") | `0xF7aa829ed31fE30834E56348e9CD3fBb4687CFdb` |
| LatticeLock (Vault, vTHSND) | `0x1141F662b0647C2776Bb6A59B0ECA3Db481e6847` |
| BurnEngine | `0x81929143c44a8141A1d2C40dB3774F1B262674D2` |
| TierRegistry (T1/T10/T100/T1000) | `0x4056179e23E87d88f76381df54e458E529fdf7BA` |

Verified on-chain: name "Thousand", symbol "THSND", 1,000,000,000 supply 100% in Safe, all owners = Safe. Source verified via Sourcify. Site cut over: muyprotocol.netlify.app points at these addresses. Tests 16/16 at deploy commit.

## Superseded deployment (abandoned, NOT compromised)

The original MUY suite (`0xC665637C9d25efaccee5F1beEe5520Ec707a9ce1` + peers, see base-mainnet.md) remains on-chain — immutable contracts can't be deleted. All 1B MUY sits in the same Safe and stays there. If anyone ever asks: publish a note that MUY was renamed to THSND pre-launch and the old contract is inert. Watch for scammers picking up the abandoned ticker.

## Status: PRE-LAUNCH — same gates as before

Unaudited. No liquidity, no announcement, no deposits until audit + legal (AUDIT_BOOKING.md is ready to paste). Update the audit submission to reference the THSND addresses and the renamed sources.
