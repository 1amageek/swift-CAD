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

struct CoaxialConeTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "CoaxialConeTorusSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "CoaxialConeTorusSurfaceIntersector has no ordinary original-proof publication.")
    }

    private func appendCandidate(
        _ candidate: (radius: Double, axis: Double, tangent: Bool),
        to candidates: inout [(radius: Double, axis: Double, tangent: Bool)],
        tolerance: ModelingTolerance
    ) {
        if let index = candidates.firstIndex(where: {
            abs($0.radius - candidate.radius) <= tolerance.distance
                && abs($0.axis - candidate.axis) <= tolerance.distance
        }) {
            candidates[index].tangent = candidates[index].tangent
                && candidate.tangent
        } else {
            candidates.append(candidate)
        }
    }

    private func candidateOrder(
        _ lhs: (radius: Double, axis: Double, tangent: Bool),
        _ rhs: (radius: Double, axis: Double, tangent: Bool)
    ) -> Bool {
        if lhs.axis != rhs.axis { return lhs.axis < rhs.axis }
        return lhs.radius < rhs.radius
    }

    private func unsupported(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
