# IGES Association Parameters

## Purpose and Scope
Owns bounded separation of standard generic association and property tails from specified IGES parameters. Parent: [CADExchange](../DESIGN.md). No children.

## Responsibilities and Boundaries
Family-specific grammar establishes the specified parameter extent. This component then separates NA/association pointers and NP/property pointers without scanning numeric geometry as references. Unknown families remain opaque. Original records remain parent-owned; graph source owns group inverse membership.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADExchange](../DESIGN.md) | parent | parsed original entities and same resource accountant | Bounded parser composition | Original records survive splitting |
| [Independent Shape Exchange](../IndependentShapeExchange/DESIGN.md) | used by | group source graph | Actual inverse-pointer validation | Non-group metadata requires its own transport or explicit loss |
| [Preservation](../ExchangePreservation/DESIGN.md) | used by | original references and losses | No dangling tail pointer disappears | Unknown grammar remains opaque |

## Architecture
```text
Specified family extent -> exact generic tail grammar -> base parameters + inverse/property pointers
```

## Contracts and Invariants
Known families establish their specified extent from fixed or checked original counts. Counts and arithmetic are checked before indexing or allocation. Generic tails allow either group to be omitted only where no subsequent group exists; supplied counts must exactly consume the original tokens. All nonempty pointers are positive odd directory identities. Arrays are admitted before materialization. Original text stays available for loss reporting. Authority: [NIST IGES 4](https://nvlpubs.nist.gov/nistpubs/Legacy/IR/nbsir88-3813.pdf), section 2.2.4.4.2.

## Failure, Concurrency, and Constraints
Malformed counts, trailing tokens, missing identities, exhausted work/storage and cancellation propagate. Parsing is invocation-local and uses the parent's original accountant and deadline.

## Verification and Change Impact
After all source implementation, verify literal 402 forms and member tails, optional empty tails, repeated/missing/wrong-family pointers, variable spline extents, unsupported metadata losses and caller limits through the actual public IGES reader. Source authoring is not behavioral evidence.
