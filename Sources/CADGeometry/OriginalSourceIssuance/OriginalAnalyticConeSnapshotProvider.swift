import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.AnalyticSurface3D
import L0
import SourceIssuer
#endif

/// Calls the existing authored family validator and basis implementation.
public struct OriginalAnalyticConeSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing AnalyticSurface3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAnalyticConeSnapshot> {
        do {
            try admission.checkpoint(); try admission.consumeWork(8)
            try input.validate(tolerance:tolerance)
            guard case let .cone(apex,axis,halfAngle) = copy input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            // Bound the existing fixed-size cross/normalization operations before execution.
            try admission.consumeWork(40)
            let basis = try analyticOrthonormalBasis(axis,tolerance:tolerance)
            let result = OriginalAnalyticConeSnapshot(original:copy input,halfAngle:halfAngle,
                apex:apex,first:basis.u,second:basis.v,axis:axis)
            try admission.checkpoint()
            return .init(original:result,sourceDepth:0)
        } catch let error as OriginalSourceIssuanceFailure { throw error }
        catch let error as ExactScalarFailure { throw .scalar(error) }
        catch { throw .sourceRejected(error) }
    }
}
