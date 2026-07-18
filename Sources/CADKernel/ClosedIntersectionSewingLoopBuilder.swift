import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct ClosedIntersectionSewingLoopBuilder {
    enum SurfaceSide {
        case first
        case second
    }

    func loops(
        for closedIntersection: BooleanClosedFaceIntersection,
        firstStableID: String,
        secondStableID: String,
        tolerance: ModelingTolerance
    ) throws -> (first: BRepSewingLoop, second: BRepSewingLoop) {
        try tolerance.validate()
        guard firstStableID.isEmpty == false,
              secondStableID.isEmpty == false,
              firstStableID != secondStableID else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed intersection sewing loops require distinct stable identities."
            )
        }
        return (
            try loop(
                for: closedIntersection,
                surfaceSide: .first,
                stableID: firstStableID,
                role: .outer,
                curveDirection: .forward,
                tolerance: tolerance
            ),
            try loop(
                for: closedIntersection,
                surfaceSide: .second,
                stableID: secondStableID,
                role: .outer,
                curveDirection: .reversed,
                tolerance: tolerance
            )
        )
    }

    func loop(
        for closedIntersection: BooleanClosedFaceIntersection,
        surfaceSide: SurfaceSide,
        stableID: String,
        role: LoopRole,
        curveDirection: Orientation,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingLoop {
        try tolerance.validate()
        guard stableID.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed intersection sewing loop requires a stable identity."
            )
        }
        let bounds = try parameterBounds(
            closedIntersection.intersection.curve.parameterDomain,
            tolerance: tolerance
        )
        let midpoint = bounds.lower + (bounds.upper - bounds.lower) * 0.5
        let curve = closedIntersection.intersection.curve
        let firstPoint = try curve.point(at: bounds.lower, tolerance: tolerance)
        let midpointPoint = try curve.point(at: midpoint, tolerance: tolerance)
        let endPoint = try curve.point(at: bounds.upper, tolerance: tolerance)
        guard firstPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance),
              firstPoint.isApproximatelyEqual(to: midpointPoint, tolerance: tolerance.distance) == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Closed intersection must provide two non-degenerate deterministic edge spans."
            )
        }
        let pcurve: SurfaceParameterCurve
        switch surfaceSide {
        case .first:
            pcurve = closedIntersection.intersection.firstSurfaceParameterCurve
        case .second:
            pcurve = closedIntersection.intersection.secondSurfaceParameterCurve
        }
        let lowerPcurve = try pcurve.trimmed(
            from: bounds.lower,
            to: midpoint,
            curveDomain: curve.parameterDomain,
            tolerance: tolerance
        )
        let upperPcurve = try pcurve.trimmed(
            from: midpoint,
            to: bounds.upper,
            curveDomain: curve.parameterDomain,
            tolerance: tolerance
        )
        let edges: [BRepSewingEdge]
        switch curveDirection {
        case .forward:
            edges = [
                BRepSewingEdge(
                    stableID: "\(stableID):edge:0",
                    curve: curve,
                    startParameter: bounds.lower,
                    endParameter: midpoint,
                    startPoint: firstPoint,
                    endPoint: midpointPoint,
                    surfaceParameterCurve: lowerPcurve
                ),
                BRepSewingEdge(
                    stableID: "\(stableID):edge:1",
                    curve: curve,
                    startParameter: midpoint,
                    endParameter: bounds.upper,
                    startPoint: midpointPoint,
                    endPoint: endPoint,
                    surfaceParameterCurve: upperPcurve
                ),
            ]
        case .reversed:
            edges = [
                BRepSewingEdge(
                    stableID: "\(stableID):edge:1",
                    curve: curve,
                    startParameter: bounds.upper,
                    endParameter: midpoint,
                    startPoint: endPoint,
                    endPoint: midpointPoint,
                    surfaceParameterCurve: try upperPcurve.reversed(tolerance: tolerance)
                ),
                BRepSewingEdge(
                    stableID: "\(stableID):edge:0",
                    curve: curve,
                    startParameter: midpoint,
                    endParameter: bounds.lower,
                    startPoint: midpointPoint,
                    endPoint: firstPoint,
                    surfaceParameterCurve: try lowerPcurve.reversed(tolerance: tolerance)
                ),
            ]
        }
        return BRepSewingLoop(stableID: stableID, role: role, edges: edges)
    }

    private func parameterBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case let .periodic(period):
            return (0.0, period)
        case .unbounded:
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed intersection sewing cannot consume an unbounded curve."
            )
        }
    }
}
