# Core Portability Proof

## Purpose and Scope

This component verifies the actual complete CADCore module and its registered
HashTreeCollections dependency on fixed Swift 6.4.0 Native, normal WASM and
Embedded WASM. Parent: [Core Portability Smoke](../DESIGN.md). It has no children.
It is a prerequisite proof, not a substitute for full Embedded A2.

## Responsibilities and Boundaries

The smoke uses public Core producers and validation, actual target math,
original typed errors, immutable identity/lineage and PersistentMap COW. The
Native/normal codec branch uses Foundation's actual JSONEncoder/JSONDecoder.
Embedded executes the same common value proof and explicitly reports that the
Codable adapter is unavailable. No primitive source extraction, proxy type,
private replacement codec or new geometry algorithm is used.
The proof directly imports the registered HashTreeCollections product when
calling PersistentMap's TreeDictionary operations and Sendable conformance.
Embedded specialization requires that defining module at the call site; this
does not replace or extract the production map owner.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core Portability Smoke](../DESIGN.md) | parent | Joined proof entry and product/SDK ownership | Invokes the common and available codec proofs | Fixed SDK/runtime and bounded build lane are required |
| [Native Codec Capability](../../CADCore/NativeCodecCapability/DESIGN.md) | depends on | Common values and explicit codec boundary | Supplies the exact producer bytes under verification | All Core production sources and the dependency remain in the graph |
| [Failure Contract](../../CADCore/FailureContract/DESIGN.md) | depends on | Typed domain/KernelError mapping | Proves failures remain failures | No catch-all success or message parsing |

## Architecture

```text
ProbeEntry -> CorePortabilityProof -> public CADCore -> HashTreeCollections
                              \-> actual Native/normal JSON adapter
```

## Contracts and Invariants

The common path checks literal vector length and overflow-safe normalization,
points/matrix/quantity/unit behavior, original straight profile/Bezier laws,
typed refusal and error normalization, exact lineage references and real COW.
Native/normal literal wire checks cover coordinate keys, single-array matrix,
explicit expression discriminators and strict unexpected-key failure. The
Embedded unavailable-codec marker records capability, never encoded output.

The diagnostic proof exercises the [Failure Contract](../../CADCore/FailureContract/DESIGN.md)
target-presentation boundary using independent associated-value literals: scalar
tolerances, schema components, tagged identities, an ordered cycle with a duplicate,
vector coordinates, resource counts and source strings. Embedded checks the
explicit structural presentation; Native/normal checks the original reflected
payload. A foreign error retains unclassifiedFailure, with the explicit Embedded
reflection limitation. A fully populated KernelError must preserve all seven
fields despite different fallback context. Each target completes these checks
before `CORE_DIAGNOSTIC_PRESENTATION_OK`.

The linear natural-continuation fixture retains the independent endpoint x=3,
exact y=0 and exact count=1. Its x comparison uses 1e-12, stricter than the
unchanged producer's modeling-distance postcondition after Gauss integration
and Newton solving. The first unverified bit-exact x oracle was invalid for
that numerical contract; its recorded failure is a fixture failure, not an
implementation failure. Runtime reports the actual x difference.

## Runtime Flows

Common proof completes before its markers; codec proof completes before its
Native marker. Any wrong value or error aborts the executable. Current-task
cancellation uses the production witness and a joined task; no task escapes.

## State, Ownership, and Lifecycle

All fixture state is local, owned value state. The same Core fields, COW backing
and Sendable contract are used on every target. The entry owns and joins its
cancellation task. There is no mutable global, callback, stream or shutdown
resource. Native codec instances are local to the capability branch.

## Failure, Concurrency, and Constraints

Fixture errors throw. Source domain errors must match their expected typed
reason. Runtime commands have an outer 120-second limit; pure builds use the
root lane's explicit deadline. SDK/backend failures are not successful markers.
The fixture has finite literal inputs and adds no new production limits.

## Verification and Change Impact

Run the actual registered product using the fixed Native toolchain and both
matching WASM SDKs. Record complete source/dependency/PIF/product/command/runtime
identity. The common markers must appear on all targets; native codec success
is required only on Native/normal WASM. Embedded must use its own SDK and raw
artifact. Parent A2 proof, source-envelope persistence and other modules remain
separate verification owners. Root owns product registration and build lanes.
