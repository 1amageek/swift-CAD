# Native M2 and M3 production verification

The frozen source snapshot in `receipt.json` was compiled with Swift 6.4.0 release. The actual CADCore and CADGeometry production modules were used, rather than substitute geometry implementations. The inventory binds 1,695 declared source inputs, 1,763 actual compiler inputs, both executable hashes and retained runtime logs. All declared input hashes were checked again before committing.

| Scope | Behavioral evidence |
|---|---|
| M2 finite Native CS/SSI | Every positive span, strict/closed/singleton/disconnected/excluded requests, independent periodic axes, original tuples and chart sides, complete empty results, retained owners and injected issuers |
| M2 resource and failure contracts | Independent work/storage/depth/cell/component/map/pair ceilings, early and final cancellation, recursive publication failure classification |
| Folded SSI | 45 cells and 108 attachments under the unchanged 80,000,000-work, 1-GiB-storage and depth-32 limits |
| M3 actual providers | Authored line authority, saved-N plane evaluation/UV, analytic primitives, physical phases and selected source branches |

The final M2 runtime took 6.582 seconds; M3 took 0.146 seconds. Each build/runtime command has a 120-second timeout and a four-job compiler limit. Failed development commands are retained in `attempts.json`; total recorded development command time was 178.447 seconds. The final four commands passed. Dedicated incremental build storage was reused.

One scoped implementation review and its finding confirmation completed. The depth-limit fixture now requires an irrational root rather than a stationary rational value that legitimately needs no refinement. Resource refusal assertions verify the production error category. Publication mapping covers wrapped source/domain cancellation and budget failures. No unresolved finding remains in M0–M3.

The independent source/domain proof, including Native/ASAN 24 behavioral tests and ordinary/Embedded WASM runtime, is recorded in `../../../OriginalDomainIdentityVerification/M2M3Evidence/`. That evidence does not claim that these full Geometry executables ran on WASM. This Native production evidence does not complete general XYZ publication, infinite family consumers, M4–M8, the seven intersection requirements or all 87 requirements. Latest-main composition is a separate integration gate.
