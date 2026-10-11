import CADCore
@testable import CADGeometry
@testable import DraftZeroRuledPort
import struct CADGeometry.CurveSurfaceIntersectionResult

/// No successful result crosses the diagnostic namespace boundary.
struct OriginalDraftedZeroLinePublicProducer {
    enum AssemblyFailure: Error { case selectedResultRequiresCurrentDTO }
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CADGeometry.CurveSurfaceIntersectionResult? {
        let actual = try DraftZeroRuledPort.OriginalDraftedZeroLinePublicProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation,
            retainingRelations: retainingRelations)
        guard actual == nil else {
            print("ASSEMBLY_STOP OriginalDraftedZeroLinePublicProducer returned a current DTO; no conversion performed")
            throw AssemblyFailure.selectedResultRequiresCurrentDTO
        }
        print("SELECTED_PRODUCER_DECLINED OriginalDraftedZeroLinePublicProducer actual current producer returned nil")
        return nil
    }
}

import CADCore
@testable import CADGeometry
@testable import DraftZeroRuledPort
import struct CADGeometry.CurveSurfaceIntersectionResult

/// No successful result crosses the diagnostic namespace boundary.
struct OriginalRetainedLiftPlanePublicProducer {
    enum AssemblyFailure: Error { case selectedResultRequiresCurrentDTO }
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CADGeometry.CurveSurfaceIntersectionResult? {
        let actual = try DraftZeroRuledPort.OriginalRetainedLiftPlanePublicProducer().resolve(curve: curve, surface: surface,
            options: options, tolerance: tolerance, invocation: invocation,
            retainingRelations: retainingRelations)
        guard actual == nil else {
            print("ASSEMBLY_STOP OriginalRetainedLiftPlanePublicProducer returned a current DTO; no conversion performed")
            throw AssemblyFailure.selectedResultRequiresCurrentDTO
        }
        print("SELECTED_PRODUCER_DECLINED OriginalRetainedLiftPlanePublicProducer actual current producer returned nil")
        return nil
    }
}
