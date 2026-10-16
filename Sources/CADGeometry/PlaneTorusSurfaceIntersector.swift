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

struct PlaneTorusSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection] {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "PlaneTorusSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "PlaneTorusSurfaceIntersector has no ordinary original-proof publication.")
    }

    private func generalSection(
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try AnalyticAnalyticSurfaceIntersector().intersections(
            first: firstSurface,
            second: secondSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func axialSection(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let height = (plane.origin - torus.center).dot(torus.axis)
        guard abs(height) <= torus.minorRadius + tolerance.distance else { return [] }
        let radialOffset = sqrt(max(
            0.0,
            torus.minorRadius * torus.minorRadius - height * height
        ))
        let center = torus.center + torus.axis * height
        if radialOffset <= tolerance.distance {
            return [try verifier.curve(
                .circle(Circle3D(
                    center: center,
                    normal: plane.normal,
                    radius: torus.majorRadius
                )),
                kind: .tangent,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )]
        }
        return try [torus.majorRadius - radialOffset, torus.majorRadius + radialOffset].map { radius in
            try verifier.curve(
                .circle(Circle3D(center: center, normal: plane.normal, radius: radius)),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
