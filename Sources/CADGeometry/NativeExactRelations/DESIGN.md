# Native Exact Relations

## Purpose and Scope
Parent: [CADGeometry](../DESIGN.md). Connect the independent L0-L5 foundation to
actual authored B-spline CS/SSI inputs in the existing production module. The
bounded input is finite, nonperiodic, positive-weight, source-valid, with exactly
one positive knot span per axis. No new production package or module is added.

## Responsibilities and Boundaries
This component owns source extraction, exact coefficient transport and closed
native/request domain intersection. The common OriginalSourceIssuance component owns the retained original Native
local law and its basis semantics. L5 owns equations and complete parameter topology. Public
`exactParameterRelation` requirements and the existing default intersectors return
a source-bound receipt; this explicit query accepts an L0 admission and lower
limits. Existing `intersectionResult` XYZ representatives, classification and
image/fiber publication are unchanged: parameter dimension does not establish
geometric dimension. The new query does not run the legacy solver or post-process
its roots. Unsupported source coverage is a typed failure, never a fallback.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Native source types and public intersectors | Actual production integration | Preserve existing numerical APIs |
| [Source Issuance](../OriginalSourceIssuance/DESIGN.md) | depends on | Native bindings, selected local laws and source/parameter receipts | Exact stored source authority | Preserve currently admitted finite single-span coverage |
| [L0](../RationalBivariateAlgebra/ExactScalar/DESIGN.md) | depends on | Scoped numeric admission, exact import | One exclusive caller ledger | Checked words-to-bytes |
| [L1](../RationalBivariateAlgebra/ExactPolynomial/DESIGN.md) | depends on | Checked ordered construction | Retain final canonical terms | Strict descending slot order and exact nonzero validation |
| [L5](../RationalBivariateAlgebra/ExactParametricRelation/DESIGN.md) | depends on | Compile, resolve and tuple membership | Complete parameter relation | Preserve denominator guards and all UV |
| [Verification](../../../Tests/NativeExactRelationVerification/DESIGN.md) | test owner | Full production Core/Geometry | Public Native and WASI routes | No subset build as integration evidence |

## Architecture
```mermaid
flowchart LR
 Q[Existing intersector exactParameterRelation] --> N[Native source and closed request]
 N --> H[Common original source issuer]
 H --> T[Exact coefficient and domain transport]
 T --> L[L0-L5 complete relation]
 L --> R[Immutable original source and parameter receipt]
 A[One caller admission] --> H
 A --> T
 A --> L
 A --> R
```

## Contracts and Invariants
- Validate input and degree before indexed source access. Count every visited knot
  with the same admission; require one positive span on each entire native axis.
- Import original rational coefficients directly into one shared L2 coefficient
  field. Do not convert coefficients to Double or use tolerance to assert equality.
- Requested bounds are finite ordered stored binary64 values. Clip with exact
  ordering of those values. Out-of-domain selections become L2 empty domains;
  singleton and native closed endpoints remain closed. The original requested
  bounds remain retained even when the effective domain is empty.
- Preserve all selected tuples, closure/incidence and denominator guards. Empty
  success includes L5 full exclusion evidence, never just an empty point array.
- Return source snapshots by value. COW buffers and proof owners survive original
  input release/mutation. One field is shared by both map sources and result.
- All extraction, preparation, import, resolution, result reservation and final
  checkpoint use the same admission. No internal budget defaults/resets exist.
- Explicit caller degree/extension, L3 cell/root and L4 closure/piece/component
  ceilings remain independent. Preparation failure aborts the query atomically.

## Runtime Flows
Validate and admit source -> issue original homogeneous laws -> import exact laws
and clip domains -> compile CS/SSI relation -> resolve L3/L4 -> reserve complete
source-bound result -> terminal cancellation -> publish. Later membership queries
receive their own explicit admission and consume retained L5 receipts.

## State, Ownership, and Lifecycle
Only invocation-local arrays mutate. No shared mutable state, cache, unsafe pointer
or callback owner is introduced. The source issuer receives the exact same exclusive admission directly. The
prepared map retains its source-law receipt through compilation and resolution.
Publication transfers its original immutable COW snapshot to the existing
NativeExactRelationSource and its exact polynomials/domains to the retained L5
owner. No private binding identity is advertised by this existing facade, and
no new stored field or result ABI is introduced.
All published owners and Sendable contracts are identical across targets.

## Failure, Concurrency, and Constraints
NativeExactRelationFailure preserves scalar, root, cell, L5 and original geometry
causes, plus explicit unsupported coverage and invalid request/degree failures.
No caught error is interpreted as empty, absence or applicability fallback.

## Verification and Change Impact
Compile all production CADCore/CADGeometry sources together and execute public
CS/SSI weighted isolation, contact, continuous overlap, multiple UV, endpoint,
singleton, clipped empty, source lifetime and independent failure/cancel paths.
Use fixed Swift 6.4.0 and matching normal/Embedded SDKs. Reuse unchanged lower
proofs; verify optimized L5 composition in this integrated module. Changes to
coefficient/basis, domain or admission contracts require these owning tests.
This milestone is not completion of the full CS/SSI/seven requirement families.
The integrated checkpoint executes the shared public fixtures and unchanged
legacy public smoke in Native, normal WASM and Embedded WASM, plus the shared
fixtures under Address Sanitizer. All lanes compile the complete production
module inventories; [retained evidence](../../../Tests/NativeExactRelationVerification/VERIFICATION.md)
owns exact source hashes, compiler inputs, runtime logs and proof limits.

## Integration Findings Closed
The complete production build exposed the parent/L0 filename collision and the
old provenance writer's geometric root assumption. Both are handled by their
owning parent helpers and scalar-authority provenance record, with actual tests.
Legacy scalar error normalization is specified by the CADGeometry parent and
IntersectionAlgebra designs; no original mathematical result is substituted.
The full existing public portability proof remains required beside this new path.

## Common Issuance Handoff

Preparation binds the actual Native source once, checks the existing degree and
finite nonperiodic single-positive-span coverage contract, and issues its four
homogeneous laws through DefaultOriginalBSplineChartIssuer. The same selected L2
coefficient field enters source arithmetic and the L5 binding. L1's checked import
transfers only the final laws; there is no legacy bivariate coefficient dictionary
or separate ordered-term conversion in this adapter. Source issuance prepares
position only, without differential, normal or silhouette work.

NativeExactPreparedMap retains the issued law and resulting L5 map until the
existing facade publishes its source-bound result. Publication uses the issued
snapshot, not a separately reconstructed source. The existing result retains
original geometry COW buffers and the exact L5 proof/polynomial/domain owners.
The public source/result/Codable representations remain unchanged. Requested
closed-domain intersection remains this component's responsibility; source
issuance does not choose a requested-domain cover or execute a root solver.

The source-only migration has a separate verification scope: independently
compile the changed preparation files and issuer, importing already-validated
cached lower/geometry modules, then exercise actual prepared maps, complete
coefficient identities, retained sources, request clipping and atomic failures.
This fulfills the user's restricted-build instruction without rebuilding upper
targets. It is not a replacement for the recorded whole public CS/SSI evidence,
and does not claim new public coverage or whole-seven completion. Unchanged
lower contracts remain reusable only when the executed premises match.
