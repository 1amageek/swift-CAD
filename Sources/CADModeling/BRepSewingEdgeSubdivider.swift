import CADCore
import CADGeometry
import CADIR

package struct BRepSewingEdgeSubdivider {
    package init() {}

    package func subdivide(
        _ edge: BRepSewingEdge,
        at points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingEdge] {
        try tolerance.validate()
        let span = edge.endParameter - edge.startParameter
        guard abs(span) > max(tolerance.angle, tolerance.distance) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact source edge subdivision requires a non-degenerate trim."
            )
        }
        var fractions = [0.0, 1.0]
        var fractionPoints: [(fraction: Double, point: Point3D)] = []
        for point in points {
            guard let parameter = try projectedParameter(
                of: point,
                on: edge,
                tolerance: tolerance
            ) else {
                continue
            }
            let fraction = (parameter - edge.startParameter) / span
            if fraction > tolerance.distance,
               fraction < 1.0 - tolerance.distance {
                fractions.append(fraction)
                fractionPoints.append((fraction: fraction, point: point))
            }
        }
        fractions.sort()
        let fractionTolerance = max(
            tolerance.distance / abs(span),
            tolerance.angle / abs(span),
            Double.ulpOfOne * 32.0
        )
        var uniqueFractions: [Double] = []
        for fraction in fractions where
            uniqueFractions.last.map({ abs($0 - fraction) <= fractionTolerance }) != true {
            uniqueFractions.append(fraction)
        }
        return try zip(uniqueFractions, uniqueFractions.dropFirst()).enumerated().map {
            index, interval in
            let lowerFraction = interval.0
            let upperFraction = interval.1
            let lowerParameter = edge.startParameter + span * lowerFraction
            let upperParameter = edge.startParameter + span * upperFraction
            // Cut endpoints carry the caller's canonical junction points,
            // and terminal cuts keep the edge's declared endpoints, so
            // subdivision cannot displace an endpoint off its junction.
            func declaredPoint(
                fraction: Double,
                parameter: Double
            ) throws -> Point3D {
                if fraction == 0.0 { return edge.startPoint }
                if fraction == 1.0 { return edge.endPoint }
                if let match = fractionPoints.first(where: {
                    abs($0.fraction - fraction) <= fractionTolerance
                }) {
                    return match.point
                }
                return try edge.curve.point(at: parameter, tolerance: tolerance)
            }
            let startPoint = try declaredPoint(
                fraction: lowerFraction,
                parameter: lowerParameter
            )
            let endPoint = try declaredPoint(
                fraction: upperFraction,
                parameter: upperParameter
            )
            return BRepSewingEdge(
                stableID: "\(edge.stableID):segment:\(index)",
                curve: edge.curve,
                startParameter: lowerParameter,
                endParameter: upperParameter,
                startPoint: startPoint,
                endPoint: endPoint,
                surfaceParameterCurve: try edge.surfaceParameterCurve.subcurve(
                    fromNormalizedFraction: lowerFraction,
                    toNormalizedFraction: upperFraction,
                    tolerance: tolerance
                ),
                parentSubshapeIDs: edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: lowerFraction <= fractionTolerance
                    ? edge.startVertexParentSubshapeIDs
                    : edge.parentSubshapeIDs,
                endVertexParentSubshapeIDs: upperFraction >= 1.0 - fractionTolerance
                    ? edge.endVertexParentSubshapeIDs
                    : edge.parentSubshapeIDs
            )
        }
    }

    package func contains(
        _ point: Point3D,
        on edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try projectedParameter(of: point, on: edge, tolerance: tolerance) != nil
    }

    private func projectedParameter(
        of point: Point3D,
        on edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let lower = min(edge.startParameter, edge.endParameter)
        let upper = max(edge.startParameter, edge.endParameter)
        let interval = try ScalarInterval(lower: lower, upper: upper)
        do {
            return try edge.curve.parameterProjection(
                of: point,
                options: CurveParameterProjectionOptions(parameterRange: interval),
                tolerance: tolerance
            ).parameter
        } catch let error as KernelError where error.code == .intersectionFailure {
            guard case let .periodic(period) = edge.curve.parameterDomain else {
                return nil
            }
            do {
                let projection = try edge.curve.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
                var parameter = projection.parameter
                while parameter < lower - tolerance.angle {
                    parameter += period
                }
                while parameter > upper + tolerance.angle {
                    parameter -= period
                }
                guard parameter >= lower - tolerance.angle,
                      parameter <= upper + tolerance.angle else {
                    return nil
                }
                return min(max(parameter, lower), upper)
            } catch let periodicError as KernelError where periodicError.code == .intersectionFailure {
                return nil
            }
        }
    }
}
