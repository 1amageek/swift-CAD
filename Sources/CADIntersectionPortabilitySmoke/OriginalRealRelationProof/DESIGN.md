# Original Real Relation Proof

## Purpose and Scope

This child of [Intersection Portability Smoke](../DESIGN.md) owns the common direct public runtime witness for requirement 5: real polynomial component decomposition. It has no children. Complete original rational and ordered relations, their selected cells, closure-derived components and exact scalar ownership are the proof target. Geometric source-family preparation and CS/SSI publication remain separate consumers.

## Responsibilities and Boundaries

The driver invokes the public `OriginalPolynomialRelationResolving` existential and inspects `OriginalRealRelation` using public identifiers, dimensions, signs, samples, membership and refinement. Ordered coefficients come from actual public rational x²−2 cell samples. It does not construct private fields, approximate coefficients or geometric substitute inputs. Detailed Native normalized-source producer tests remain the algebra owner's evidence; the common driver composes their public coefficient contract.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Intersection Portability Smoke](../DESIGN.md) | parent | Joined execution and final marker | Owns executable composition | Parent integration follows all checks |
| [Intersection Algebra](../../CADGeometry/IntersectionAlgebra/DESIGN.md) | depends on | Public original relation, resolver, immutable result and scalar APIs | Owns complete decomposition, closure and failure | Samples never substitute for whole cell conditions |
| [Original Point Relation Proof](../OriginalPointRelationProof/DESIGN.md) | coordinates with | Existing complete-module proof recipe | Reuses fixed compiler/cache scheduling | Geometry proofs do not establish requirement 5 |

## Architecture

```text
public original polynomial + postfix predicate + exact domains
  -> unconditional Mutex ledger -> public resolver existential
  -> retained real relation -> component/cell checks -> exact membership/refinement
  -> joined entry/last-callback cancellation -> Q5 final marker
```

## Contracts and Invariants

| Witness group | Required observations |
|---|---|
| Rational geometry rings | Public coordinate counts 1..4 and parameter dimensions 0..4; full regions and singleton selections |
| Real topology | Crossing, cusp, mixed isolated/positive-dimensional components, isolated real zero versus empty complex-positive law, exceptional/nullified fiber and repeated/close distinct roots |
| Domains/predicates | Closed, singleton, strict/open, half-infinite and unbounded domains; unions and explicit denominator-zero exclusions |
| Ordered sources | Both public sqrt2 conjugate samples, exact fixed-coefficient region/point membership, released input lifetime, causal sample refinement and foreign-owner rejection |
| Admission | Independent work, checked UInt32-word-to-byte storage, parameter/coefficient depths and both cell counters; limits fail rather than publish partial/empty success |
| Cancellation | Entry rejection plus cancellation at the last actual normal-return callback for positive/empty decomposition and true/false membership |

The public ring remains 1..4; arbitrary internal admitted coefficient/closure coordinates are the production algebra's contract. No fixture changes that public bound. A true/false result is checked against the original predicate; disconnected open branches cannot be merged through an excluded boundary. Components must include every published selected cell exactly once with their actual maximum parameter dimension. Domain and sign checks use original rational values only.

## State, Ownership, and Lifecycle

Each proof invocation owns one immutable Sendable ledger with a `Mutex<State>` protecting cumulative work, bytes, cell visits, achieved depths and callback ordinals. Every `OriginalRelationUsage` copy forwards to that owner. Count multiplication and addition are checked. Cancellation hooks run after releasing the lock. Released input/producer values remain alive only through actual public immutable results/scalars, and later queries retain their original identity and inherited depths. There are no raw pointers, caches, actors or target-specific shared-state branches.

| Target | Storage | Isolation | Reads/mutations | Release |
|---|---|---|---|---|
| Native | Mutex<State> | same mutex | same snapshot/admission | last strong ledger owner |
| Normal WASM | Mutex<State> | same mutex | same entries | same owner |
| Embedded WASM | Mutex<State> | same mutex | same entries | same owner |

## Runtime Flows

Synchronous groups validate complete results and independent failures. Terminal operations are measured once; a fresh joined task cancels at their measured final callback ordinal, with identical input, path and limits. The task must throw CancellationError and never publish the expected normal value. An additional task is cancelled before its first admission and must spend no callbacks. Successful groups emit distinct markers, followed by the parent final Q5 marker only after all cancellation tasks join.

## Failure, Concurrency, and Constraints

Unexpected success, incorrect original signs/ownership/coverage, invalid dimensions or failure types abort the executable. This proof uses the existing rational-test baseline of 10M work and 10M UInt32 words, and ordered-test baseline of 20M work and 20M UInt32 words with independent depth24 and 100K cell admissions; exhaustion does not select another input, cap or algorithm. Unconditional imports and Sendable callbacks retain the same synchronization semantics on every target. Production missing contracts return to the algebra owner; the driver never repairs the solver or hides unsupported cases.

## Verification and Change Impact

The sole fixed-cache compiler owner stages one reviewed stable common snapshot of complete CADCore/CADGeometry and this driver, then compiles/links/runs Native, matching Swift6.4.0 normal WASM and Embedded WASM. Logs, raw artifacts, commands and all source hashes are retained. Root owns a single whole review and finding-specific confirmations, source commit and main integration. Requirement 5 acceptance requires these results plus the production algebra owner's general closure/ordered/source-bound proof; unrelated CS/SSI/source-family completion is not inferred.

The common groups map to existing Native detailed owners: `OriginalPolynomialRelationTests` (whole public rational selection and domains), `OriginalOrderedPolynomialRelationTests` (actual normalized original coefficient transport and independent source depths), `OriginalOrderedIntersectionClosureTests` (fixed-coefficient closure), and `IntersectionIncidenceTests` (forced general quantified formula, higher admitted internal coordinates, exact incidence and exceptional fibers). The common driver does not recreate those private theorem-selection fixtures.
