# Original Domain Consumer Verification

## Purpose and Scope
Parent: [system](../../DESIGN.md). Verification-only composition of production
Native source providers and CS/SSI parameter consumers with fresh L0-L5/DI.

## Responsibilities and Boundaries
Build only this consumer and its exact dependencies. Reuse validated, unchanged
CADCore and Native DTO/intersector modules after checking their recorded premises.
No whole CADGeometry rebuild, fake shape, second solver or guessed cache is used.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Consumer](../../Sources/CADGeometry/NativeExactRelations/DESIGN.md) | verifies | public parameter relation | domain receipt composition | XYZ legacy routes unchanged |
| [DI](../../Sources/CADGeometry/OriginalDomainIdentity/DESIGN.md) | depends on | source-bound cover | prepared proof consumption | no success generalization |

## Architecture
```mermaid
flowchart LR
 C[Checked cached Native DTOs] --> A[Actual source providers]
 A --> D[Fresh SourceIssuer and DI]
 D --> N[Actual Native consumer source files]
 L[Fresh L0-L5] --> N
 N --> P[Existing public behavior fixtures and retained cover assertions]
```

## Contracts and Invariants
The compiler builds linked production sources directly. Cached source premises,
module objects and runtime artifact hashes are recorded. Every public solve uses
the same original admission, result topology and independent original ceilings.

## Verification and Change Impact
Execute original weighted/contact/multiple-UV/endpoints/empty/overlap/folded-SSI
fixtures plus limits, cancellation and original domain owner assertions.
Record current compiled inputs independently from prior foundation evidence.
This subset composition does not establish fresh whole-module or XYZ integration.
