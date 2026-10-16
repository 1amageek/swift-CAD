import CADCore

/// Reuses prepared arc-length authority and proves whole polyline host inclusion.
public struct OriginalPolylineSurfaceLiftSnapshotProvider: OriginalSourceSnapshotting {
    public let pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>
    public let tolerance: ModelingTolerance
    public init(pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>, tolerance: ModelingTolerance) {
        self.pcurve=pcurve; self.tolerance=tolerance
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalPolylineSurfaceLiftSnapshot> {
        let original=copy input
        do {
            return try admission.withProofScope { a in
                try a.checkpoint(); try a.consumeWork(1)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Priority-image and non-Native host lifts
                // need complete original correspondence at their own source ports. This
                // prepared Native/polyline port must not certify those public input families.
                guard original.exactBSplineImage == nil else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                try pcurve.require(children)
                let inherited=pcurve.original.originalProofDepth
                try a.admitDepth(value:inherited.value,coefficient:inherited.coefficient)
                guard case .polyline(let points)=original.parameterCurve,
                    case .polyline(let retained)=pcurve.original.original,
                    points.count==retained.count else { throw OriginalSourceIssuanceFailure.foreignBinding }
                for index in points.indices {
                    try a.consumeWork(3)
                    guard points[index].u==retained[index].u,points[index].v==retained[index].v else {
                        throw OriginalSourceIssuanceFailure.foreignBinding
                    }
                }
                let surface=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:tolerance))
                    .bind(original.surface,limits:children,using:&a)
                let native=surface.original,f=pcurve.original.originalField
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    if native.isPeriodic(in:axis) { continue }
                    let lower=try f.binary64(exactly:axis==0 ? native.uKnots[native.uDegree]:native.vKnots[native.vDegree],using:&a)
                    let upper=try f.binary64(exactly:axis==0 ? native.uKnots[native.uControlPointCount]:native.vKnots[native.vControlPointCount],using:&a)
                    for point in retained {
                        try a.consumeWork(1)
                        let value=try f.binary64(exactly:axis==0 ? point.u:point.v,using:&a)
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy tolerance-only UV clamps
                        // require their own whole correspondence. This source port refuses
                        // them until authored UV can be retained through the public lift path.
                        guard try f.compare(value,lower,using:&a) != .less,
                            try f.compare(value,upper,using:&a) != .greater else {
                            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                        }
                    }
                }
                let depth=max(surface.sourceDepth,pcurve.sourceDepth).addingReportingOverflow(1)
                guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPolylineSurfaceLiftSnapshot.self))
                let result=OriginalPolylineSurfaceLiftSnapshot(original:original,surface:surface,pcurve:pcurve)
                try a.checkpoint(); return .init(original:result,sourceDepth:depth.partialValue)
            }
        } catch { throw .init(preserving:error) }
    }
}
