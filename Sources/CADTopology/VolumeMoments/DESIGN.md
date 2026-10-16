# Volume Moments

## Purpose and Scope
Child of [CADTopology](../DESIGN.md). Owns certified volumetric first and second moments. [Geometric Measurement](../../CADKernel/GeometricMeasurement/DESIGN.md) consumes these intervals for density, placement and inertia.

## Responsibilities and Boundaries
Exact oriented boundary geometry owns integration. The Kernel consumer owns density and length-unit conversion after integration. Rendering meshes cannot authorize a mass measurement.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../DESIGN.md) | parent | oriented material shells and pcurve trim | Includes cavities and disconnected components | Face and shell signs must both be applied |
| [Geometry](../../CADGeometry/DESIGN.md) | depends on | original differential enclosure | Bounds oriented flux throughout a cell | Samples are upper witnesses only |

## Architecture
```text
Oriented trimmed exact boundary -> divergence flux for monomials
    -> interval integral -> volume/first/second moments
    -> density/unit/placement composition -> inertia eigensystem
```

## Contracts and Invariants
Every material shell contributes signed flux. A request may lower the original 262144-work/32-depth ceilings; it cannot widen them. A successful result publishes actual consumed work. Mass composition carries one residual request allowance through distinct body integrations and reuses an immutable original moment receipt for repeated occurrences. Fixed-size placement algebra is charged once per occurrence. All ten original integral error intervals are retained for consumer propagation. General directed trims use signed boundary-fan pullbacks, retaining original chart authority and certified loop traversal. Hole winding is normalized by loop role before face/shell signs. Geometry-issued original native rectangles and fan domains retain their one-sided source authority. Smooth cells use original flux Hessians and closed midpoint enclosures for interval Taylor integration; mixed derivatives retain a centered remainder. Lower-order native cells keep full value interval integration. Absolute accuracy is interpreted separately in each original model-unit moment dimension (length powers 3, 4 and 5). Relative accuracy uses the minimum absolute value allowed by the complete result enclosure, so every value in that enclosure meets the request; an enclosure containing zero falls back to the absolute bound. Requested accuracy that cannot be enclosed under the shared fixed allowance fails. Consumer composition propagates the resulting intervals and reports its units and source accuracy; it does not claim the unscaled integral request as an SI output-width promise.

Adaptive cell evaluation passes the same caller execution into complete
synchronous pcurve-encloser and predicate queries. Query-local producers
retain immutable source evidence, while returned cells retain their prepared
domain and integral bounds without retaining mutable execution.

Bounded immutable BRep validation uses the same incoming execution. Structural
validation visits are depth-zero work; original source recursion and
subdivision ceilings remain explicit constructor arguments. A structural visit
does not enlarge either independent depth ceiling.

## Verification and Change Impact
Independent box, sphere, cavity and transformed composite fixtures must verify moments, error enclosures, density scaling and principal axes after implementation completion.

One caller-owned `OriginalQueryExecution` uses the same cumulative budget and
Mutex isolation on all targets. Original support preparation, trim enclosures,
face parameter covers, loop winding and flux visits share this owner. Adaptive
trim refinement retains the request's original subdivision ceiling. Signed
loop orientation integrates the original flux with its closed midpoint and
second derivative when available; native joins retain the complete value range
rather than borrowing a smooth certificate.

Volume face extents and original closed source preparation retain the requested subdivision depth and shared execution. Each source position or differential request receives the remaining cell depth; a lower default cannot replace the invocation depth. Native fan/rectangle partition preparation admits each visited cut, comparison, coverage and retained owner through that execution. Fixed source partition scans report depth zero; adaptive lower visits retain their actual depth. Issued original native owners therefore begin integral cells at depth zero; the number of authored spans is not a synthetic subdivision tree or an algebra/source nesting depth. Only actual adaptive splitting increases that cell depth. The original maxCount and radial partition authority remain unchanged.

The validated-model requirement consumes `ValidatedBRepModel.model` and derives its tolerance directly. Exact or volumetric receipts establish original source validity without an independently supplied model comparison. Modeling-only receipts are refused. Legacy manual-input construction still requires complete original validation; its bounded traversal is a distinct required source port. Kernel mass composition uses the retained EvaluatedDocument exact receipt when available, preserving injected provider authority through the protocol requirement.

