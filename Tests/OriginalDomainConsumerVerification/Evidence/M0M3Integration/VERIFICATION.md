# M0–M3 latest-main integration

The independent integration worktree composes main `a87b7853` and implementation commits `e6e33d62`, `e2e99a9b`, `06f9d8da` at merge snapshot `f4cb18b1`. This preserves concurrent coordinate-transfer storage repair and constant-coordinate optimization. No merge conflict or source repair was needed.

The actual production CADCore/CADGeometry source was incrementally compiled and both Native public proof executables ran successfully. The recorded command results (seconds, exit code) are `[(16.388, 0), (1.99, 0), (6.561, 0), (0.65, 0)]`. The four-job compiler and 120-second per-command ceiling are retained; no Kernel/Rupa target is compiled. `receipt.json` binds all 1,695 source inputs, actual compiler inputs, artifacts and logs for the composed snapshot.

`integration.json` records exact source equality in the independent integration checkout and execution of the same hashed artifacts from that checkout. Both public runtimes passed again. This reuse avoids recompiling byte-identical source in a fresh build directory; these are Native runtime proofs, not fresh compilation at the integration path.

All 344 retained inputs for each Native, ASAN, ordinary WASM and Embedded WASM lower proof also match the composed checkout. Their existing behavioral evidence is reused only within that unchanged source/domain scope. Full Geometry WASM publication is not inferred from those proofs.

The scoped aggregate review and its finding confirmation were completed before commit. Integration introduced no contract change requiring another review cycle. M0–M3 are complete; M4–M8, general XYZ/infinite-family consumers, the full seven intersection requirements and all 87 requirements remain open.
