# Scoped implementation review

One comprehensive review follows the actual public constructors, ordering calls,
canonical sweeps, result retention and L2 error/depth facade. The affected Embedded
module-specialization finding is closed by the lossless wrapper and its four-lane
regression. No source/shape or solver capability is inferred from this acceptance.

| Invariant | Implementation/evidence |
|---|---|
| One interval meaning | ExactParameterInterval.checked; root facade delegates all three prior sites |
| Endpoint holes survive | Canonical append/overlap/difference + independent endpoint-sector oracle |
| Complete empty set | Completed exact construction/sweeps; unresolved ordering propagates |
| Foreign axis rejected | Immutable context identity before set/query algebra |
| Original endpoint ownership | Immutable scalar values + retained contexts + released-input rational fixture |
| Cumulative exclusive admission | Same generic inout admission; checked bytes before reserveCapacity; terminal checkpoint |
| Depth cannot decrease | retainingDepth joins; set/product retains axis depths; L2 retains discovered admission depth |
| Upper boundary compatibility | Local L2 bound enum and read-only facade members; no upper source import or algorithm change |

Production source was searched for Embedded/conditional Synchronization, Mutex,
unchecked Sendable, nonisolated unsafe and every mutable stored property. DI0 has no
shared mutable state or target-dependent ownership/synchronization declaration.
Local scratch arrays are invocation-owned; context and result storage are immutable.
The existing exclusive L0 ledger is reused, never copied into a second budget.

| Logical state | Native | Normal WASM | Embedded WASM |
|---|---|---|---|
| Axis authority | immutable Sendable context | same | same |
| Set/interval/result | immutable COW backing/scalar owner | same | same |
| Work/storage/depth/cancel | caller-exclusive ~Copyable L0 admission | same | same |
| Read entry | admitted public operations, owner checks | same | same |
| Mutation | invocation-local buffers/admission only | same | same |
| Release | retained ARC/COW/scalar owner | same | same |

All four compiled graphs use identical production declarations and protocol
requirements. The only DI0 source condition imports L0 for isolation; it does not
change storage, conformance, failure or lock semantics. No manual pointer allocation,
new shared cache, lock or unsafe conformance is introduced. The buffer-address test
keeps standard-library borrows scoped and returns only a Boolean.
