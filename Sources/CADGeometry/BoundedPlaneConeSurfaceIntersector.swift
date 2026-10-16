import CADCore
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

struct BoundedPlaneConeSurfaceIntersector {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Ordinary SSI dispatch reaches this direct entry.
    // The former numerical/tolerance branches did not establish original common-set
    // authority. U4 must supply complete original source/UV coverage before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceSurfaceIntersection]? {
        execution.context = execution.context.at(stage: .relation)
        do {
            try execution.checkpoint()
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "BoundedPlaneConeSurfaceIntersector requires complete original source relation authority.")
        } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Existing candidate/source helper methods call
    // this ordinary publication entry. It performs no numeric solve or fallback;
    // U4 must provide source-bound relation proof and direct execution before success.
    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        try CurrentTaskCancellationChecker().checkCancellation()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "BoundedPlaneConeSurfaceIntersector has no ordinary original-proof publication.")
    }

    private static func planeSurface(
        _ firstSurface: Surface3D,
        secondSurface: Surface3D
    ) -> Surface3D {
        if case .plane = CanonicalAnalyticSurface(firstSurface) {
            return firstSurface
        }
        return secondSurface
    }

    private static func analyticConic(
        _ intersection: SurfaceSurfaceIntersection
    ) -> AnalyticCurve3D? {
        guard case let .curve(value) = intersection,
              case let .parametric(.analytic(curve)) = value.truth else {
            return nil
        }
        switch curve {
        case .hyperbola, .parabola:
            return curve
        case .line, .circle, .arc, .ellipse, .planeTorus:
            return nil
        }
    }

    private func parameter(
        of point: Point3D,
        on curve: AnalyticCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let parameter: Double
        switch curve {
        case let .hyperbola(hyperbola):
            parameter = try hyperbola.parameter(for: point, tolerance: tolerance)
        case let .parabola(parabola):
            parameter = try parabola.parameter(for: point, tolerance: tolerance)
        case .line, .circle, .arc, .ellipse, .planeTorus:
            return nil
        }
        let reconstructed = try curve.point(at: parameter, tolerance: tolerance)
        return (reconstructed - point).length <= tolerance.distance ? parameter : nil
    }

    private func deduplicated(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        points.sorted(by: lexicographicPointOrder).reduce(into: []) { result, point in
            if result.last.map({ ($0 - point).length <= tolerance.distance }) != true {
                result.append(point)
            }
        }
    }

    private func deduplicated(
        _ parameters: [Double],
        tolerance: ModelingTolerance
    ) -> [Double] {
        parameters.sorted().reduce(into: []) { result, parameter in
            if result.last.map({ abs($0 - parameter) <= tolerance.relative }) != true {
                result.append(parameter)
            }
        }
    }

    private func lexicographicPointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
