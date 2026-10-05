# Original Silhouette Provenance

## Purpose and Scope

Parent: [SurfaceSilhouette](../DESIGN.md). This child owns a common-target,
non-generic visitor for the complete retained original silhouette and exact trim
traversal, isolated points and complete envelope incidence. It has no children. Native format envelopes belong to CADExchange.

## Responsibilities and Boundaries

The visitor emits original source values, selected zero laws, branch maps,
resolution steps, station incidence and exact endpoint expressions. It never
serializes interval derivative caches as source or rebuilds a solver. A sink owns
its staged output and the original Surface3D codec; it publishes only after the
entire visit succeeds. Sink failures propagate without producing a success receipt.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SurfaceSilhouette](../DESIGN.md) | parent | Original curves and one live SurfaceSilhouetteUsage | Supplies retained source | Same usage and admission identity are required |
| [RationalBivariateAlgebra](../../RationalBivariateAlgebra/DESIGN.md) | depends on | Immutable exact coefficients, roots, field owners and maps | Supplies original algebraic source | No interval midpoint or reconstruction |

## Architecture

```text
retained trimmed curve -> typed original provenance visitor -> staged format sink
 exact field owners   -> encounter-order definitions / references
 same live usage      -> source visits + temporary sorting + sink output admission
```

## Contracts and Invariants

The stream starts with schema `original-surface-silhouette-v1`. Records have typed
names, named fields and explicit nulls; arrays preserve order and have exact counts.
Binary64 values retain their UInt64 bit patterns. Rational values retain reduced
sign and little-endian canonical numerator/denominator UInt32 limbs. Sparse
polynomials use sorted original powers. Field owner IDs are encounter-order stream
references, never randomized hashes or addresses; each definition retains its
original root and parent coefficient law. Repeated references retain actual sharing.

No Codable, reflection, downcast or target-conditional ownership is used. Every
sink operation is a non-generic protocol requirement and receives the same inout
usage. The sink must charge actual output bytes before allocation through that
usage. The visitor charges scalar source/event visits and typed temporary buffers;
serialization neither consumes new root cells nor resets source/refinement depths.
Original stored root depths and endpoint exclusions are retained unchanged. Source
surface encoding must honor the supplied independent source, algebra and UV caps.

## State, Ownership, and Lifecycle

The invocation-exclusive emitter retains field owner references while visiting;
its reference table is discarded after success or failure. The sink owns staged
output and its synchronization. No callback executes inside the accounting Mutex.

## Failure, Concurrency, and Constraints

Budget, cancellation and sink failures propagate. A sink must discard incomplete
streams and never advertise a partial branch descriptor as a complete silhouette.
All targets use identical Sendable event/sink contracts. The original geometry
source codec may have a Native capability boundary without changing the visitor.

## Verification and Change Impact

Deferred behavioral verification must distinguish branch ordinals, singular maps,
unrelated field roots, endpoint exclusions and close roots, and exercise staged
sink failure and shared-accountant exhaustion. Changes affect CADExchange drawing
provenance and Runtime page publication. Source-only implementation is not completion.

Point provenance retains the original root law, not a sampled spatial midpoint.
A singular station retains and visits its actual issuing original curve;
its exact rational U/V source and characteristic multiplicity remain explicit.
Atlas station provenance retains its original algebraic contact and complete
incident-curve/endpoint-side arrays. Constant-image publication retains the original
curve descriptor together with the upper whole-D1-zero and trim receipt.

`Station.writeOriginalProvenance(admittedContact:to:usage:)` visits the actual upper retained station/refinement pair in one emitter and one reference namespace. Runtime owns that association; the visitor preserves both full root laws and does not infer identity from coinciding bounds or deduplicate independent owners.
