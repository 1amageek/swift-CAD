import CADCore

public struct OriginalAffineSurfaceLiftSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalExactScalarDomain, tolerance: ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SurfaceLiftCurve3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAffineSurfaceLiftSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): General/periodic surface lifts and priority
            // images need their own complete source correspondence. This affine pcurve port
            // cannot complete those families through a fitted or sampled replacement.
            guard input.exactBSplineImage == nil else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            let surface=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:tolerance))
                .bind(input.surface,limits:children,using:&a)
            let pcurve=try DefaultOriginalSourceBindingIssuer(provider:OriginalAffinePcurveSnapshotProvider(field:field,tolerance:tolerance))
                .bind(input.parameterCurve,limits:children,using:&a)
            // The actual affine validator has fixed scalar/endpoint visits and no descendant
            // surface validation. Prepay its visits and two temporary Double arrays.
            try a.consumeWork(16)
            if case .affine = input.parameterCurve { try a.retainStorage(bytes:exactScalarPayloadBytes(count:8,of:Double.self)) }
            try input.parameterCurve.validate(on:input.surface,tolerance:tolerance)
            let native=surface.original,f=field,curve=pcurve.original,ring=curve.originalPolynomials
            for axis in 0..<2 {
                try a.consumeWork(1)
                let lower=try f.binary64(exactly:axis == 0 ? native.uKnots[native.uDegree]:native.vKnots[native.vDegree],using:&a)
                let upper=try f.binary64(exactly:axis == 0 ? native.uKnots[native.uControlPointCount]:native.vKnots[native.vControlPointCount],using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalExactScalar.self))
                for parameter in [curve.originalCellLowerBound(at:0),curve.originalCellUpperBound(at:0)] {
                    try a.consumeWork(1)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactScalar.self))
                    let value=try ring.evaluated(curve.originalCellHomogeneous(at:0)[axis],at:[parameter],using:&a).value
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy tolerance-only UV clamps are not
                    // original source equality. Full out-of-support correspondence must exist
                    // before this exact lift port can publish those inputs successfully.
                    guard try f.compare(value,lower,using:&a) != .less,try f.compare(value,upper,using:&a) != .greater else {
                        throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                    }
                }
            }
            let depth=max(surface.sourceDepth,pcurve.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalAffineSurfaceLiftSnapshot.self))
            let result=OriginalAffineSurfaceLiftSnapshot(original:copy input,surface:surface,pcurve:pcurve)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
