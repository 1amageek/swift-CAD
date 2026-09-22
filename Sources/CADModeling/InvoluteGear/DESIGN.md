# Involute Gear Section

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. Builds an external
involute gear section with explicitly specified circular root fillets.

## Responsibilities and Boundaries

`InvoluteGearFeatureEvaluator` consumes the
[native source](../../CADIR/InvoluteGear/DESIGN.md) and delegates a request-local
Profile and axial path to the existing Sweep evaluator. The original feature
identity owns all output topology; temporary inputs never enter the document
graph. Source expressions and parameter dependencies remain in CADIR. No
second evaluator registry, publication path or cache is introduced.
The delegated Sweep's `ValidatedFeatureEvaluating` result is retained unchanged
when available: its feature identity and tolerance are the original request's.
An injected evaluator exposing only `FeatureEvaluating` must have its returned
geometry validated before the gear evaluator returns. All failures are wrapped
with the original gear feature ID; no failed evaluation publishes a result.

Owns resolved section geometry and feasibility. Returns the existing CADIR
Profile in XY; callers own source expressions, units, placement, persistence
and feature identity. This is a circular-filleted design, not a claim to
reproduce a hob-generated trochoid or certify manufacturability.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | Profile construction | Existing downstream solid operations | No duplicate evaluator |
| [Involute geometry](../../CADGeometry/Involute/DESIGN.md) | depends on | bounded cubic flanks | Positional allowance on tooth flanks | Rotated-control error must also fit |
| [CertifiedTwist](../CertifiedTwist/DESIGN.md) | used by | Profile input | Double-helical solid construction | Separate sweep allowance |

## Architecture

```text
resolved radii + pitch tooth angle + fillet radius + budget
    -> contact feasibility -> certified involute -> mirrored/rotated teeth
    -> analytic tip/root/fillet arcs + B-spline flanks -> closed Profile
```

## Contracts and Invariants

All lengths are meters and angles radians. Pitch tooth angle is the full tooth
thickness angle on the reference circle. Base <= pitch < tip and root < pitch.
Let rb be base radius, rf root radius, f fillet radius. The left flank root
fillet center is C=P(t)-f*N(t), where N=(-sin(t),cos(t)). Tangency to the
root circle requires |C|=rf+f, giving
t=(sqrt((rf+f)^2-rb^2)-f)/rb. Positive t below pitch contact is required;
negative or imaginary contact is refused, not replaced by a radial line.
Root circles and fillets are analytic; involute flanks retain their explicit
positional approximation allowance. Tip and root angular gaps must be positive.
The output boundary is CCW, with clockwise concave root fillets.

Tooth placement encloses mathematical pi, division by tooth count, the
pitch/base radius ratio, square root and inverse tangent before constructing
rotation coefficients. Coefficients are immutable request-local values reused
by all points on one tooth side. Translation by the native source origin is
included in the interval placement, so large origins cannot silently consume
the positional allowance. Certification of contact/end-roll selection
uses interval square roots and division. The selected stored roll endpoints
are compared to their enclosures; rb*max(roll)*max(endpoint error) bounds the
position shift over the entire linearly corresponding parameter interval,
because the involute speed is rb*roll. That bound is added to flank placement
error. Composed analytic arc admission is implemented below and checked against
independently computed high-precision arc references and infeasible allowances.

The root-center angle is t-atan(t+f/rb), obtained from
C=Rot(t)*(rb,-rb*t-f). Consequently each concave fillet sweep is
atan(t+f/rb)-pi/2. Both sides share this interval; root and tip sweeps
come from their interval half angles. Radius times sweep rounding bounds the
corresponding angular position error. Center coordinates are enclosed from the
contact trigonometry, and root points from C*rf/(rf+f). Each transformed point
is admitted within e=maximumError/8. The difference of start and center has
error at most 2e. Radial normalization gives arc error at most
e+4*r*e/(r-2e)+r*angleError when r>2e. This full bound must fit maximumError;
independent arc-reference and refusal tests exercise this composed path.

## State, Ownership, and Lifecycle

Request-local immutable inputs; returned Profile owns its geometry. Segment
budget applies to the complete repeated boundary, checked before expansion.

## Failure, Concurrency, and Constraints

Nonfinite/invalid radii, angles, contact, overlapping teeth, insufficient
segment budget and uncertifiable flanks throw typed errors. No partial Profile
or display-mesh substitute is returned.

## Verification and Change Impact

CADKernelTests/InvoluteGearProfileTests checks closed endpoints, radial extent,
root tangency, invalid geometry and actual sewn double-helical B-rep and mesh.
RupaCoreTests/InvoluteGearEditingTests verifies native source creation,
parameter-driven regeneration, replacement, Undo/Redo and atomic geometric
refusal. These checks do not certify manufacturing suitability or interactive
latency. Mounted UI and native package workflows remain application-owned.
