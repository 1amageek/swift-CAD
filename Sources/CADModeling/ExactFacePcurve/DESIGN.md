# Exact Face Pcurve

## Purpose and Scope
Own construction and whole-span admission of native surface parameter curves for original BRep edges. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Geometry owns original spatial and native parameter laws, jets, bounds, and correspondence certificates. This consumer constructs pcurve candidates and publishes only after whole original curve/surface correspondence validation. Fitted spatial geometry and sampled projection cannot become source authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | sewing and feature construction | Supplies native coedge charts | Source identity remains original |
| [Parameter Image](../../CADGeometry/ParameterImage/DESIGN.md) | depends on | original affine spatial and scalar chart images | Keeps foreign units and placements | Rounded chart candidates require whole validation |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | original correspondence validation | Authorizes publication against original laws | Unresolved bounds propagate failure |

## Architecture
```text
original edge + oriented native trim + original surface
    -> structural image pullback / original chart candidate
        -> whole original curve/surface correspondence certificate -> pcurve
```

## Contracts and Invariants

Harmonic and exact analytic projection predicates do not unwrap original corrected, drafted, polyline or guide-chain sources into a circular native chart. They decline applicability until the corresponding source law is available.

A structurally identical spatial transform or exact affine operation word on an edge and surface permits source chart construction under their retained original laws. Identical operation words retain the original source pcurve and unchanged UV through OriginalAffineWordSurfaceParameterCurve; they never reconstruct a representative matrix. All signed gains, rational gain coefficients and axis exchanges retain the source lift through OriginalImageSurfaceParameterCurve; its original spatial shortcut supplies pole/apex authority instead of inverse-UV roundtrips. A foreign curve parameter image maps oriented endpoints as candidate arithmetic, retains the original spatial curve in topology, and validates the entire resulting correspondence against that original parameter image before publication. Different transforms and nonlinear inverse correspondences require their original Geometry producer; sampled inversion is insufficient.

## Failure, Concurrency, and Constraints

Endpoint connector chart proposals consume the corrected original curve through whole correspondence validation. Their construction spline has no authority to grant harmonic or circular projection shortcuts.

Scalar chart pullback delegates endpoint mapping to the original parameter-image
producer for binary gains, original ratios, products and directed differences
with retained periodic translations. Its original exact-coefficient bounds and
represented boundary identities remain lower authority. The numerical endpoints
only construct a candidate and never replace whole correspondence validation.
Missing geometry, invalid trims, unsupported original inverse laws, unresolved correspondence and inherited subdivision budgets fail explicitly. State is invocation-local; values and Sendable contracts are common across all targets. Native codecs belong to Geometry adapters.

## Verification and Change Impact
Deferred behavior includes positive/negative scalar gains, rational foreign units, spatial reflections, image nesting, circles converted to rational splines, failed nonlinear inversion and whole correspondence disagreement. Recheck original jet and pcurve consumers when Geometry chart laws change. No behavioral evidence is claimed by this source design.

Original construction chart curves retain their normalized original parameter law through whole correspondence. The construction control net does not supply exact native span, harmonic or projected-boundary identity; optional normalization fast paths decline and retain the original source for the whole-curve producer.

Physical-angle transport retains its original conic phase expression. It cannot inherit the scalar native-angle harmonic projection shortcut from its primitive source. Original lifted/image chart witnesses remain eligible; other inverse phase charts require their retained Geometry producer and whole original correspondence, rather than sampled coefficients.

The caller-admitted direct planar native-spline entry retains the complete raw 3D spline as spatial authority. It generates a projected 2D control proposal in the authored plane chart without Boehm trimming or reversed knot materialization. The original 2D continuation carrier retains that full proposal with the requested oriented native endpoints; its bounded constructor and complete spatial/support correspondence validator consume the same live admission. Rounded projection coefficients cannot authorize correspondence by themselves. Original native knots and weights are shared immutable COW values, while the projected control buffer is admitted before allocation. General image/inverse families need their actual bounded producer and cannot delegate to the legacy projection path when admission is selected.
