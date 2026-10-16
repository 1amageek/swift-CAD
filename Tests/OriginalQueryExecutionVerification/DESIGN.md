# Original Query Execution Verification

## Purpose and Scope

This test owner verifies the canonical execution contract and the first finite
G01 public SSI delivery. Parent: [SwiftCAD](../../DESIGN.md). It has no children.
Individual accepted inputs do not establish all G01 families or all U1–U4.

## Responsibilities and Boundaries

The runners bind actual production sources, toolchain, SDK, original successful
compiler commands, products, fixtures and runtime logs. They compile genuine
production modules or consume their verified immutable products. Private SwiftPM
packages contain the selected real test sources; they do not replace production
implementations. Geometry equality and coverage remain production-owner proofs.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SwiftCAD](../../DESIGN.md) | parent | fixed deployment and package graph | Owns integration and delivery | A local test is not whole-package acceptance |
| [Original Query Execution](../../Sources/CADGeometry/OriginalQueryExecution/DESIGN.md) | depends on | cumulative admission, scopes and retained owners | Supplies actual query execution | Independent resource axes retain their meaning |
| [Exact Scalar](../../Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/DESIGN.md) | depends on | depth and actual decision visits | Supplies low-level arithmetic | Constant depth admission is not a root visit |

## Architecture

```text
source inventory + fixed compiler/SDK + actual dependencies
    -> immutable production module/object receipt
        -> actual test sources or public G01 fixture
            -> bounded compile/link/runtime
                -> source/product/log evidence and scoped result
```

## Contracts and Invariants

Reuse checks the exact successful source snapshot, original compiler invocation
and log, target/SDK/flags, and every retained module/object hash. An explicit
reuse prefix never grants reuse to later modules. Source mismatch within that
prefix fails; selected dependents compile freshly. Failed or timed-out phases
remain diagnostic evidence and cannot be accepted as successful execution.

Native upper-module verification uses actual OpenUSD sources, module/object
products, generated resource accessors and schema bundles. Test resources remain
the real target Fixtures with SwiftPM-generated accessors. Protocol conformance,
successful typechecking and compile/link alone do not imply runtime success.

Native SwiftPM test targets retain normal per-file compilation and the generated
output-file map. A temporary WMO diagnostic pass can expose a full ownership
batch, but cannot establish a runnable test product: SwiftPM still expects
per-file dependency outputs. Real Kernel source-adjacent Fixtures reference the
same hashed resource copy. Both actual SwiftPM bundle layouts are verified,
including every generated copy and resource accessor; resource paths cannot
select unreceipted fixture bytes.

G01 requires ordinary, admitted and prepared results in both operand orders for
the recorded singleton complete-empty and nonempty finite-cut inputs under the
unchanged caller ceilings. The fixture preserves original XYZ/all UV, source
owners, complete cover, independent limits, cancellation and detached readers.

## Runtime Flows

`typecheck.py` produces verified module prefixes. `native_tests.py` selects real
test files and runs Swift Testing against those products. `verify_g01_direct.py`
links the frozen [public fixture](../OriginalPublicAcceptanceVerification/G01Direct/G01DirectAcceptance.swift)
and runs separately bounded logical groups. Portable runners retain distinct
ASAN, ordinary WASM and Embedded compile/link/runtime evidence.

## State, Ownership, and Lifecycle

Each run owns a fresh private output directory and immutable source copies.
Receipts retain original product origins; later shared builds cannot silently
replace them. A reused test executable requires matching production, test,
resource and artifact hashes. Source, product and log drift are checked again
after execution. Results preserve their production evidence owners.

## Failure, Concurrency, and Constraints

Native compiler and runtime phases use the recorded process-tree memory and
wall limits. Runtime groups have a 120-second bound; compilation has a
1,200-second bound. SwiftPM jobs and team compiler slots are bounded separately.
Resource refusal and cancellation are checked by their original typed causes.
An unexpected error cannot satisfy a specific refusal oracle.

## Verification and Change Impact

Changed admission paths require actual success/refusal, N/N−1, independent
depth, cancellation and lifetime controls. Missing mandatory `using:` ports have
outside-target compile-fail controls. Historical evidence remains valid only for
unchanged proof premises. Integration compares the delivered source snapshot
with the accepted source inventory; whole-family and whole-task completion
remain separate gates in the task's sole root `PROGRESS.md`.

### Explicit Native Collections Product Authority

Artifact recovery may select a fresh `--collections-products` receipt rather
than the historical default dependency location. The selected four-entry map
binds exactly two genuine Collections modules and their two objects to a
successful adjacent dependency build receipt. Selection validates the pinned
package revision, actual source inventory, fixed compiler/SDK, successful
compiler log, original product paths and bytes. The production receipt records
both authorities; a focused test must select the same map and product origins.
An absent, mismatched or unsuccessful authority fails explicitly. Historical
receipts and their default paths are never rewritten to describe new products.
Recovery outputs live in a run-owned directory outside disposable `.build`
caches; immutable copied snapshots and logs remain required for product reuse.
