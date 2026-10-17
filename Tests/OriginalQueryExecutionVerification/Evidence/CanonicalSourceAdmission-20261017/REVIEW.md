# Source review and finding closure

This file indexes completed reviews; packaging did not start another review.
The original records are preserved byte for byte in `proof-records.tar.gz`.
Their issuance-time runtime-pending wording is intentionally retained. The final
accepted indexes and runtime logs supply the subsequently completed target gates.

| Scope | Original record SHA-256 | Outcome |
|---|---|---|
| Core comprehensive review and correction-only confirmation | `2ec6a1b5cacefecf2d86ad01f1d476f5d4af65f6c5ec80ad2932d1d6f0fd02ff` | Wrapper `self.value` shadowing and stale existential wording corrected in R3; no remaining source finding |
| All 481 IR writers, SHA/fingerprint/memo | `155a816fc06f72485f861ade7a1163de8c887b30c3d5e6837705c6b4b8e266d0` | Entry admission before default memo allocation corrected in R2; inverse/allocation finding confirmation closed |
| Sole Kernel codec source | `d7ba069eb2228c74cf2d3e3a793ced4a802137869765eb7ee8f03ef6e8cc746c` | Full original codec schema/order/guards/fees/source ownership reviewed; no source finding at issuance |
| Actual codec shared behavioral fixture | `3d8863b4f730d6e1c6bce4ce4ad7412dc016f0cac88b609124d95c0e3a7f6b52` | Original nonempty cube, real validation, independent content/ID laws and caller resource/cancel/lifetime checks reviewed |
| Actual Embedded direct-import finding | Freeze `c7e58ca258e948387a13b24f07057e02b59920e5019f8e91280f1677d31fa45d` | Root confirmed import-only source inverse; final R2 four-target compile/link/runtime accepted |

Accepted index authority:

- Core: `8b323544670fa8958606e091ff291f6e5f0f998373a06283ad598cde15e353f5`.
- IR: `9a5862719a157174ec6cac1077b7a519fdbd5ec19187674970127214a0daba84`.
- Codec: `617325b767b771d64624975092abefa709feb10800a92668f2aa6d23d2520e32`.

The reviews and actual behavioral gates close this finite encoding/witness unit.
Main source integration is recorded separately in [integration.json](integration.json).
They do not upgrade the pending Section/evaluator/UI/full-Kernel work identified
in [VERIFICATION.md](VERIFICATION.md).
