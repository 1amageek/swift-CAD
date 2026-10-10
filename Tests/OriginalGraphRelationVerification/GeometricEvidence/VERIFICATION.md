# Issued Graph Geometric Publication Verification

## Scope and contracts

Consume complete source/DI-bound L5 relations once, preserve all auxiliary lifts,
compute original-parameter image/fiber strata, transport isolated tuples forward
to authored parameters, and publish immutable evidence through the existing CS/SSI
rich result types. The explicit `intersectionResult(exactRelations:...)` port has
`representation == .exactRelation`. Numerical arrays are not requested on that port;
read `originalIssuedGeometricRelation.exactPoints` and `pairs` for complete evidence.
Existing numerical shape dispatch, point Codable and numerical arrays retain their
behavior. This does not complete automatic numerical migration, all source families,
DI M4-M7 or any whole seven/full-87 requirement.

## Behavioral coverage

| Groups / product | Invariants |
|---|---|
| GraphProof 0-5 | Original source/DI/L5 composition, guards, forward parameter selection, owner/depth, independent limits and cancellation |
| GraphProof 6-8 | Native and positive-q offset exact CS points, positive-dimensional SSI image and complete station fiber |
| GraphProof 9-10 | Two/free auxiliary witnesses project to one original tuple; exact lift membership, not auxiliary fiber dimension |
| GraphProof 11,13 | Whole-cell affine image rank after complete existential projection; nonlinear auxiliary constraints retained |
| GraphProof 12 | Complete exclusion, exact work/storage ceilings, point refusal and terminal cancel |
| IssuedGraphProof 6,7,8,12,14 | Actual CADCore/CADGeometry public CS/SSI ports; wrong kind, exact isolated/positive/empty receipts, final publication cancel, source/point lifetime after input/result release |
| GeneralGraphProof | General nonlinear XYZ pullback and exact station fiber without affine/finite-map shortcuts |
| NativeExactGeometricProof | Existing public-cs-weighted and public-ssi-endpoints numerical regression |

All runtime commands have outer bounds at most 120 seconds. Native Swift Testing
runs three focused groups; its source group passed with the earlier stricter one-minute
per-case annotation and is reused. Publication/fiber groups pass with two-minute
annotations, matching the unchanged outer 120-second bound. Library work/storage/
degree/depth/result limits and tolerances are unchanged.

## Configuration and evidence

Use Swift6.4.0 release and matching wasm/wasm-embedded SDKs; commands and identities
are retained in each lane's logs/result.json. WASI uses Node24.19.0 and Preview1.
`inputs.json` records project-owned sources of the consumed targets. Products and
runtime commands are independently hashed/recorded. swift-collections remains the
existing exact1.5.1 dependency (revision fea17c02d767f46b23070fdfdacc28a03a39232a).
The original independent package premise is retained because GeneralGraphProof was
added after its fourteen-case run; original target definitions and consumed source
bodies are unchanged. No old proof is inferred from a new source body.

ASAN public entries execute full CADGeometry in debug WMO. L6-only group13 exceeded
120 seconds in that configuration and is not acceptance evidence. Its unchanged
production math executes successfully in the existing optimized isolated ASAN
GraphProof artifact; public-asan/result.json records that artifact and the distinct
command. The supporting optimized build and failed diagnostic are retained separately.
GeneralGraphProof also runs under optimized isolated ASAN. No debug-ASAN performance
success is claimed for group13.

`diagnostic-*` directories and the partial `asan` directory retain failed compile/
wall-clock attempts; these are not acceptance. Three simultaneous full cold builds
caused memory pressure; final full builds were serialized, preserving caches.
The runners now stop detached SwiftPM compiler descendants on timeout.

## Scoped review

One whole change review followed the actual source receipt -> L5 -> L6 -> authored
transport -> public result path. It checked projected topology, lift attribution,
whole-cell affine ranks, XYZ pullback, exact station constraints, atomic limits,
source lifetime and unconditional protocol requirements. The source assumption that
all auxiliary witnesses represent one authored position is explicit in the L6 design;
L5 alone does not establish that authored semantic guarantee.

Findings closed: projected-station membership imports original values into the deeper
compatible coefficient field; isolated points retain actual source/DI owners outside
the enclosing result; continuous-component endpoints are not published as isolated
points; generated merged proof buffers and elimination scratch are admitted; general
XYZ pullback has its own successful behavioral proof. Finding-specific confirmation
is recorded with the stable cases; no additional review cycle is required.

| Logical state | Native / WASM / Embedded storage | Access / release |
|---|---|---|
| Source, coefficients, DI, L5 | Same immutable retained owners | Protocol getters; result/point ownership retains all premises |
| L6 strata, graph, fibers | Same immutable COW values and owner-bound cells | Read-only views/handles; no global mutable cache |
| Query scratch and admission | Exclusive invocation-local values | Same inout budget and final checkpoint; no target-specific synchronization weakening |

No new unsafe pointer or shared mutable state is introduced. No conditional Sendable,
no-op lock, raw Embedded state or runtime-metadata existential extension call is added.

## Entry-point isolation confirmation

Embedded synchronous `main` was required to retain MainActor isolation. The original
harness placed closures directly in `main`, causing actor-context diagnostics even
though they capture only local immutable/scratch proof values. Each changed harness
now delegates to an explicitly nonisolated synchronous runner. Production isolation,
Sendable, storage and algorithms are unchanged. Original entry source bodies and prior
lane inputs/logs are retained; `entrypoints.py` checks the modifier/delegation-only
transformation and all unchanged production premises before recompiling only that
entry module. Its fresh cases confirm argument handling, successful publication and
failure/cancel behavior. Unchanged math coverage remains valid under its recorded
original harness. The ASAN offset repeat timed out under concurrent compiler load;
the prior successful full-module ASAN offset proof remains the unchanged math evidence,
with its original wrapper retained. This is not a new ASAN performance claim.

The actual full Embedded package compiled CADCore/CADGeometry and fixtures through
SwiftPM, but repeated whole-package planning invalidated completed WMO modules.
`resume_embedded.py` retains the original build plan, prebuilt source/object hashes,
compile/wrap commands and quoted complete object response list. It executes only the
remaining exact nodes. The final entry compile has a 360-second build-only bound;
runtime bounds and all query limits remain unchanged. Diagnostic cold-build, isolation
and concurrent-timeout attempts are preserved separately.

## Final lane results and main integration

| Environment | Accepted behavior |
|---|---|
| Native | Fourteen independent fixtures, general nonlinear graph, nine actual-module groups and two unchanged numerical regressions |
| ASAN | Five actual public groups with full debug CADGeometry; auxiliary groups and general nonlinear graph use the separately recorded debug/optimized coverage described above |
| Ordinary WASM | Fourteen independent fixtures, general nonlinear graph and nine actual-module groups |
| Embedded WASM | Fourteen independent fixtures, general nonlinear graph and nine actual-module groups; final nonisolated-runner entries have no actor-context diagnostics |

Every accepted source manifest and current product hash matches the final snapshot.
The original entry-point math runs and fresh isolated-runner confirmations retain
separate records; their production math/source premises are unchanged. No timeout or
diagnostic attempt is acceptance evidence. Independent latest-main composition at implementation commit `4390d60f` succeeds
against main `8ef7d7a2` with no source adjustment. `integration/result.json` binds all
eleven lane manifests and current artifacts; seven fresh Native processes exercise
the actual prepared public CS/SSI ports and unchanged numerical CS/SSI regressions
from that independent checkout. The accompanying integration-record commit closes
normal fast-forward main delivery. Foreign worktrees and their changes are preserved.
