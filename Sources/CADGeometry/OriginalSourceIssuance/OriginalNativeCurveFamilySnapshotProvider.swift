import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Curve3D
import struct CADGeometry.BSplineCurve3D
import L0
import SourceIssuer
#endif

/// An explicit family capability, usable as an injected ruled boundary provider.
public struct OriginalNativeCurveFamilySnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<BSplineCurve3D> {
        do {
            try admission.checkpoint()
            guard case .bSpline(let native) = copy input else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            return try OriginalBSplineCurveSnapshotProvider(tolerance: tolerance)
                .snapshot(native, limits: limits, using: &admission)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
