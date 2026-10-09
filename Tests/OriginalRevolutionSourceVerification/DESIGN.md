# Original Revolution Source Verification

## Purpose and Scope
Verification-only package for the actual original rational-generator revolution
source capability. Parent design: [OriginalSourceIssuance](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md).
No production child module is introduced.

## Responsibilities and Boundaries
Run actual CADCore/CADGeometry constructors, providers, retained child law issuance
and point/derivative handoff. This Native package does not generalize its result to
full Geometry WASM or non-rational generators. Independent source algebra and
portable receipts are verified by the existing source verification package.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Source owner](../../Sources/CADGeometry/OriginalSourceIssuance/DESIGN.md) | verifies | revolution snapshot, law, support, correspondence | Actual source handoff | No descriptor-only proof |
| [Revolution](../../Sources/CADGeometry/OriginalRevolution/DESIGN.md) | verifies | original constructor/evaluation | Same retained generator and axis | Keep tolerance and budgets |

## Architecture
```text
actual reversed weighted generator -> actual revolution
              |                           |
       retained original law <- snapshot provider
              |                           |
             exact position / child correspondence
                         <-> numerical public point/derivative
```

## Contracts and Invariants
The proof checks exact coefficient/correspondence values independently from the
numerical evaluator, closed support and period, endpoint collapsed position,
wrong-length rejection and provider depth/tolerance failure. One query-local
ledger admits the original constructors and all source issuance.

## Verification and Change Impact
Build/link/run with fixed Swift6.4.0 release, four compiler jobs and an outer
120-second timeout per command. Record all production source inputs and artifact
hashes. Changes to source law, traversal endpoint imports, normalized axis or
actual evaluator invalidate the relevant evidence.
