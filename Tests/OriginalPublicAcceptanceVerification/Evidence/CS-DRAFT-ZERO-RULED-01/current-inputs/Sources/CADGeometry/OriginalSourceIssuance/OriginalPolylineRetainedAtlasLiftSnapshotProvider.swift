import CADCore

/// Composes original host authority with the retained Euclidean arc-length owner.
public struct OriginalPolylineRetainedAtlasLiftSnapshotProvider<P: OriginalRetainedLiftHostSnapshotting>: OriginalSourceSnapshotting {
    public typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<P.Source>
    public let host: P
    public let pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>
    public init(host: P,pcurve: OriginalSourceBinding<OriginalPolylinePcurveSnapshot>) {
        self.host=host;self.pcurve=pcurve
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source> {
        let original=copy input
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try a.consumeWork(1)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Priority images need their own complete
                // original equality and parameter correspondence. This retained-atlas
                // polyline source port cannot certify that required public family yet.
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
                let f=pcurve.original.originalField
                let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                for point in retained {
                    for axis in 0..<2 {
                        try a.consumeWork(1)
                        let value=try f.binary64(exactly:axis==0 ? point.u:point.v,using:&a)
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Tolerance-only UV clamps change
                        // the authored map. This exact source port requires their complete
                        // correspondence before accepting out-of-support polyline vertices.
                        guard try f.compare(value,zero,using:&a) != .less,
                            try f.compare(value,one,using:&a) != .greater else {
                            throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                        }
                    }
                }
                let surface=try host.bindHost(original.surface,limits:children,using:&a)
                let depth=max(surface.sourceDepth,pcurve.sourceDepth).addingReportingOverflow(1)
                guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Source.self))
                let result=Source(original:original,surface:surface,pcurve:pcurve)
                try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
            }
        } catch { throw .init(preserving:error) }
    }
}
