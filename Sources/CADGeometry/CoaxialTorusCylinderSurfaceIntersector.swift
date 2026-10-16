#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

struct CoaxialTorusCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "CoaxialTorusCylinderSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "CoaxialTorusCylinderSurfaceIntersector has no ordinary original-proof publication.")
    }
}
