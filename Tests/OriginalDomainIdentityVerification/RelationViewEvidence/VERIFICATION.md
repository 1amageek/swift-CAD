# Checked DI relation and affine-coordinate views

Scope: DIA.4.I.M6.D only. The new refining protocols expose checked immutable
coordinate words and scoped identity relations to M6 consumers. Existing proof
constructors, decisions and solver algorithms are unchanged. No public view
initializer exists; the view retains the original map/receipt and COW buffers.

Native and ASAN: 28 behavioral tests each. Normal and Embedded WASM DomainProof
compile, link and run using Swift6.4.0 release and matching SDKs, Node24.19.0 WASI
Preview1. The independent fixture compiles exact whole affine constraints into L1
polynomials and agrees with existing identity decisions. Reversed/permuted axes,
closed/open selected scope, constant-source complete products, source release and
COW mutation are verified. No same-XYZ inference or sample inverse is used.

Transport-view admission costs match existing admitted(map) exactly. Retained
coefficient acquisition requires zero generated storage; a zero-storage caller
success is verified. Exhausted work, transport depth, source depth, proof count and
entry/terminal cancellation reject explicitly. All new operations use the original
exclusive caller admission and final checkpoint. The existing coefficient proof
admission is reused; no extra mutable ledger or cache is introduced.

Scoped review: the new protocols refine existing protocols without adding
requirements to existing conformers; only owner-issued immutable views certify
relations. completeProduct applies only to its retained scopes. Arrays share COW
backing and modifying an exported copy leaves original evidence unchanged. The
logical-state matrix is identical on Native, WASM and Embedded: stored state is let
transport/receipt with immutable owners, readers are computed properties, mutation
entry is absent, release is ARC/Swift value lifetime. No conditional synchronization,
unsafe memory, shared mutable storage or Sendable weakening is added. The existing
scoped proof and source-depth replay is the only admission authority.

receipt.json binds 361 recorded compiler/fixture/package/runner inputs, 36 products
and six logs. The compiler filelists include stable cached target inputs; this is
not a claim that every cached file was recompiled. Each command has a120-second
build/test or60-second runtime timeout. The final stable source is the same across
the six successful commands. This is independent DI validation, not production
Kernel boundary/self completion or all-family M4-M6 acceptance.
