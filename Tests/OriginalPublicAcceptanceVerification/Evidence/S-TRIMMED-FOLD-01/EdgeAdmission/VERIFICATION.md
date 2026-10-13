# Native lifted edge model-admission prerequisite

The actual fixed S-TRIMMED-FOLD-01 face uses Native F(u,v)=(2u,v,0) on the left
and(2-2u,v,0) on the right, full square outer loop and the asymmetric hole
U[1/8,3/8],V[1/4,3/4]. Every edge retains the original constant-U/V pcurve,
reverse canonical spatial lift and reversed coedge. The frozen unchanged model
fails invalidEdge because its retraced outer horizontal lift has equal original
endpoint positions but is classified open.

```text
Validated original lift -> existing Geometry homogeneous Native position laws
    -> exact all-incident endpoint equality -> Topology closed position classification
    -> actual exact ValidatedBRepModel admission, preserving source UV and topology
```

BRepEdgeGeometryClassifier now consumes that existing original producer for full
normalized constant-U/V lifts on a nonperiodic Native host without a priority
image. Its exact rational comparisons prove position closure only. It neither
makes the source injective nor removes distinct UV, nor validates an embedding.

| Fixed target | Actual exact face and closure controls | Final runtime |
|---|---|---|
| Native | PASS | 0.843s |
| ASAN | PASS | 1.512s |
| ordinary WASM | PASS | 0.281s |
| Embedded WASM | PASS | 0.689s |

Tests cover both outer sides/interiorV, unequal positive rational weights,
least-positive-binary64 endpoint displacement remaining open, original
source-discontinuity refusal, exact whole-classification work/storageN and
independentN-1, source depth0 refusal, final caller callback Task cancellation
and detached/COW exact model lifetime. Native/ASAN query counts6297 work and16688
bytes; WASI counts4395/9080. Callback counters use the same Mutex<Counts> on every
target; cancellation occurs outside the lock.

Canonical CADTopology sources are compiled with fixed Swift6.4.0 release and
matching SDKs on all four targets, linking the admitted current Geometry/Core
products. Geometry/Core/Kernel and independent lower verification artifacts
are not regenerated. Topology Native27.766s, ASAN32.982s, WASM27.959s and
Embedded94.355s; final Embedded fixture compile231.391s remains within its300s
limit and10GiB memory cap. That fixture correction does not regenerate Topology.
All runtime processes are bounded120s. The longer final Embedded fixture compile
is reported explicitly, not represented as the previous74s diagnostic trial.

source-premises.json binds the current Core/Geometry/Topology Swift sources;
products.json binds actual linked objects, canonical Topology products, fixture
and executable hashes. summary.json references the unchanged inherited product
manifest. accepted records bind exact commands, zero exits and raw log hashes.
Frozen diagnostic trials are not accepted successful evidence. REVIEW.md owns
one comprehensive scoped review; no production finding remains.

This closes only the concrete model-admission prerequisite. Both exact material
predicates, all policy residuals and actual DefaultOffsetResultValidator receipt
consumption remain incomplete. S-TRIMMED-FOLD-01 itself, M4-M8, whole-seven1/7 and
full87 remain open. Independent latest-main delivery is recorded separately.
