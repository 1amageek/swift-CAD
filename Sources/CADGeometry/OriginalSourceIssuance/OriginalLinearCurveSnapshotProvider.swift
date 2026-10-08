import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Curve3D
import enum CADGeometry.AnalyticCurve3D
import L0
import SourceIssuer
#endif

public struct OriginalLinearCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalLinearCurveSnapshot> {
        do {
            try admission.checkpoint()
            let origin: Point3D, direction: Vector3D
            switch copy input {
            case .line(let line): origin = line.origin; direction = line.direction
            case .analytic(.line(let point, let vector)): origin = point; direction = vector
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            // Both accepted families perform a fixed-size coordinate/direction check.
            try admission.consumeWork(8)
            try input.validate(tolerance: tolerance)
            let snapshot = OriginalLinearCurveSnapshot(original: copy input, origin: origin, direction: direction)
            try admission.checkpoint(); return .init(original: snapshot, sourceDepth: 0)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
