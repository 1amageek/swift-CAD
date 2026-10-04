# OriginalGraphBand

## Purpose and Scope

This CADGeometry child owns bounded, mesh-only original rational graph-band
certificates. The [parent module](../DESIGN.md) owns its index. The consumer is
CADKernel mesh tessellation under the [CADIR geometric-fidelity contract](../../CADIR/DESIGN.md).
This scope does not repair a pcurve, assert exact UV closure, or complete general
trimmed-surface tessellation. GeometryConversion is an independent sibling.

## Responsibilities and Boundaries

Geometry owns original coefficient enclosures, strict graph monotonicity,
separation, native support regularity, reference-cell coverage, endpoint and
inverse uncertainty, and continuous facet error bounds. Topology owns ordered
coedge-use orientation and shared spatial vertex identity. Kernel owns actual
mesh allocation, FaceRun provenance, compatible grids, facet emission and the
existing TessellationBudget. No BRep ID or caller-provided closure Boolean is a
Geometry proof. No input curve, support, trim or topology is mutated.

## Related Designs

| Design | Relationship | Contract used | Caution |
|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original selected native-span jets and strict normals | Use the exact original support and preparation tolerance |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | Mesh fidelity, retained preflight/emission, checked budgets | This receipt does not admit arbitrary trim or replace rectangle identity |
| [CADIR](../../CADIR/DESIGN.md) | depends on | Facet approximation to original curve/surface | Reference uncertainty is not source UV identity |
| [CurveSurfaceOverlap](../CurveSurfaceOverlap/DESIGN.md) | coordinates with | Whole correspondence evidence | Correspondence alone does not prove planar closure or winding |

## Architecture

```text
Topology: ordered original coedge uses + actual shared vertex points
    -> OriginalRationalGraphBandCertifying
        -> original native rational graph coefficients
        -> exact entry/exit inverse ownership and join uncertainty
        -> selected original support panels / shared proof usage
        -> immutable OriginalGraphBandReceipt
            -> Kernel compatible reference grids / actual mesh stations
            -> receipt whole-facet admission
            -> Kernel checked preflight + emission + FaceRun
```

## Contracts and Invariants

### Input and receipt boundary

The package protocol is `OriginalRationalGraphBandCertifying` with
`certify(input:fidelity:tolerance:proofUsage:) throws -> OriginalGraphBandReceipt`.
The input retains an exact BSplineSurface3D, the original oriented
SurfaceParameterCurve values in an ordered loop, the graph-chain assignment,
and numeric shared-join indices with the actual Point3D vertex. Kernel verifies
ordered original edge-use endpoint IDs, including last-to-first, before passing
these points; Geometry verifies the geometry itself. Coedge pcurve fraction
0/1 already follows use direction and is not reversed again by edge orientation.
A graph-chain reversal is a view of the original law, not a reconstructed curve.

The consumer separately owns a whole spatial-edge correspondence receipt bound
to the actual original curve, directed trim, pcurve, support and tolerance. Its
proven requested deviation ceiling is reserved from the original mesh linear
allowance before Geometry receives the remainder. Geometry certifies
S(original pcurve) versus reference facets; it does not mint a 3D spatial-edge
certificate from a success Boolean. The existing correspondence owner and its
65536 limit are not migrated into this components 262144 proof usage.

The bounded family is finite nonperiodic clamped positive-weight native
piecewise Bezier pcurves of degree at most four, plus original affine constant
coordinate segments, on a regular original nonperiodic selected-span support.
Each interior pcurve knot has multiplicity equal to its degree. Other valid
families refuse explicitly; no rounded generic Bezier extraction is authority.
The support is exactly clamped with one native linear V interval and at least
C0 U continuity; original U intervals may be C0 and retain
separate one-sided normal owners. Every native coefficient and interval is paid
and retained. Required U derivative signs come from outward original homogeneous
Bernstein coefficients, not control-point order or samples.

The immutable receipt binds the complete input, fidelity, tolerance and directed
loop winding. It
retains every graph cell, every original boundary parameter interval, every
uncertain inverse band and every join cell. No caller can mint or modify the
receipt. Materialized mesh stations are approximations with explicit enclosures;
they never become exact source stations. An immutable station carries its unique
receipt owner, selected reference cell, parameter, actual point/normal and
original position/normal error. Facet admission verifies actual positions and
normals against those stations; caller-provided numeric errors are not proof.
A shared mesh point candidate may be reused at a neighboring cell only after
independent original point enclosure admits it there, with separate one-sided
normal ownership. This changes no source station or topology identity.
Kernel must bind the actual facet
positions/normals to the receipt before publication.

### Simple reference completion and original uncertainty

Outside each retained closed join box B, the exact original graph is fixed.
Inside B, the reference family consists of all monotone-U simple graphs joining
exact coefficient/inverse-owned entry and exit points and confined to B. A
certified affine connector establishes that this family is nonempty: its exact
endpoints are in convex B, its entry U is strictly less than its exit U, and the
whole B is separated from every other chain and nonincident source arc. Entry
and exit values are original mathematical values enclosed by the original
inverse owner; interval representatives are not source identity.

Crossing original tail intervals inside B are retained as original uncertainty
cells, not mandatory reference-connector arcs. This distinction is necessary:
the frozen Draft packet upper join has endpoint differences du=dv=2^-53 and
whole original tail slopes greater than 9 and less than 0, which force an
interior crossing. No simple completion can contain both entire crossing arcs.
The component preserves these original intervals and their full geometric
coverage without claiming an exact simple UV boundary for the source loop.

