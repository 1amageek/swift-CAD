import CADCore

public struct OriginalNativePcurveRetainedAtlasLiftSnapshotProvider<P: OriginalRetainedLiftHostSnapshotting>: OriginalSourceSnapshotting {
    public typealias Source = OriginalNativePcurveRetainedAtlasLiftSnapshot<P.Source>
    public let host: P
    public let tolerance: ModelingTolerance
    public init(host: P,tolerance: ModelingTolerance) { self.host=host;self.tolerance=tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source> {
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Priority images and non-Native pcurves
            // need complete original correspondence before this retained-host lift source
            // port can publish those required families successfully.
            guard input.exactBSplineImage == nil,case .bSpline(let originalPcurve)=input.parameterCurve else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            let surface=try host.bindHost(input.surface,limits:children,using:&admission)
            let pcurve=try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplinePcurveSnapshotProvider(tolerance:tolerance))
                .bind(originalPcurve,limits:children,using:&admission)
            // Child validation already visited every knot, weight and control point.
            // Preserve the actual lift's control-domain admission without revalidating it.
            for point in originalPcurve.controlPoints {
                try admission.consumeWork(1)
                guard try input.surface.uDomain.contains(point.x,tolerance:tolerance),
                    try input.surface.vDomain.contains(point.y,tolerance:tolerance) else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                try admission.consumeWork(1)
                // FIXME(INCOMPLETE_IMPLEMENTATION): A tolerance-only UV clamp changes
                // the original map. General out-of-support hulls need complete guarded
                // correspondence before this exact source port may accept them.
                guard point.x>=0,point.x<=1,point.y>=0,point.y<=1 else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
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
