import CADCore

public struct OriginalNativeSurfaceLiftSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalNativeSurfaceLiftSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Lift source issuance still requires general
            // surface/pcurve families and a retained equality theorem for priority images.
            // This Native source port refuses those branches until complete correspondence exists.
            guard input.exactBSplineImage == nil, case .bSpline(let pcurve) = input.parameterCurve else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            let surface = try DefaultOriginalSourceBindingIssuer(provider:
                OriginalNativeSurfaceFamilySnapshotProvider(tolerance:tolerance)).bind(input.surface,limits:children,using:&a)
            let curve = try DefaultOriginalSourceBindingIssuer(provider:
                OriginalBSplinePcurveSnapshotProvider(tolerance:tolerance)).bind(pcurve,limits:children,using:&a)
            let native = surface.original
            let lowerU = native.uKnots[native.uDegree], upperU = native.uKnots[native.uControlPointCount]
            let lowerV = native.vKnots[native.vDegree], upperV = native.vKnots[native.vControlPointCount]
            // Whole-image proof uses original coefficients, never a guessed inverse or UV clamp.
            let contained = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalQuadraticPcurveContainment.contains(pcurve,
                    u: native.isUPeriodic ? .unbounded : .closed(lowerU, upperU),
                    v: native.isVPeriodic ? .unbounded : .closed(lowerV, upperV), using: &usage)
            }.value
            if contained != true {
                for point in pcurve.controlPoints {
                    try a.consumeWork(1)
                    guard try input.surface.uDomain.contains(point.x,tolerance:tolerance),
                        try input.surface.vDomain.contains(point.y,tolerance:tolerance) else {
                        throw OriginalSourceIssuanceFailure.invalidSource
                    }
                    try a.consumeWork(1)
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy lift evaluation clamps UV inside
                    // tolerance. This exact source port cannot publish that implicit geometry change.
                    // Unproved out-of-support images require complete original correspondence proofs.
                    guard (native.isUPeriodic || (point.x >= lowerU && point.x <= upperU)),
                        (native.isVPeriodic || (point.y >= lowerV && point.y <= upperV)) else {
                        throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                    }
                }
            }
            let depth = max(surface.sourceDepth,curve.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalNativeSurfaceLiftSnapshot.self))
            let result = OriginalNativeSurfaceLiftSnapshot(original:copy input,surface:surface,pcurve:curve)
            try a.checkpoint(); return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
