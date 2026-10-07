# Native Surface Surface Point Relations

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md). Owns complete isolated original tuples
(u1, v1, u2, v2) on finite closed nonperiodic positive-weight single-span
tensor B-spline products, and isolated components of genuine common Native chart coverage. This contract does not claim full SSI coverage.

## Responsibilities and Boundaries
The exact point publisher also accepts cells of genuine common SSI coverage, bound
to their original canonical source laws. Existing public point handles retain either
the genuine single decomposition or complete common coverage; no synthetic decomposition
or numerical image deduplication represents multi-chart authority.
Admit original source laws and consume the existing four-coordinate decomposition.
Publish complete zero-dimensional coverage through the isolated fast path. Rich
positive-dimensional publication delegates to [Native SSI Relations](../NativeSurfaceSurfaceRelations/DESIGN.md)
under the same ledger; discrete entries retain nonDiscreteIntersection rejection. Ineligible
sources remain with existing dispatch; failures after admission propagate.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | SSI result | Rich result preserves empty receipts | Array adapter exposes only intersections |
| [Intersection Algebra](../IntersectionAlgebra/DESIGN.md) | depends on | original system, guarded isolated decomposition | Complete four-coordinate closed coverage | No sampled absence |
| [Native CS Points](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | depends on | scalar localization | Retained original affine root transport | No new solver |
| [Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | coordinates with | source, span, subdivision, work and bytes | One caller allowance | Exact depth is independent |

The package-internal NativeSurfaceSurfacePointPublisher is the extracted original
localization/refinement algorithm. Both producers pass each exact cell and its canonical
original source laws; no cross-chart scalar or XYZ equality deduplicates tuples.

## Architecture
```text
normal / admitted / box-pair / prepared-session rich entry
 -> native eligibility -> original laws -> complete isolated decomposition
 -> all-cell dimension gate -> exact tuple order -> localization
 -> immutable complete receipt + numerical point handles
```

## Contracts and Invariants
Requested finite closed boxes intersect unchanged native domains exactly,
including singleton and excluded products. Complete empty success retains its
exclusion receipt. Repeated roots yield one tuple; distinct parameter preimages
at the same XYZ remain distinct. Original ordered lifting determines lexicographic
tuple order. The receipt retains both raw original sources, full decomposition,
cell identity, four field coordinates and achieved isolation/localization proofs.
Foreign receipt identities are rejected. Numerical parameters and XYZ lie inside
outward exact-root enclosures; original rational laws bound residual and error
against both surfaces. Point equality, hashing and Codable retain historical
numerical semantics and do not serialize authority.

## Runtime Flows
One local admission forwards the composing caller work and optional byte callbacks
through preparation, decomposition, localization and publication. Source depth,
span ceiling, option subdivision cell ceiling and algebraic depth remain separate.
Existing source validation owns degree legality. maximumSeedCount retains the existing distinct-component ceiling: each isolated
parameter tuple is a component, including distinct preimages at the same XYZ.
maximumRootAttempts retains its numerical refinement-attempt meaning; this producer
creates no Newton attempts. maximumIterations bounds scalar publication. Ordinary work equals checked subdivision cells times iterations;
cumulative storage equals checked scalar work times retained Cell stride. Exact
UInt32 words convert to bytes with checked arithmetic. Cancellation is checked
after final storage admission before publishing points or empty coverage.

## State, Ownership, and Lifecycle
Receipt and field owners are immutable Sendable. Handles retain the same receipt
and original source values after caller source release. Refinement and accounting
are value-local. No shared mutable state or target-specific isolation is added.

## Failure, Concurrency, and Constraints
Source validation, count, work, byte, source depth, algebraic depth, refinement
and cancellation failures propagate. Incomplete coverage never becomes empty
success. Proximity and geometry repair do not establish original equality.
Later exact coordinate queries require their own explicit allowance.

## Verification and Change Impact
The original nonconstant-weight quadratic bowl, weighted bilinear plane, and
close-root products publish complete original tuples at their unchanged precision
under finite caller admission of 80,000,000 work units and 1 GiB cumulative
storage. Ordinary admission verifies identical complete tuples when successful
and accepts only typed resource exhaustion otherwise. The close-root input retains distinct
preimages separated by less than modeling tolerance. Verified pure even-power
real-zero reduction is explicitly enabled for this producer; the original
equations, guards and Jacobian remain authoritative through the algebra contract.
The public protocol witness also verifies source-valid nonclamped single native
spans in both surface orders without changing their raw sources or native domains.

[NativeSurfaceSurfacePointTests](../../../Tests/CADGeometryTests/NativeSurfaceSurfacePointTests.swift)
owns public ordinary/admitted/box/session success, rank-deficient isolated contact,
closed boundary and singleton, same-XYZ preimages, weighted sources, retained
coordinate lifetime, empty receipt and explicit resource/cancellation failures.
The algebra proof tests own reconstruction, original rank preservation, full
expanded-buffer allocation admission and insufficient-storage rejection. These
tests and all native SSI tests pass in the same corrected source snapshot; the
preceding combined verification also covers projection, native CS and its
singular-field and tangency callers. These results cover this component's finite
isolated-point contract and do not complete positive-dimensional or general SSI.
Root dispatch integration must execute the same producer on every eligible route.
