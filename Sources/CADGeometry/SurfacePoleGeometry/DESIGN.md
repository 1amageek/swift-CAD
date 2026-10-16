# Surface Pole Geometry

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns original one-sided
normal limits on coefficient-proved collapsed clamped native B-spline boundaries.

## Responsibilities and Boundaries

Geometry checks exact original row/column collapse and evaluates its original
closed derivative law. Topology owns legal singular uses and winding orientation;
mesh owns publication. No displacement, epsilon sample or control snapping is used.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original closed native surface jets | Supplies original endpoint derivatives. | Every incident owning side is retained. |
| [CADTopology](../../CADTopology/DESIGN.md) | used by | singular mesh vertices | Consumes a proven limiting unit direction. | Mesh orientation remains a separate owner. |

## Architecture

```text
original clamped coefficients → exact collapsed row/column identity
    → original closed endpoint jets → first normal Taylor coefficient
    → strict nonzero interval + bounded normalized angular spread → receipt
```

## Contracts and Invariants

For a constant-U collapsed boundary, Sv is identically zero on that boundary and
N=Su×Sv has first inward coefficient ±Su×Suv. For constant-V collapse it is
±Suv×Sv. The upper native boundary has negative inward direction. Positive
original weights and identical Cartesian boundary controls prove collapse for
the entire original boundary. Every original owning native side is enclosed;
no midpoint extraction supplies derivative authority. An interval normal vector
must exclude zero. Normalization uses its outward length bounds and the angular
spread of the complete normalized interval must meet the original angle tolerance.
The returned unit direction is only a representative inside that certified cone.

## Failure, Concurrency, and Constraints

The caller owns all preparation and evaluation work. Nonclamped, noncollapsed,
foreign parameter, uncertain derivative or work exhaustion fail explicitly.
Higher-order normal coefficients require exact vanishing authority for every
preceding coefficient and are not inferred from small floating point values.

## Verification and Change Impact

After the source phase, exercise exact rational revolution poles, reversed upper
boundaries, C0 owning sides, noncollapsed rows, first-coefficient degeneracy,
strict angular rejection and cancellation through the actual mesh consumer.

### Closed first-factor normal panels

On an exact clamped collapsed row/column, the original normal vanishes on the
whole endpoint. Its inward first-factor field equals the integral of N_u or N_v
along the inward segment. Original closed third jets enclose that integral and
its derivatives: the normal-direction derivative has a factor one-half; the
tangential derivative is the integral of N_uv. A strictly positive field norm
then certifies unit-normal derivative bounds on the entire original owning panel.
No epsilon station or point-only normal supplies a whole-facet bound.

Native tessellation reuses its existing prepared source and owning span for this
first-factor branch. Failed factor nonzero proofs subdivide under the same
invocation cell/depth usage. General native rectangles first use their complete
original span cover and aggregate those one-sided differential bounds.

### Original Affine Pole Transport

`OriginalImagePoleNormalTransport` binds each source normal panel to its exact
image source and native parameter cover. The original cofactor matrix transports
the oriented normal field, with signed UV gain product and axis-swap parity.
Its whole normal derivative bound uses the cofactor operator upper bound and
original affine inverse upper bound, each enclosed from original columns.
Foreign tangents and second derivatives scale by original gain interval powers.
Nested images keep distinct source receipts; rounded composed matrices do not
replace source authority. Singular or unbounded affine inverses fail explicitly.

Generic tessellation dispatch recurses through each original image source using
the same remaining cell ledger. Source native owning panels establish regular
or factored pole normal bounds before image differential transport; each image
layer debits a visit and never resets the source cell budget.

Point normal transport retains the original closed normal coefficient receipt
and inverse original chart interval. Foreign UV fields remain enclosing chart
values when a true source station has no representable foreign value; the
transported model normal is proven from the original field, not a rounded UV
round trip. Each nested image preserves its source identity and signed cofactor.

### Analytic Closed Pole Panels

Original spherical radial law establishes its unit normal independently of the
vanishing angular tangent. Original cone normals divide out the signed native V
factor on one nappe; their nonzero lower bound uses the constant axial projection
of the original normal coefficient. The full original position jet supplies all
five position derivative bounds. Normal derivatives use the factored field and
its positive lower norm, never a sampled epsilon station. Cone boxes crossing
both nappes require a source partition and do not form one normal chart. Each
analytic panel consumes one visit from the same tessellation invocation ledger.

Shared interval scalar/vector jet records expose the same immutable original
D0-D3 fields at package scope for retained closed owning receipts. Package
consumers may compose these interval operations; source binding and admission
remain owned by prepared providers, never inferred from a naked jet value.

Analytic closed-station panel receipts retain complete parameter boxes and the
original radial/factored normal field. A cone singleton at its apex requires an
explicit owning positive or negative nappe; no midpoint chooses orientation.
The same generic panel/receipt and original image cofactor contracts transport
this source interval authority through signed foreign charts.

### Arbitrary Original Boundary Factor Order

