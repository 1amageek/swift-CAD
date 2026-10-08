import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.BSplineCurve3D
import L0
import SourceIssuer
#endif

/// Retains the authored curve after the family-owned bounded validation.
public struct OriginalBSplineCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing BSplineCurve3D, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<BSplineCurve3D> {
        do {
            try admission.checkpoint()
            try input.validate(tolerance: tolerance, consumeWork: { try admission.consumeWork(1) })
            try admission.checkpoint()
            return .init(original: copy input, sourceDepth: 0)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
