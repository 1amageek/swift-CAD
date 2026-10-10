import CADCore

public struct OriginalRetainedAtlasSurfaceLiftSnapshotProvider<P: OriginalRetainedLiftHostSnapshotting>: OriginalSourceSnapshotting {
    public typealias Source = OriginalRetainedAtlasSurfaceLiftSnapshot<P.Source>
    public let host: P
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(host: P,field: OriginalExactScalarDomain,tolerance: ModelingTolerance) {
        self.host=host;self.field=field;self.tolerance=tolerance
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source> {
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Priority images and non-retained host/pcurve
            // variants need their own complete original correspondence before this source
            // snapshot port may publish them as a complete lift family.
            guard input.exactBSplineImage == nil else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            let surface=try host.bindHost(input.surface,limits:children,using:&admission)
            let pcurve=try DefaultOriginalSourceBindingIssuer(provider:OriginalAffinePcurveSnapshotProvider(field:field,tolerance:tolerance))
                .bind(input.parameterCurve,limits:children,using:&admission)
            // The actual affine validator has fixed scalar/endpoint visits.
            try admission.consumeWork(16)
            if case .affine = input.parameterCurve { try admission.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Double.self)) }
            try input.parameterCurve.validate(on:input.surface,tolerance:tolerance)
            let zero=try field.integer(0,using:&admission),one=try field.integer(1,using:&admission)
            let curve=pcurve.original,ring=curve.originalPolynomials
            for axis in 0..<2 {
                try admission.consumeWork(1)
                try admission.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalExactScalar.self))
                for parameter in [curve.originalCellLowerBound(at:0),curve.originalCellUpperBound(at:0)] {
                    try admission.consumeWork(1)
                    try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactScalar.self))
                    let value=try ring.evaluated(curve.originalCellHomogeneous(at:0)[axis],at:[parameter],using:&admission).value
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Tolerance-only support clamps change
                    // the authored UV. They require complete original correspondence before
                    // this retained atlas lift source can accept those inputs.
                    guard try field.compare(value,zero,using:&admission) != .less,
                        try field.compare(value,one,using:&admission) != .greater else {
                        throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                    }
                }
            }
            let depth=max(surface.sourceDepth,pcurve.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Source.self))
            let result=Source(original:copy input,surface:surface,pcurve:pcurve)
            try admission.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