The raw-model moment entry validates the original request before admission, then creates one moment visit owner for both bounded exact BRep validation and integration. Validated-receipt callers start at integration without revalidating the same immutable model. Original validation keeps the caller subdivision/source caps; incomplete lower validation/chart and temporary-byte producers remain explicit dependencies and do not receive a fresh integral allowance.

All ten integral-width comparisons use outward endpoint subtraction. Relative
allowances use the downward enclosed product of caller relative accuracy and the
smallest absolute value proved by that integral interval. Rounded inward width
subtraction cannot authorize result publication. Adaptive priority uses the same
outward widths; nonfinite accumulated fields fail before publication.

Exact rectangular trim detection uses the same original invocation work and
caller subdivision/source ceilings as the face bounds and integral. Equivalent
affine, polyline and clamped native sides are recognized by their complete
original axis law. Geometry integrand/chart preparation must additionally
retain those ceilings through its source validation and prepared differential
storage; legacy preparation is not complete original work authority.

Original moment flux preparation receives the same composing subdivision cap, source ceiling 16 and independent algebra ceiling 32 with the incoming execution. Native coefficient and direct prepared-support queries retain those source policies. Specialized rolling/offset/ruled preparation and generic nonlinear chart admission must preserve the same contract before complete moment-domain closure is claimed.

Moment trim-loop unwrapping explicitly forwards that same selected algebra
ceiling32, alongside source ceiling16 and the request's subdivision ceiling.
The incoming execution retains its independent value/coefficient ceilings;
the local selection cannot widen either ambient axis. A missing local algebra
selection is not equivalent to the selected finite policy, even when a
particular polyline length simplifies to a rational value. No normalization
guard, root branch or complete chart-lift coverage may be bypassed.

The retained exact-receipt entry intentionally reuses completed immutable model
validation. Its preparation is a separate, explicitly observed operation and
is not charged again as moment integration. The raw-model entry keeps its
original shared validation/integration allowance. A receipt-based moment
success therefore does not establish success of a raw Mass caller that exhausts
the unchanged work ceiling before reaching moment preparation.

The [moment-loop admission tests](../../../Tests/CADTopologyTests/VolumeMomentLoopAdmissionTests.swift)
and [portable client](../../../Tests/OriginalQueryExecutionVerification/VolumeMomentLoopAdmissionPortable.swift)
own the actual six-face/24-polyline cube counterexample, complete ten original
moment intervals, independent limits, cancellation and retained receipt lifetime.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.

### Canonical Geometry API rebinding

Existing numerical consumers borrow the common
[execution](../../CADGeometry/OriginalQueryExecution/DESIGN.md) through actual
source preparation and Geometry queries. Ordinary roots delegate once into the
same body. Independent local limits, formulas, result meaning and all supported
branches remain unchanged; resource and cancellation failures stay explicit.
This delivery binding does not add an independent algorithm or feature fix.

### Direct protocol witnesses

`BRepVolumeMomentMeasuring` declares non-generic direct requirements for both
raw `BRepModel` and immutable `ValidatedBRepModel` inputs. Kernel mass composition
invokes these requirements on its injected existential provider with the existing
`inout OriginalQueryExecution`; extension-only dispatch cannot supply that witness.
`DefaultBRepVolumeMomentMeasurer` already implements both direct bodies. Its ordinary
entries create one root and delegate, while direct entries retain their immutable
request contribution on the same budget for validation and integration.

```text
Kernel execution -> BRepVolumeMomentMeasuring direct witness
                 -> existing validated/raw concrete moment body -> same budget
```

This protocol binding leaves the existing ten integrals, local request limits,
source/depth/algebra policies, receipt authority, and typed failures unchanged.
The direct requirements have no ordinary-method fallback and no default success
implementation. Every injected conformer must provide its actual direct witness.
The next production gate must compile the protocol and the Kernel existential
calls together. Earlier receipts do not cover this added public witness contract.
