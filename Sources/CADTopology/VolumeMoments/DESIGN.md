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

Adaptive cell evaluation borrows its caller work callback for the complete
synchronous pcurve-encloser and predicate queries. These query-local producers
are destroyed before the cell value is returned; the returned cell retains
only its previously prepared domain and integral bounds, not the borrowed
callback.

The bounded immutable BRep receipt invokes a work-unit callback without a
subdivision-depth argument. Moment preparation charges that validation work at
depth zero in the existing invocation ledger. Original source recursion and
subdivision ceilings remain explicit constructor arguments; depth zero here
does not enlarge either ceiling.

## Verification and Change Impact
Independent box, sphere, cavity and transformed composite fixtures must verify moments, error enclosures, density scaling and principal axes after implementation completion.

One invocation-owned `VolumeMomentProofBudget` uses the same Mutex storage and admission on all targets. Original support preparation, trim enclosures, face parameter covers, loop winding and flux visits share this owner. Adaptive trim refinement retains the request's original subdivision ceiling. Signed loop orientation integrates the original flux with its closed midpoint and second derivative when available; native joins retain the complete value range rather than borrowing a smooth certificate.

Volume face extents and original closed source preparation retain the requested subdivision depth and shared work callback. Each source position or differential request receives the remaining cell depth; a lower default cannot replace the invocation depth. Native fan/rectangle partition preparation consumes the same original depth callback for each visited cut, comparison, coverage and retained owner. Fixed source partition scans report depth zero; adaptive lower visits retain their actual depth. Issued original native owners therefore begin integral cells at depth zero; the number of authored spans is not a synthetic subdivision tree or an algebra/source nesting depth. Only actual adaptive splitting increases that cell depth. The original maxCount and radial partition authority remain unchanged.

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

Original moment flux preparation receives the same composing subdivision cap, source ceiling 16 and independent algebra ceiling 32 with the invocation work callback. Native coefficient and direct prepared-support queries retain those source policies. Specialized rolling/offset/ruled preparation and generic nonlinear chart admission must preserve the same contract before complete moment-domain closure is claimed.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.
