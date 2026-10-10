import CADCore

public struct OriginalRollingBallCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalExactScalarDomain,tolerance: ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalRollingBallCurveSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            let capability: OriginalRollingBallCurveSnapshot.Capability,depth: Int
            switch copy input {
            case .bSpline:
                let child=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeCurveFamilySnapshotProvider(tolerance:tolerance))
                    .bind(input,limits:children,using:&a)
                capability = .native(child);depth=child.sourceDepth
            case .surfaceLift(let lift):
                switch (lift.surface,lift.parameterCurve) {
                case (.bSpline,.bSpline):
                    let child=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:tolerance))
                        .bind(lift,limits:children,using:&a)
                    capability = .nativeLift(child);depth=child.sourceDepth
                case (.bSpline,.affine),(.bSpline,.constantU),(.bSpline,.constantV):
                    let child=try DefaultOriginalSourceBindingIssuer(provider:OriginalAffineSurfaceLiftSnapshotProvider(field:field,tolerance:tolerance))
                        .bind(lift,limits:children,using:&a)
                    capability = .retainedLift(child);depth=child.sourceDepth
                case (.procedural(.originalCoons),.bSpline):
                    let provider=OriginalNativePcurveRetainedAtlasLiftSnapshotProvider(host:OriginalCoonsAtlasSnapshotProvider(field:field,tolerance:tolerance),tolerance:tolerance)
                    let child=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(lift,limits:children,using:&a)
                    capability = .coonsNativeLift(child);depth=child.sourceDepth
                case (.procedural(.originalCoons),.affine),(.procedural(.originalCoons),.constantU),(.procedural(.originalCoons),.constantV):
                    let provider=OriginalRetainedAtlasSurfaceLiftSnapshotProvider(host:OriginalCoonsAtlasSnapshotProvider(field:field,tolerance:tolerance),field:field,tolerance:tolerance)
                    let child=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(lift,limits:children,using:&a)
                    capability = .coonsLift(child);depth=child.sourceDepth
                case (.procedural(.originalBoundaryCorrected),.bSpline):
                    let provider=OriginalNativePcurveRetainedAtlasLiftSnapshotProvider(host:OriginalBoundaryCorrectionSnapshotProvider(field:field,tolerance:tolerance),tolerance:tolerance)
                    let child=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(lift,limits:children,using:&a)
                    capability = .boundaryNativeLift(child);depth=child.sourceDepth
                case (.procedural(.originalBoundaryCorrected),.affine),(.procedural(.originalBoundaryCorrected),.constantU),(.procedural(.originalBoundaryCorrected),.constantV):
                    let provider=OriginalRetainedAtlasSurfaceLiftSnapshotProvider(host:OriginalBoundaryCorrectionSnapshotProvider(field:field,tolerance:tolerance),field:field,tolerance:tolerance)
                    let child=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(lift,limits:children,using:&a)
                    capability = .boundaryLift(child);depth=child.sourceDepth
                default:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Remaining lifted rail host/pcurve families
                    // need complete original parameter/guard supply before this rolling-ball
                    // source port can publish their full normalized child cover.
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Other required rolling-ball curve sources
                // must supply their complete original position graphs. This public source
                // adapter refuses them and does not establish whole-family completion.
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            let total=depth.addingReportingOverflow(1)
            guard !total.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRollingBallCurveSnapshot.self))
            let result=OriginalRollingBallCurveSnapshot(original:copy input,capability:capability)
            try a.checkpoint();return .init(original:result,sourceDepth:total.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
