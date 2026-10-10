# Actual plane-derivative Surface3D lift host

## Scope and actual route

The existing `OriginalPlaneDerivativeSurfaceSnapshotProvider` now implements
`OriginalRetainedLiftHostSnapshotting`. Its protocol requirement accepts the actual
`Surface3D.procedural.originalPlaneDerivative` payload and delegates to the same
source binding issuer. No original surface is reconstructed, no coefficient or
projection formula is added, and no unchecked proof initializer is exposed.

The existing retained-host lift providers consume this source with Native B-spline
or affine/constant pcurves. Existing complete lift graphs and guarded DI preserve
one authored T parameter, auxiliary U/V, all original closed cells, equations,
guards, depth and projection/connector owners. Position coverage does not imply
derivative continuity or whole embedding certification. See the
[source contract](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md#plane-derivative-retained-lift-host).

## Receipt-bound numerical payload and independent assembly

The M6 numerical products contain the original plane-derivative payload used by
the real Surface3D enum. The current source adds exactly three package helper
methods. `Verify.py` checks the cached source hash against its production receipt
and proves that removing those three exact method bodies makes the current file
byte-identical to that cached source. Stored fields, initialization, equality,
existing public queries and ownership are unchanged; no layout substitution is
performed. The actual constructor and numerical evaluator use that original enum
payload in every lane.

The three current helper bodies compile in `DerivativePayloadAccess`, against the
unchanged original private fields, using verification-only access-control disabling.
The current original positional atlas, source snapshot/provider, new host protocol
conformance, lift and DI compile with ordinary access control in the separate
`RetainedHostAdapters` module. No original formula or state is rewritten. This
separation avoids Embedded private-setter warnings caused by applying the helper
flag to the whole source/DI assembly. The flag is absent from production source,
package configuration and the source/DI compilation.

All inherited input/product/log hashes are admitted before reuse and rechecked
after runtime. Swift 6.4.0, matching SDKs, compiler commands and products are bound
by the four final lane receipts. Each compile/link/runtime command has a
120-second timeout; the strict WASI runner propagates the actual exit status.

| Lane | Helper compile | Source/DI compile | Link | Runtime |
|---|---:|---:|---:|---:|
| Native | 0.260 s | 24.768 s | 2.494 s | 1.592 s |
| Changed-source ASAN | 0.192 s | 41.032 s | 5.348 s | 2.192 s |
| Normal WASM | 0.308 s | 21.177 s | 1.505 s | 1.777 s |
| Embedded WASM | 0.262 s | 14.845 s | 39.198 s | 0.948 s |

All four final compile/link logs have no warnings/errors; runtime has no
actor/race/null-call/signature diagnostics. Node's WASI experimental notice is
informational. ASAN covers the freshly compiled helpers, source/DI and fixture;
unchanged numerical dependency objects are not newly instrumented. This is not
a full production ASAN or broad CAD build.

## Behavioral coverage and scoped review

`Shape.swift` reuses the original derivative-source fixture construction and
Hermite position oracle. `Proof.swift` exercises actual weighted/unweighted,
projected/unprojected multi-cell surfaces, via actual Surface3D/lift values and
the generic host protocol requirement. It verifies:

- Native, affine diagonal, reversed constant-U and constant-V pcurves; all eight
  host/span incidents at the knot, original source equality and exact XYZ/UV.
  Weighted XYZ Y is checked with its rational law, separately from authored V.
- Original numerical evaluator accuracy separately from exact graph equality.
- Full, nonbinary strict, singleton, disconnected and complete empty requests,
  wrong-UV exclusion and retained guard consumption through existing DI.
- Exact preparation/query work and byte ceilings and one-unit-short refusal,
  exact source/lift depth and one-less refusal, wrong-host rejection, entry and
  final-storage-callback cancellation, input COW and graph queries after input
  release. The result retains projection, connector and original source owners.
- Unchanged actual boundary-correction and Native-pcurve retained-host behavior
  against the freshly compiled source/DI assembly.

One stable scoped review covers the new conformance, actual constructor/payload,
existing source/lift/DI route, all final runtime behavior and helper/cache premise.
No unresolved finding remains in this unit. The sole production addition delegates
through existing checked contracts; no solver, new budget, fallback, shared state,
unsafe ownership or target-specific conformance is introduced.

| State | Native | Normal WASM | Embedded WASM |
|---|---|---|---|
| Provider configuration | Immutable | Same | Same |
| Original payload and result owners | Immutable Sendable | Same | Same |
| Preparation/query scratch | Invocation-local | Same | Same |
| Admission/cancellation | Exclusive caller inout ledger | Same | Same |
| Release | Last retained immutable owner | Same | Same |

## Rejected attempts and remaining scope

`Evidence/diagnostics.json` binds superseded logs and inputs. Initial Native
fixtures incorrectly assumed weighted Y equals authored V. The pre-split Embedded
assembly passed runtime but emitted private-setter warnings and was not accepted.
Only the four final lane receipts above establish this unit's verification.

Broad CADCore/CADGeometry/Kernel and L2-L6 rebuilding was not performed. General
angular/algebraic derivative supply, other hosts/pcurves, derivative rolling-ball
rails, general identities/material/self consumers and automatic or symbolic
public geometry remain open M4-M8 work. Whole-seven completion remains 1/7
(requirement 5), and full-87 acceptance is unchanged. Independent latest-main
delivery must compare source/product/log premises and run fresh Native/Embedded
interaction before this implementation unit is marked delivered.
