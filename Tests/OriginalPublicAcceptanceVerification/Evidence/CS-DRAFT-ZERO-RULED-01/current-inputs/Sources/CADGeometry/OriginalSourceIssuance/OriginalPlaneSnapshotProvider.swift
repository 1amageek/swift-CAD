import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Surface3D
import L0
import SourceIssuer
#endif

public struct OriginalPlaneSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalPlaneSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(8); try tolerance.validate()
            let origin: Point3D,normal: Vector3D
            switch copy input {
            case .plane(let plane):
                guard plane.uDirection == nil else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                origin = plane.origin; normal = plane.normal
            case .analytic(.plane(let point,let vector)): origin = point; normal = vector
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try origin.validate(); try normal.validate()
            guard normal.x != 0 || normal.y != 0 || normal.z != 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
            let snapshot = OriginalPlaneSnapshot(original:copy input,origin:origin,normal:normal)
            try a.checkpoint(); return .init(original:snapshot,sourceDepth:0)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
