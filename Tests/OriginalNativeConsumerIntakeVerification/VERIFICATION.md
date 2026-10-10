# Native retained-relation adapter verification

Scope: the shared Native L5 refinement adapter required by M6 intake. This does
not complete face/self, Topology, general M6, M7 or M8. Source, predicate and
raw/refined owners are retained without resolving the original intersection again.

The actual production adapter/result/protocol and failure mapper are compiled
against freshly generated current independent L0-L5, source and DI modules. No
CADCore/CADGeometry/Kernel production target or L6 is built. The existing explicit
independent-regeneration authorization applies. Swift 6.4.0 release and matching
normal/Embedded WASM SDKs are fixed by the driver; ASAN instruments every generated
independent module. Compiler inputs, generation commands, logs, object/module and
product hashes are admitted before runtime and rechecked afterward.

| Lane | Generation inputs | Generated artifacts | Runtime seconds | Result |
|---|---:|---:|---:|---|
| native | 530 | 538 | 1.655 | PASS |
| asan | 530 | 538 | 1.545 | PASS |
| wasm | 530 | 560 | 2.437 | PASS |
| embedded | 530 | 558 | 1.273 | PASS |

The fixture compiles a real complete curve/plane L5 relation and refines the exact
open interval (1/3,2/3). It checks coefficient-field compatibility, algebraic
sqrt(1/3) inclusion, algebraic exclusion, foreign-field failure, every included
raw-cell ordinal, complete empty refinement, strict endpoints, invalid predicate
arity, exact work/storage ceilings and one-less failures. It checks entry/final
query and refinement cancellation, both raw and refined retained-depth refusal,
COW isolation and membership after the construction/source scope has returned.
The last assertion runs after releasing all local construction handles.

Native final acceptance is Evidence/native-release; asan/wasm/embedded are the
other accepted lanes. Evidence/native records the initial fixture main-actor
compile failure; native-accepted records the runtime that exposed wrapped L4
resource failure. Native-final precedes the added release/arity/refinement-cancel
checks. None of those earlier runs is acceptance for the final fixture.

One stable adapter review has no remaining findings. Every production property is
immutable with identical Sendable declarations on Native/WASM/Embedded. The only
mutable production buffer is invocation-local coordinates; no unsafe pointer,
shared mutable state, target-dependent synchronization or callback is introduced.
The retained main graph-refinement evidence remains unchanged; the new verifier
uses its existing generation validator without changing it.

The upper Native face/self authored-coordinate query paths still need descendant
field transport and actual current-snapshot integration. This adapter receipt must
not be generalized to those paths or used as evidence of whole M6 completion.
