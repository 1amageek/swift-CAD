# CS-DERIVATIVE-LIFT-PLANE-01 selected-entry observation

The prechange retained-lift exact producer returns `nil` for the existing weighted,
projected derivative host and its mode-0 Native diagonal pcurve. The ordinary rich
entry then reaches the admitted verification assembly's `unselectedLegacyRoute`
tripwire. That tripwire is an assembly stop, not a production geometry failure;
the complete production fallback behavior remains unobserved.

| Observation | Bound evidence |
|---|---|
| Actual input | Existing `DerivativeHostShape.shape(weighted:true, projected:true)`, degree1 pcurve knots `[0,0,0.5,1,1]`, diagonal controls, full authored T and whole plane x=1/2, normal unitX |
| Independent complete oracle (corrected arithmetic) | X=t on the complete requested interval, so T=1/2 is the only root. Host UV=(1/2,1/2), XYZ=(1/2,1/2,5/32), plane UV=(5/32,-1/2); all eight closed knot incidents, image and coordinate-fiber dimensions0 |
| Selected exact entry | `OriginalRetainedLiftPlanePublicProducer.resolve(..., retainingRelations:true)` returns nil |
| Ordinary rich assembly | Actual current rich entry falls through to the explicit verification-only tripwire; it does not publish a result in this assembly |
| Compile/link | 2.992 seconds, exit0 |
| Runtime | 0.624 seconds, exit0; diagnostic completion only |
| Bounds | Wall/CPU120 seconds per command; original CAD caller ceilings unchanged; zero owned descendants remain |
| Reuse | 3,424 admitted source/product/log checks match before and after; no lower proof or broad build was repeated |

The row-constant weights cancel from the original X quotient and the original
U basis/control X yields X=u. Projection changes only Z and the Hermite correction
preserves X. At u=v=1/2 the independent positional expression is
`(1/4)*(1/2-5/32+15/64+3/64)=5/32`.
The original `OriginalPlaneHermiteDerivativeBasis` owner defines
`h11(v)=-4*v^3+7*v^4-3*v^5`, hence `h11(1/2)=-5/32`.
Both the positional evaluator and rational atlas consume that owner. The
previously derived65/512 used an erroneous h11 value of-5/64. This was our
oracle calculation error, not a change to the authored input or source law.
The immutable prechange fixture and log retain that old value; their selected
entry observations remain valid, but they are not accepted positional evidence.

The missing exact public-entry receipt is the observed gap. Existing derivative
source/DI and Native-pcurve lift capabilities remain its premises, rather than a
new source implementation prerequisite. The next change must consume those
receipts, preserve every original coordinate/incident/guard and complete the
ordinary public result. No cell, source family, M4-M8 or requirement completion
is established by this diagnostic.

Raw [receipt](native-observation/receipt.json),
[runtime log](native-observation/observation.log),
[compiler command](native-observation/compile-command.json) and
[immutable evidence manifest](evidence-manifest.json) retain original bytes.
The receipt SHA256 is
`685eff6a1eec0ef4ab2e7dea13cc899c2b5820ce3c9dc16052e1046700b148eb`.
Historical source comparisons are explicit comparators from their original
commits; they are not claims that the corresponding current-root bytes match.

The prechange production comparator is commit `99d61ff19a6990ae7fc3174d63603c4cdf30263e`,
`Sources/CADGeometry/NativeExactGeometricRelations/OriginalRetainedLiftPlanePublicProducer.swift`.
A later producer edit does not turn this historical receipt into a current-root
byte-equality claim.
