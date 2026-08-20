import CADCore
import CADGeometry
import CADIR

package struct BRepSewingEdgeSubdivider {
    private enum AuthoredPcurveProjection {
        case unavailable
        case outside
        case parameter(Double)
    }

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
        let authoredProjector = try makeAuthoredPcurveProjector(
            for: edge,
            tolerance: tolerance
        )
        for point in points {
            guard let parameter = try projectedParameter(
                of: point,
                on: edge,
                authoredProjector: authoredProjector,
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
        let authoredProjector = try makeAuthoredPcurveProjector(
            for: edge,
            tolerance: tolerance
        )
        return try projectedParameter(
            of: point,
            on: edge,
            authoredProjector: authoredProjector,
            tolerance: tolerance
        ) != nil
    }

    private func projectedParameter(
        of point: Point3D,
        on edge: BRepSewingEdge,
        authoredProjector: BSplineCurve3D.ParameterProjector?,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        switch try authoredPcurveProjection(
            of: point,
            on: edge,
            projector: authoredProjector,
            tolerance: tolerance
        ) {
        case .unavailable:
            break
        case .outside:
            return nil
        case let .parameter(parameter):
            return parameter
        }
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

    private func authoredPcurveProjection(
        of point: Point3D,
        on edge: BRepSewingEdge,
        projector: BSplineCurve3D.ParameterProjector?,
        tolerance: ModelingTolerance
    ) throws -> AuthoredPcurveProjection {
        guard case let .surfaceLift(lift) = edge.curve,
              case let .bSpline(parameterCurve) = edge.surfaceParameterCurve,
              case let .closed(parameterLower, parameterUpper) = parameterCurve.domain,
              let projector else {
            return .unavailable
        }
        let surfaceProjection: SurfaceParameterProjection
        do {
            surfaceProjection = try lift.surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .intersectionFailure {
            return .outside
        }
        let u = alignedPeriodicParameter(
            surfaceProjection.u,
            domain: lift.surface.uDomain,
            coordinates: parameterCurve.controlPoints.map(\.x)
        )
        let v = alignedPeriodicParameter(
            surfaceProjection.v,
            domain: lift.surface.vDomain,
            coordinates: parameterCurve.controlPoints.map(\.y)
        )
        let projection: CurveParameterProjection
        do {
            projection = try projector.project(
                Point3D(x: u, y: v, z: 0.0)
            )
        } catch let error as KernelError where error.code == .intersectionFailure {
            return .outside
        }
        let parameterPoint = try parameterCurve.point(
            at: projection.parameter,
            tolerance: tolerance
        )
        let reconstructed = try lift.surface.point(
            u: parameterPoint.x,
            v: parameterPoint.y,
            tolerance: tolerance
        )
        guard (reconstructed - point).length <= tolerance.distance else {
            return .outside
        }
        let fraction = (projection.parameter - parameterLower)
            / (parameterUpper - parameterLower)
        return .parameter(
            edge.startParameter
                + (edge.endParameter - edge.startParameter) * fraction
        )
    }

    private func makeAuthoredPcurveProjector(
        for edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D.ParameterProjector? {
        guard case .surfaceLift = edge.curve,
              case let .bSpline(parameterCurve) = edge.surfaceParameterCurve,
              case let .closed(parameterLower, parameterUpper) = parameterCurve.domain else {
            return nil
        }
        let embeddedCurve = BSplineCurve3D(
            degree: parameterCurve.degree,
            knots: parameterCurve.knots,
            controlPoints: parameterCurve.controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: parameterCurve.weights
        )
        return try embeddedCurve.makeParameterProjector(
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(
                    lower: parameterLower,
                    upper: parameterUpper
                )
            ),
            tolerance: ModelingTolerance(
                distance: max(
                    tolerance.distance,
                    tolerance.angle,
                    tolerance.relative
                ),
                angle: tolerance.angle,
                relative: tolerance.relative
            )
        )
    }

    private func alignedPeriodicParameter(
        _ parameter: Double,
        domain: ParameterDomain,
        coordinates: [Double]
    ) -> Double {
        guard case let .periodic(period) = domain,
              let minimum = coordinates.min(),
              let maximum = coordinates.max() else {
            return parameter
        }
        let center = minimum + (maximum - minimum) * 0.5
        return parameter + ((center - parameter) / period).rounded() * period
    }
}
