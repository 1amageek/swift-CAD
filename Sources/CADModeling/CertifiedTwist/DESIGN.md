# Certified Straight Twist Sweep

## Purpose and Scope

Child of [CADModeling](../DESIGN.md). Builds a profile-normal straight Sweep
with a certified positional approximation to a piecewise-linear angle law.
There are no child components.

## Responsibilities and Boundaries

Owns admission, angle subdivision and tensor control construction. Existing
Sweep owns caps, pcurves, sewing and semantic topology. Source remains CADIR.
No gear source, UI, guide transform, scaling or curved moving frame is added.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | rotational acceptance | request composition | preserve exact profile |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | outward scalar intervals | coefficient enclosure | no libm certificate |
| [CADIR](../../CADIR/DESIGN.md) | depends on | SweepOptions | persisted tolerance and angle knots | omitted allowance refuses twist |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | planning and sewing | same admission in both paths | tests require compilation clearance |

## Architecture

```text
SweepOptions -> certified plan -> Hermite tensor patches -> Sweep face request
                                                        -> sewer -> BRep
```

## Contracts and Invariants

The allowance bounds distance to the ideal sweep of the retained input profile,
not distance to an analytic curve that the input profile itself approximates.
Normalized law positions increase from zero to one; angles start at zero and
end at twistAngle. Interior knots alone may change angular velocity.
Artificial subdivision endpoints share position and physical derivative.
The tensor weights repeat the positive profile weights in all five quartic rows.
Original path endpoint positions are obtained from the retained original chart's
closed position jets, including nonrepresentable exact fractional endpoints.
Rodrigues normalization and section-plane anchoring use those intervals, not
the converted candidate's endpoints. Original section correspondence error is
amplified by the maximum authored scale and included in both reach and final
positional admission. Authored native sections with exact identity contribute
zero construction error; an authored approximation remains its own input law.
One invocation admission survives section/path conversion, original endpoint
queries and all angle-law intervals.
The immutable plan retains that admission through face-request construction;
publication cannot allocate a fresh geometry allowance after tensor preparation.
Retained loop/interval tables, tensor rows, repeated-weight outer arrays and
temporary interval coefficients debit their actual element stride before
allocation. Tables reserve their complete admitted capacity once; every
subdivision visit and control construction debits the same work callback.
Borrowed input knot and weight buffers retain their existing immutable storage;
new axial knot and path-control buffers are charged separately.
Whole-interval Hermite error plus outward-enclosed coefficient error fits the
allowance. Profile and path geometry must be admitted before topology allocation.
Singular rotation, nonfinite arithmetic and resource exhaustion are failures.

The initial domain is one retained whole original monotone linear path span, a closed
profile (including holes) or a curve section (open or closed; an open one makes
only a sheet, its loop's ends left as boundary), the original linear nonnegative
scale law, no guides and
new-body solid or sheet.
Source angles lie in [-16,16] radians: division by 16 puts them in the Taylor
domain [-1,1], and exactly four double-angle steps bound evaluation cost. Twenty
terms and an outward 2^-150 remainder enclose trigonometry before Hermite control
construction. Rodrigues normalization, plane-axis intersection, fractional path
length and tensor coefficients are evaluated with outward intervals. The maximum
L1 control error bounds the rational surface error because weights are positive
and repeated in every axial row. The scaled Hermite remainder uses
R max(1,endScale) |delta|^4 / 128,
conservatively larger than the componentwise vector bound.

Admission caps total patches at 4096 and tensor controls at 262144, including
all profile loops; each source-law interval is dyadically subdivided so fractions
are exact. These are explicit refusal budgets, not accuracy defaults. C1 is the
shared Hermite endpoint/physical-derivative contract; floating control storage
has the separately enclosed coefficient error. No C2 guarantee is made.

## Verification and Change Impact

Tests must reject missing/invalid allowances and unsupported domains; check
source round-trip and parameter dependencies; verify the interval error bound,
artificial-seam derivatives, explicit law reversal, holes, exact BRep validation
and real tessellation. Run only after shared compilation clearance. Source,
planner and evaluator changes must preserve this same admission contract.

The multi-tooth construction fixture verifies actual sewn surface coordinates
against the retained profile and angle law, closure and tessellation. Native
solid classification also verifies the center, a remote exterior point, a cap
boundary, and tooth-interior/gap-exterior points at three axial positions.
The earlier recorded classifier resource-limit failure is not reproduced on
the current kernel; these nine checks now guard that path. They do not prove
arbitrary Boolean operations or validate a manufactured involute gear.

### Original scale and terminal collapse

The source law multiplies the original Rodrigues offset by the authored linear
scale. Cubic rotation candidates are multiplied exactly by that linear law in
Bernstein form, producing quartic tensor rows; the original rotation remainder
is charged after multiplication by the maximum original scale. Translation and
axial scale use exact degree elevation. A zero scale is admitted only as the
terminal endpoint, and all terminal coefficients share one original path-point
enclosure candidate. The unchanged tensor-control ceiling is charged for five
rows. Pole UV uses and absent end-cap publication use the same original singular
boundary contract as other sweep tensors. This does not supply guide or corner
laws, which retain their respective source owners.

Original path linearity is proved by SectionResolution's whole original
homogeneous incidence law under the configured conversion admission. A degree-one
candidate cannot authorize a straight twist from a curved original source.