Exact original homogeneous normal numerators establish the least common native
boundary-factor multiplicity across all nonzero components. Zero components have
unlimited multiplicity and do not cap the common factor. Exact division proves
all preceding coefficients vanish; positive original W means the remaining
numerator has the same normalized normal as the original normal divided by its
inward factor. Original inward orientation contributes sign to the actual factor
power. Requested panels enclose that retained polynomial and its exact U/V
partials, and bound unit-normal derivatives by partial magnitude divided by the
strict whole-field lower norm. Exact work/storage uses supplied caller admission;
no exact polynomial is constructed from outward interval coefficients.

Native tessellation first uses its existing interval N1 certificate. If the first
factor vanishes, exact factor preparation/evaluation debits every exact work and
storage item through the same invocation proof usage and callback; it never
creates an additional allowance. The original cell depth remains the parent
context for these fixed coefficient operations. Failed nonzero hulls subdivide
under the original cell/depth ceiling; exhausted algebra propagates failure.

Closed-station generic panel union requires identical source, parameter box and
preparation tolerance. It encloses all original owning normal fields and retains
component-wise maxima of one-sided derivative bounds; union itself never proves
smoothness across a native join. Cone normalization must accept all owning sides.

Native pole factor preparation exposes its immutable exact oriented numerator
polynomials to same-module higher normal-field consumers. Each value has already
removed the shared original boundary factor; positive original weight denominator
is a direction gauge only. Silhouette zeros may use this gauge without treating
its magnitude as original surface metric or derivatives.

[Original Revolution](../OriginalRevolution/DESIGN.md) owns algebraic-endpoint
Rodrigues pole germ factors. This component supplies its shared source-bound
normal panel DTO and the native tensor factor recognition only.

A complete pole station normal receipt may aggregate source-owning panels that
partition one closed tangential interval at native knots. It verifies exact
coverage of the requested singleton collapsed coordinate and tangential range,
then encloses every one-sided unit normal. This point-cone receipt establishes no
normal derivative continuity across the join; facet derivative proofs keep their
separate original owning panels.

Collapsed boundary XYZ publication retains the original source/support station,
its structural collapse witness and a complete original position interval.
Tensor endpoints use exact equal original controls under positive weights; cones
use their stored apex; root revolutions use the retained exact axis endpoint.
Nested images map the original interval by their stored affine columns. A single
deterministic numerical representative may be reused for every physical pole
vertex only after the composing caller admits its enclosed point error. Sphere
latitude endpoint symbolism must be established independently of rounded cosine
values before it supplies a structural collapsed XYZ witness.


### Complete Native Panel Boundary Factors

Optional exact panel preparation recognizes every coefficient-proved collapsed
clamped boundary touched by the original owning panel. It divides the shared
normal numerator by all such exact boundary factors, including both ends of one
axis and simultaneous U/V boundaries. Each factor contributes its original
inward orientation raised to its multiplicity. The retained quotient and its
exact partial derivatives are one normal gauge for the whole selected panel;
recognizing only the first collapsed side cannot authorize a closed panel that
also includes another pole. Ordinary noncollapsed boundaries return no factor;
source binding, algebra admission and cancellation failures propagate.

A collapsed boundary requires a closed, exactly clamped domain only in its fixed
coordinate. Its tangential coordinate may retain original periodic owning cells
and lifted translations. Periodic seams are never interpreted as clamped poles.
Canonical sphere pole XYZ is independent of the finite unwrapped longitude box;
its symbolic latitude witness supplies the collapse, without longitude sampling.

### Prepared Whole Normal-Field Bounds

A prepared surface exposes complete unit-normal component bounds on a closed
rectangle. Regular source jets supply the original tangent cross product.
Native owning spans use exact all-touching collapsed-boundary factors where
required; each original side is normalized before its field joins the cover.
Canonical sphere/cone gauges and retained revolution endpoint factors use their
existing source-bound producers. Nested original images transport the whole
source unit field with the original cofactor and signed chart orientation.
The component hull covers every admitted owning side; it is not a smooth-join
receipt or a derivative identity through a discontinuity. Mesh owns facet-angle
admission and may subdivide an inconclusive field under its existing ledger.
Preparation reuse, exact scalar work and depth stay caller owned; temporary-byte
admission remains a separately marked source gap.


A prepared whole unit-normal query may take an explicit original native owning
span. Its source binding and complete selected box are validated under the same
caller work. At native creases or endpoint joins this returns the owning side's
regular or exact factored normal only; it does not include a zero-width neighbor
or infer cross-crease smoothness. Image recursion retains that native owner.
Queries without a token continue to cover every original intersecting owner.

The tessellation exact-pole adapter counts retained exact UInt32 word slots
through the same existing proof counter. Native Taylor byte buffers convert
with the explicit MemoryLayout<UInt32>.stride and checked ceiling division.
Generic caller-ledger normal queries require their caller's storage slot stride;
that count never encodes depth.


Exact pole algebra admits its own original algebra/root depth envelope separately
from geometric tessellation depth. Exact-cell visits charge the same invocation
work counter at the retained outer tessellation depth; they do not add algebra
ancestry depth to a geometric subdivision depth. Storage word counts retain the
explicit UInt32 slot stride and never become depth metadata.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
