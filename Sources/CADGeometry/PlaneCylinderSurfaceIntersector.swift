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

struct PlaneCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
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
                message: "PlaneCylinderSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "PlaneCylinderSurfaceIntersector has no ordinary original-proof publication.")
    }

    private func axialLines(
        plane: CanonicalAnalyticSurface.Plane,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let signedDistance = (cylinder.origin - plane.origin).dot(plane.normal)
        let normalizedOffset = -signedDistance / cylinder.radius
        let normalizedTolerance = tolerance.distance / cylinder.radius
        guard abs(normalizedOffset) <= 1.0 + normalizedTolerance else { return [] }
        let clampedOffset = min(max(normalizedOffset, -1.0), 1.0)
        let transverse = try cylinder.axis.cross(plane.normal).normalized(
            tolerance: tolerance.angle
        )
        let transverseMagnitude = sqrt(max(0.0, 1.0 - clampedOffset * clampedOffset))
        let firstRadial = plane.normal * clampedOffset + transverse * transverseMagnitude
        let kind: CurveSurfaceIntersectionKind = transverseMagnitude <= normalizedTolerance
            ? .tangent
            : .transverse
        var results = [try verifier.curve(
            .line(Line3D(
                origin: cylinder.origin + firstRadial * cylinder.radius,
                direction: cylinder.axis
            )),
            kind: kind,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
            tolerance: tolerance
        )]
        if kind == .transverse {
            let secondRadial = plane.normal * clampedOffset - transverse * transverseMagnitude
            results.append(try verifier.curve(
                .line(Line3D(
                    origin: cylinder.origin + secondRadial * cylinder.radius,
                    direction: cylinder.axis
                )),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
                tolerance: tolerance
            ))
        }
        return results
    }
}
