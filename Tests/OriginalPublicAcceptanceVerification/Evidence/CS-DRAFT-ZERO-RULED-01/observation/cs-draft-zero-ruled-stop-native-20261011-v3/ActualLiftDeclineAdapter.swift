import CADCore
@testable import CADGeometry
@testable import DerivativeLiftPlanePort
import struct CADGeometry.CurveSurfaceIntersectionResult

/// No successful result or receipt crosses this diagnostic namespace boundary.
struct OriginalRetainedLiftPlanePublicProducer {
    enum AssemblyFailure: Error { case selectedResultRequiresCurrentDTO }
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CADGeometry.CurveSurfaceIntersectionResult? {
        let actual = try DerivativeLiftPlanePort.OriginalRetainedLiftPlanePublicProducer().resolve(
            curve: curve, surface: surface, options: options, tolerance: tolerance,
            invocation: invocation, retainingRelations: retainingRelations)
        guard actual == nil else {
            print("ASSEMBLY_STOP selected lift result requires its current DTO; no conversion performed")
            throw AssemblyFailure.selectedResultRequiresCurrentDTO
        }
        print("SELECTED_PRODUCER_DECLINED actual current producer returned nil")
        return nil
    }
}