The two outer tips have a separate cap case. At a coefficient/inverse-owned
common U station, a V-monotone vertical affine cap may close the band. It has a
nonzero V extent or a certified point collapse and is not an invertible strict-U
graph segment. The whole cap is disjoint from unrelated arcs except its intended
entry and exit. All original tip intervals remain in uncertainty coverage; a
collapsed tip does not authorize omission of unproved triangles or normalization
of F normals. Original selected support normals remain authority.

Every box and inverse band is retained closed, including all incident original
support spans. Strict coefficient graph separation and winding are proved
outside B. Tip boxes similarly retain both incident chains and complete source
intervals; their reference closure must have a proven simple connector. Boxes
may not overlap unrelated arcs or each other without a separately proven
complete reference cover. Unproved separation, domain, inverse ownership,
nonemptiness, normal or cell cover is a typed refusal. No tail is clipped away
merely to make U stations appear ordered.

### Whole reference cells and joins

Away from join boxes, a cell uses the exact reference map
`F(u,w)=S(u,(1-w)L(u)+wH(u))`, with strict `L(u)<H(u)` and w in [0,1].
Whole native rational graph inversion encloses v, v_u and v_uu, where
`v_u=v_t/u_t` and `v_uu=(v_tt*u_t-v_t*u_tt)/(u_t^3)`.
Original support jets compose with these derivatives. In particular F_uu
includes `S_v*v_uu`; a flat support does not authorize dropping curved trim
interior error. Native support/pcurve breaks and all inverse uncertainty are
retained; no triangle crosses a C0 support knot. Compatible subdivisions retain
one grid at each shared station and separate selected normal owners at creases.

An internal join box only localizes boundary uncertainty; it cannot remove the
vertical strip beneath its U range. This strip retains complete F reference
cells using the coefficient-owned affine connector as the reference boundary.
For any admissible original tail/reference completion in B=[a,b]x[c,d], the
same-u,w V displacement is at most w*(d-c). Its selected original support
position displacement is at most Sv_upper*w*(d-c), computed outward and added
to the same remaining linear allowance with connector endpoint, inverse,
materialization and whole-facet Taylor errors. Original normal enclosures cover
the full strip UV range, not just the boundary box. All strips/caps and original
intervals retain their complete measure. Unknown separation, excessive
uncertainty or unproved full-strip normals refuse explicitly.

For each join cell, original selected support panel r, and actual shared vertex
P, the owner encloses `E_r=sup(q in B intersect r) distance(S(q),P)`.
For an actual candidate facet with vertices M_i it encloses
`D=max_i distance(M_i,P)`. Convex barycentric containment proves the universal
position bound `E_r+D` for every admissible reference completion and every
retained original tail point in B. Original inverse, correspondence and station
materialization errors are included in the same unchanged linear allowance.
A vertex-only mapping cannot omit the retained join cells or original intervals.

Original support normal enclosures cover every closed owning panel over B and
are compared to the actual mesh normals under the existing angular allowance.
No continuous normal law across a C0 knot is inferred. Actual triangle sides
and diagonals separately satisfy maxEdgeLength; axis-only checks are insufficient.

## State, Ownership, and Lifecycle

Source arrays and receipts are immutable Sendable values. Proof usage is a
single invocation-local inout value, never a stored shared mutable cache, escaped
callback or new concurrency policy. The receipt retains its source lifetime.

## Failure, Concurrency, and Constraints

`OriginalTessellationProofUsage` retains one aggregate ceiling 262144 and depth
32 across graph preparation, inverses, separation, selected surface panels,
reference cells, joins and facet admission. A test-only internal initializer
may lower the same ceiling. The original package rectangle API retains its
default ceiling and delegates to the same native traversal; a minimal internal
handoff charges actual visited cells without resetting the caller usage.
Each station materialization and each inverse endpoint shortcut consumes this
same usage before original point, normal, jet or endpoint proof work.
Checked counts precede bounded allocation; cancellation is checked before work,
in adaptive traversal and before a successful receipt or facet admission.

New invalid provenance/input is invalidInput; existing source validation errors
retain their original typed contract. Valid unproved family/coverage is
unsupportedCapability; original singular, numerical, resource and cancellation
failures propagate. Depth/cell exhaustion is resourceLimitExceeded. No resource
ceiling, tolerance, width or private allowance is increased, and no failure is
retried through a rectangle or sampled path.

## Verification and Change Impact

Dedicated OriginalGraphBandTests must execute the actual package protocol and
receipt admission. Literal positive rational native graphs establish original
coefficient monotonicity, graph inversion, source-normal and full-cell fidelity.
An independent nonconvex lower graph on a flat support must reject a facet whose
trim interior error exceeds the linear allowance despite zero support Hessian.
Exact crossing tails test the distinction between reference completion and full
original uncertainty coverage; disconnected vertex geometry, unproved graph
sign, chain crossing outside B, domain escape and box interference refuse.
Forward/reversed uses retain the same geometric cover and winding ownership.
C0 selected support sides retain both normal owners and no crease-crossing facet.
Shared aggregate count, depth, cancellation and invalid/foreign receipt inputs
have behavioral refusal evidence with unchanged limits. Kernel separately owns
actual emitted triangles, all edge lengths, checked counts and FaceRun, then the
original frozen Draft public fixture. A lower receipt alone does not complete
M2 or establish that the real packet passes all admission conditions.

The initial implementation paths are the seven Swift files in this directory
and the native traversal handoff in `../SurfaceTessellationDifferentialBounds.swift`.
`Tests/CADGeometryTests/OriginalGraphBandTests.swift` owns the literal loop/cap,
reversal, flat nonconvex trim, crossing full-strip, unequal-weight rational,
selected C0 normal, actual station/diagonal, aggregate resource, invalid vertex
and cancellation declarations. Existing OriginalNativeSpanTessellationTests
owns compatibility of the original default traversal. Compile/runtime evidence
is required before this bounded component is complete.
