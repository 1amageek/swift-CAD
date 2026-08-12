import CADCore
import CADGeometry

public struct BooleanTrimmedFaceIntersection: Codable, Hashable, Sendable {
    public let intersection: SurfaceSurfaceIntersectionCurve
    public let startParameter: Double
    public let endParameter: Double
    public let start: BooleanUVPoint
    public let end: BooleanUVPoint

    public init(
        intersection: SurfaceSurfaceIntersectionCurve,
        startParameter: Double,
        endParameter: Double,
        start: BooleanUVPoint,
        end: BooleanUVPoint,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        // Endpoints snap to canonical junction points on source boundary
        // geometry, sitting up to eight tolerances from the exact curve.
        guard startParameter.isFinite,
              endParameter.isFinite,
              endParameter - startParameter > tolerance.angle,
              start.residual <= tolerance.distance * 8.0,
              end.residual <= tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Trimmed face intersection requires an ordered verified parameter interval."
            )
        }
        let exactStart = try intersection.curve.point(at: startParameter, tolerance: tolerance)
        let exactEnd = try intersection.curve.point(at: endParameter, tolerance: tolerance)
        let residual = max(
            (exactStart - start.point).length,
            (exactEnd - end.point).length,
            intersection.maximumResidual
        )
        guard residual <= tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Trimmed face intersection endpoints do not match the exact curve."
            )
        }
        self.intersection = intersection
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.start = start
        self.end = end
    }

    public var midpointParameter: Double {
        startParameter + (endParameter - startParameter) * 0.5
    }
}


// Bounded-frame equality: the intersection member carries the large
// certified truth payloads, so it compares in its own frame.
extension BooleanTrimmedFaceIntersection {
    public static func == (
        lhs: BooleanTrimmedFaceIntersection,
        rhs: BooleanTrimmedFaceIntersection
    ) -> Bool {
        lhs.startParameter == rhs.startParameter
            && lhs.endParameter == rhs.endParameter
            && lhs.start == rhs.start
            && lhs.end == rhs.end
            && equalsIntersection(lhs, rhs)
    }

    @inline(never)
    private static func equalsIntersection(
        _ lhs: BooleanTrimmedFaceIntersection,
        _ rhs: BooleanTrimmedFaceIntersection
    ) -> Bool {
        lhs.intersection == rhs.intersection
    }
}
