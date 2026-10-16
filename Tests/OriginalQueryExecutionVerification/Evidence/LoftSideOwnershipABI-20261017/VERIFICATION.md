# Loft Side Ownership and WASM ABI Verification

## Scope and source authority

This package records the single `LoftSideSurfaceSource` representation repair and
its paid immutable ownership controls. The production change makes only the
`originalPlaneDerivative` enum case indirect and replaces the old retained-field
reservation with the complete typed tuple reservation. Both reservations remain
before construction/certification, in their original order, on the same
`OriginalQueryExecution`. Source laws, conversion guarantees, phase limits,
original failure causes and the three other enum cases are unchanged.

[owned-source-manifest.json](owned-source-manifest.json) pins the one production
file, owning design, shared checks, Native wrappers and portable entry. Exact
UTF-8 source snapshots are preserved as gzip. The Native compile authority is
`native-full-r6/receipt.json`, SHA256
`d19500908ae949676d9ef7cd9eeff6eec6b800f86046b510aa43b79538dca05c`,
only for its exact current Core67/Geometry2171 plus Loft1 source subset.

The full current Modeling snapshot is **not** labelled Native r6: the separate
`SourceFacePatch/SourceBRepFacePatchBuilder.swift` added one explicit
`import HashTreeCollections` after r6. Its before/current hashes and exact inverse
single-import proof are recorded in `index.json` and
`authority/native-r6-exact-subset.json.gz`. That file is not compiled into the
one-source Loft module and is outside this commit unit.

## Implementation and evidence flow

```text
Real Core/Geometry accepted products
    -> real LoftSideSurfaceSource.swift (module CADModeling, same package name)
    -> shared checks -> actual factory -> actual geometry converter
       -> paid payload + full tuple -> success, N-1 refusal or cancellation
    -> identical Native wrappers / ASAN / normal-WASM / Embedded entry
```

The existing `RationalAlgebraStorage` owner reserves the source payload for the
inner procedural box and the full `(source, procedural, guarantee)` payload for
the new outer indirect box. Repeated surface publication retains the same inner
owner. No private replacement declaration, fake guarantee, solver, new budget,
math change or global ceiling increase supplies this proof.

## Behavioral controls and actual results

| Shared control | Actual behavior checked |
|---|---|
| Retained source and guarantee lifetime | Same source hash, finite guarantee, positive certified box count, copied surface equality and repeated point evaluation after local release; pre-certification storage equals both real typed reservations |
| Each retained capacity | Both first/second reservation N-1 boundaries reject before certifier invocation; preceding accepted storage remains paid |
| Source cases and layouts | Three unchanged cases preserve exact values; actual payload/enum strides are printed |
| Exact cumulative storage | Real converter measures N; N succeeds with identical output/guarantee/work; N-1 fails without side publication |
| Converter work refusal | Actual converter under work0 fails with the original resource classification and no paid work |
| Converter cancellation | First actual paid work triggers caller checkpoint cancellation; typed cause, no side publication, same spent work and valid retained original source are checked |

The original fixture budget remains 268,435,456 UInt32 words (1 GiB), 80,000,000
work/cell ceilings, scalar64, source32, subdivision8 and one span. Real converter
requirements and its 256-box ceiling are unchanged. All 29 original boolean
predicates preserve their expressions/order; the six actual authoring/conversion
helper bodies are unchanged except static dispatch. Shared failures throw rather
than relying on Testing macros. Native keeps the original five wrappers plus the
single cancellation wrapper; the capacity wrapper retains both Boolean inputs.

Native `native-loft-shared-r1` passes the five original methods, including both
capacity arguments. Its added cancellation method threw the correct raw
`ExactScalarFailure.cancelled`, which the old fixture classifier did not yet
recognize, so that **overall receipt remains failed**. The only fixture repair
recognizes that typed case, without mapping arbitrary errors to cancellation.
`native-loft-cancel-finding-r1` executes only that corrected cancellation method
and passes. Both original and corrected source snapshots, commands, receipts and
logs are retained. This is a five-plus-one evidence composition, not a relabelled
six-case successful first run.

| Portable lane | Actual new module / client-link / runtime seconds | Peak process-tree RSS | Result |
|---|---|---:|---|
| ASAN | 0.700247 / 2.322068 / 1.423484 | 759,480,320 bytes | All six groups pass |
| Normal WASM | 0.691450 / 1.619197 / 0.464531 | 895,221,760 bytes | All six groups pass |
| Embedded WASM | 5.979352 / 42.742029 / 0.238007 | 5,088,133,120 bytes | All six groups pass |

ASAN and normal WASM compile the actual one-source Modeling module and object,
then link real lower objects. Embedded uses the accepted serialized-module-only
strategy for Core/Geometry/Modeling with no Swift object substitution. Each lane
uses fixed Swift 6.4.0 release tooling and its recorded SDK/runtime command. The
canonical `native_tests.run` monitor enforces jobs1, 10 GiB process-tree RSS,
120-second runtime and cumulative 1200-second compile/link allowance, deducting
the accepted lower compiler cost. Before/after source/product/tool/SDK/log pins
match; all three receipts report empty drift. No new controller was introduced.

Actual observed layouts, without guessed fixed target sizes:

| Target | Plane source | Procedural field | Guarantee | Full tuple | Side enum |
|---|---:|---:|---:|---:|---:|
| Native / ASAN | 1584 | 4496 | 32 | 6112 | 312 |
| Normal / Embedded WASM | 1208 | 3128 | 32 | 4368 | 176 |

## Separate full public-writer integration evidence

`integration/` preserves an external normal-WASM public drawing client receipt,
its runtime log and raw ABI diagnostics using the exact same Loft enum source
`ae3e63a76d5c165284dee311fd5f6d4f82dac8b98130ced502de75f7f9cdedcb`.
The original raw module had one type with 1091 parameters, used by the outlined
copy and consume of `LoftSideSurfaceSource`; Node rejected it before execution.
After the representation repair those two functions have 43 parameters, the
maximum parameter count across the final module is 782, and no invalid types
remain. The external six public drawing groups load and execute successfully.
That integration snapshot also records its separate source changes. This proves
the observed ABI/load boundary and selected writer interaction, **not** complete
writer, Exchange, Loft feature, Modeling, Kernel or whole U1 capability coverage.

## Packaging and reproducibility limits

[index.json](index.json) lists every compressed artifact, its exact compressed
and decompressed SHA256, origin and evidence scope. Gzip uses deterministic
mtime=0. Receipts retain full commands/source inventories/product identities;
source snapshots and the actual private driver are text only. There are no
module, object or executable copies in this package. Lower binaries remain
external immutable artifacts and must match the receipt identities to reproduce
the commands. No compiler/runtime, source/design/test/PROGRESS edit, cleanup or
additional comprehensive review was performed while packaging this evidence.

The Root [finding confirmation](finding-review.json) closes only the concrete ABI
and paid-ownership repair, with no remaining finding in that scope.
