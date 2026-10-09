# Final M0–M3 main composition

Snapshot `a6799f0f` incorporates main `71e58b4f`, including its plane-torus private tracing retirement, after the first verified composition `f4cb18b1`. The merge retained the M3 saved-normal admission precondition and introduced no conflict or new contract.

The same owned incremental build cache compiled actual CADCore/CADGeometry and ran both public Native proof executables with Swift 6.4.0 release. Final command results (seconds, exit code): `[(14.523, 0), (2.209, 0), (6.602, 0), (0.66, 0)]`. Four compiler jobs and 120-second per-command limits remain unchanged. All commands passed; folded SSI and original domain/provider fixtures retain their original limits and guarantees.

`receipt.json` binds the full production source/compiler inputs and executable hashes. `integration.json` confirms byte-identical production inputs in the separate integration worktree and verifies the executable hashes used for runtime evidence. The identical final snapshot is not executed redundantly from another directory. All 344 inputs in each lower Native/ASAN/WASM/Embedded proof remain unchanged, so their evidence remains valid within its original scope.

M0–M3 are reviewed, implemented, verified and delivered in the accompanying commit. General XYZ/infinite-family publication, M4–M8 and the full seven/87 requirements remain open. No whole-Geometry WASM/Embedded runtime claim is made from the lower proof.
