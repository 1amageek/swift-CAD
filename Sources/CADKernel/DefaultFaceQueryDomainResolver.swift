import CADCore
import CADGeometry
import CADTopology
import Foundation

struct DefaultFaceQueryDomainResolver: FaceQueryDomainResolving {
    private let containment: any FaceParameterContainmentSessionPreparing
    private let rectangularDomainResolver:
        any ExactRectangularPcurveDomainResolving
    private let parameterBoundsResolver: any FaceParameterBoundsResolving
    private let spatialBoundsResolver: any FaceSpatialBoundsResolving
    private let surfaceDifferentialEncloser: any SurfaceDifferentialEnclosing

    init(
        containment: any FaceParameterContainmentSessionPreparing =
            DefaultFacePointContainmentTester(),
        rectangularDomainResolver:
            any ExactRectangularPcurveDomainResolving =
                ExactRectangularPcurveDomainResolver(),
        parameterBoundsResolver: any FaceParameterBoundsResolving =
            DefaultFaceParameterBoundsResolver(),
        spatialBoundsResolver: any FaceSpatialBoundsResolving =
            BRepFaceBoundingBoxBuilder(),
        surfaceDifferentialEncloser: any SurfaceDifferentialEnclosing =
            DefaultSurfaceDifferentialEncloser()
    ) {
        self.containment = containment
        self.rectangularDomainResolver = rectangularDomainResolver
        self.parameterBoundsResolver = parameterBoundsResolver
        self.spatialBoundsResolver = spatialBoundsResolver
        self.surfaceDifferentialEncloser = surfaceDifferentialEncloser
    }

    func makeContainmentSession(
        for faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> any FaceParameterContainmentSession {
        try containment.makeParameterContainmentSession(
            for: [faceID],
            in: model,
            tolerance: tolerance
        )
    }

    func closestBoundaryProjection(
        to point: Point3D,
        from supportParameter: SurfaceParameter,
        on faceID: FaceID,
        surface: Surface3D,
        in model: BRepModel,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection {
        guard let face = model.faces[faceID] else {
            throw FeatureEvaluationError.missingInput(
                "Surface closest-point query references a missing face."
            )
        }
        if let rectangle = try rectangularDomainResolver.resolve(
            face: face,
            model: model,
            tolerance: tolerance
        ) {
            return try closestRectangularBoundaryProjection(
                to: point,
                from: supportParameter,
                domain: rectangle,
                surface: surface,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
        }
        return try closestGeneralBoundaryProjection(
            to: point,
            face: face,
            surface: surface,
            model: model,
            maximumIterations: maximumIterations,
            tolerance: tolerance
        )
    }

    func directionalSearchDomain(
        from origin: Point3D,
        direction: Vector3D,
        on faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceDirectionalSearchDomain {
        let parameterBounds = try parameterBoundsResolver.bounds(
            for: faceID,
            in: model,
            tolerance: tolerance
        )
        let bounds = try spatialBoundsResolver.bounds(
            for: faceID,
            in: model,
            tolerance: tolerance
        )
        let parameters = corners(of: bounds).map {
            ($0 - origin).dot(direction)
        }
        guard let lower = parameters.min(),
              let upper = parameters.max() else {
            throw KernelError(
                phase: .geometry,
                code: .emptyResult,
                tolerance: tolerance,
                message: "Face projection bounds produced no line parameters."
            )
        }
        let scale = max(abs(lower), abs(upper), upper - lower, 1.0)
        let padding = max(
            tolerance.distance * 8.0,
            tolerance.relative * scale * 8.0,
            Double.ulpOfOne * scale * 4_096.0
        )
        return FaceDirectionalSearchDomain(
            curve: try ScalarInterval(
                lower: lower - padding,
                upper: upper + padding
            ),
            surface: parameterBounds
        )
    }

    private func closestRectangularBoundaryProjection(
        to point: Point3D,
        from supportParameter: SurfaceParameter,
        domain: ExactRectangularPcurveDomain,
        surface: Surface3D,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection {
        let sides = [
            RectangularBoundarySide(
                fixedDirection: .u,
                fixedValue: domain.uLower,
                variableLower: domain.vLower,
                variableUpper: domain.vUpper,
                initialVariable: supportParameter.v
            ),
            RectangularBoundarySide(
                fixedDirection: .u,
                fixedValue: domain.uUpper,
                variableLower: domain.vLower,
                variableUpper: domain.vUpper,
                initialVariable: supportParameter.v
            ),
            RectangularBoundarySide(
                fixedDirection: .v,
                fixedValue: domain.vLower,
                variableLower: domain.uLower,
                variableUpper: domain.uUpper,
                initialVariable: supportParameter.u
            ),
            RectangularBoundarySide(
                fixedDirection: .v,
                fixedValue: domain.vUpper,
                variableLower: domain.uLower,
                variableUpper: domain.uUpper,
                initialVariable: supportParameter.u
            ),
        ]
        var best: FaceTrimBoundaryProjection?
        for side in sides {
            let candidate = try closestProjection(
                to: point,
                on: side,
                surface: surface,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
            if let current = best {
                if candidate.residual < current.residual
                    || candidate.residual == current.residual
                        && boundaryOrder(candidate, current) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult(
                "Rectangular face boundary projection produced no candidate."
            )
        }
        return best
    }

    private func closestProjection(
        to point: Point3D,
        on side: RectangularBoundarySide,
        surface: Surface3D,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection {
        let fullInterval = try ScalarInterval(
            lower: side.variableLower,
            upper: side.variableUpper
        )
        var best: FaceTrimBoundaryProjection?
        let initialVariables = [
            side.clamped(side.initialVariable),
            fullInterval.lower,
            fullInterval.midpoint,
            fullInterval.upper,
        ]
        for initial in initialVariables {
            let candidate = try refinedProjection(
                to: point,
                on: side,
                surface: surface,
                initialVariable: initial,
                variableInterval: fullInterval,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
            best = preferredProjection(candidate, over: best)
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult(
                "Rectangular boundary projection produced no initial candidate."
            )
        }

        let maximumSubdivisionDepth = 48
        var remainingCells = 1_048_576
        var certifiedBest = best
        var stack = [BoundaryProjectionCell(
            variableInterval: fullInterval,
            depth: 0
        )]
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rectangular boundary projection exceeded its subdivision cell budget."
                )
            }
            remainingCells -= 1

            let enclosure = try boundaryPositionEnclosure(
                on: side,
                over: cell.variableInterval,
                surface: surface,
                tolerance: tolerance
            )
            let lowerBound = distanceLowerBound(
                from: point,
                to: enclosure
            )
            if lowerBound + tolerance.distance >= certifiedBest.residual {
                continue
            }

            let candidate = try refinedProjection(
                to: point,
                on: side,
                surface: surface,
                initialVariable: cell.variableInterval.midpoint,
                variableInterval: cell.variableInterval,
                maximumIterations: maximumIterations,
                tolerance: tolerance
            )
            certifiedBest = preferredProjection(candidate, over: certifiedBest)
            if lowerBound + tolerance.distance >= certifiedBest.residual {
                continue
            }

            let midpoint = cell.variableInterval.midpoint
            guard cell.depth < maximumSubdivisionDepth,
                  midpoint > cell.variableInterval.lower,
                  midpoint < cell.variableInterval.upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rectangular boundary projection could not close its global distance bound."
                )
            }
            stack.append(BoundaryProjectionCell(
                variableInterval: try ScalarInterval(
                    lower: midpoint,
                    upper: cell.variableInterval.upper
                ),
                depth: cell.depth + 1
            ))
            stack.append(BoundaryProjectionCell(
                variableInterval: try ScalarInterval(
                    lower: cell.variableInterval.lower,
                    upper: midpoint
                ),
                depth: cell.depth + 1
            ))
        }
        return certifiedBest
    }

    private func refinedProjection(
        to point: Point3D,
        on side: RectangularBoundarySide,
        surface: Surface3D,
        initialVariable: Double,
        variableInterval: ScalarInterval,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection {
        var variable = min(
            max(initialVariable, variableInterval.lower),
            variableInterval.upper
        )
        var completedIterations = 0
        for iteration in 0..<maximumIterations {
            completedIterations = iteration + 1
            let parameter = side.parameter(variable: variable)
            let geometry = try surface.differentialGeometry(
                atU: parameter.u,
                v: parameter.v,
                tolerance: tolerance
            )
            let derivative: Vector3D
            let secondDerivative: Vector3D
            switch side.fixedDirection {
            case .u:
                derivative = geometry.tangentV
                secondDerivative = geometry.secondDerivativeVV
            case .v:
                derivative = geometry.tangentU
                secondDerivative = geometry.secondDerivativeUU
            }
            let residual = geometry.position - point
            let gradient = residual.dot(derivative)
            let hessian = derivative.dot(derivative)
                + residual.dot(secondDerivative)
            let scale = max(
                1.0,
                derivative.dot(derivative),
                abs(residual.dot(secondDerivative))
            )
            guard hessian.isFinite,
                  abs(hessian) > Double.ulpOfOne * scale else {
                break
            }
            let next = min(
                max(variable - gradient / hessian, variableInterval.lower),
                variableInterval.upper
            )
            guard next.isFinite else {
                throw GeometryError.invalidDistance(next)
            }
            if abs(next - variable) <= max(
                tolerance.relative * max(abs(variable), 1.0),
                Double.ulpOfOne * max(abs(variable), 1.0) * 128.0
            ) {
                variable = next
                break
            }
            let nextParameter = side.parameter(variable: next)
            let nextPoint = try surface.point(
                u: nextParameter.u,
                v: nextParameter.v,
                tolerance: tolerance
            )
            if (nextPoint - point).length <= residual.length {
                variable = next
            } else {
                break
            }
        }
        let parameter = side.parameter(variable: variable)
        let projectedPoint = try surface.point(
            u: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        )
        return FaceTrimBoundaryProjection(
            parameter: parameter,
            point: projectedPoint,
            residual: distanceUpperBound(from: point, to: projectedPoint),
            iterations: completedIterations
        )
    }

    private func boundaryPositionEnclosure(
        on side: RectangularBoundarySide,
        over variableInterval: ScalarInterval,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        let fixedInterval = try enclosingInterval(
            side.fixedValue,
            in: side.fixedDirection == .u ? surface.uDomain : surface.vDomain,
            tolerance: tolerance
        )
        let parameters: SurfaceParameterBox
        switch side.fixedDirection {
        case .u:
            parameters = SurfaceParameterBox(
                u: fixedInterval,
                v: variableInterval
            )
        case .v:
            parameters = SurfaceParameterBox(
                u: variableInterval,
                v: fixedInterval
            )
        }
        return try surfaceDifferentialEncloser.enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        ).position
    }

    private func enclosingInterval(
        _ value: Double,
        in domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rectangular boundary parameter must be finite."
            )
        }
        var lower = value.nextDown
        var upper = value.nextUp
        if case let .closed(domainLower, domainUpper) = domain {
            lower = max(lower, domainLower)
            upper = min(upper, domainUpper)
        }
        guard lower < upper else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rectangular boundary parameter has no enclosing surface interval."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func distanceLowerBound(
        from point: Point3D,
        to enclosure: CoordinateEnclosure3D
    ) -> Double {
        let x = axisDistanceLowerBound(
            point.x,
            interval: enclosure.x
        )
        let y = axisDistanceLowerBound(
            point.y,
            interval: enclosure.y
        )
        let z = axisDistanceLowerBound(
            point.z,
            interval: enclosure.z
        )
        let xSquared = max(0.0, (x * x).nextDown)
        let ySquared = max(0.0, (y * y).nextDown)
        let zSquared = max(0.0, (z * z).nextDown)
        let xy = max(0.0, (xSquared + ySquared).nextDown)
        let squared = max(0.0, (xy + zSquared).nextDown)
        return max(0.0, sqrt(squared).nextDown)
    }

    private func axisDistanceLowerBound(
        _ value: Double,
        interval: ScalarInterval
    ) -> Double {
        if value < interval.lower {
            return max(0.0, (interval.lower - value).nextDown)
        }
        if value > interval.upper {
            return max(0.0, (value - interval.upper).nextDown)
        }
        return 0.0
    }

    private func distanceUpperBound(
        from point: Point3D,
        to projectedPoint: Point3D
    ) -> Double {
        let x = abs(projectedPoint.x - point.x).nextUp
        let y = abs(projectedPoint.y - point.y).nextUp
        let z = abs(projectedPoint.z - point.z).nextUp
        let xSquared = (x * x).nextUp
        let ySquared = (y * y).nextUp
        let zSquared = (z * z).nextUp
        let xy = (xSquared + ySquared).nextUp
        return sqrt((xy + zSquared).nextUp).nextUp
    }

    private func preferredProjection(
        _ candidate: FaceTrimBoundaryProjection,
        over current: FaceTrimBoundaryProjection?
    ) -> FaceTrimBoundaryProjection {
        guard let current else {
            return candidate
        }
        if candidate.residual < current.residual
            || candidate.residual == current.residual
                && boundaryOrder(candidate, current) {
            return candidate
        }
        return current
    }

    private func closestGeneralBoundaryProjection(
        to point: Point3D,
        face: Face,
        surface: Surface3D,
        model: BRepModel,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> FaceTrimBoundaryProjection {
        var best: FaceTrimBoundaryProjection?
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw FeatureEvaluationError.missingInput(
                    "Surface closest-point query references a missing trim loop."
                )
            }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      let pcurve = coedge.surfaceParameterCurve,
                      let trim = edge.trim else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Surface closest-point query requires exact trimmed curves and pcurves."
                    )
                }
                let interval = try ScalarInterval(
                    lower: min(trim.startParameter, trim.endParameter),
                    upper: max(trim.startParameter, trim.endParameter)
                )
                let projection = try curve.closestParameterProjection(
                    of: point,
                    options: CurveParameterProjectionOptions(
                        parameterRange: interval,
                        maximumIterations: maximumIterations,
                        seedCount: 64,
                        maximumSubdivisionDepth: 32,
                        maximumSubdivisionCells: 1_048_576,
                        maximumCandidateCount: 4_096
                    ),
                    tolerance: tolerance
                )
                let canonicalFraction = (
                    projection.parameter - trim.startParameter
                ) / (trim.endParameter - trim.startParameter)
                let orientedFraction = coedge.orientation == .forward
                    ? canonicalFraction
                    : 1.0 - canonicalFraction
                let parameter = try pcurve.parameter(
                    atNormalizedFraction: min(max(orientedFraction, 0.0), 1.0),
                    tolerance: tolerance
                )
                let surfacePoint = try surface.point(
                    u: parameter.u,
                    v: parameter.v,
                    tolerance: tolerance
                )
                guard surfacePoint.isApproximatelyEqual(
                    to: projection.point,
                    tolerance: tolerance.distance * 8.0
                ) else {
                    throw FeatureEvaluationError.invalidGraph(
                        "A face trim pcurve does not match its exact 3D boundary curve."
                    )
                }
                let candidate = FaceTrimBoundaryProjection(
                    parameter: parameter,
                    point: surfacePoint,
                    residual: (surfacePoint - point).length,
                    iterations: projection.iterations
                )
                if let current = best {
                    if candidate.residual < current.residual
                        || candidate.residual == current.residual
                            && boundaryOrder(candidate, current) {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult(
                "Surface closest-point query found no trim boundary."
            )
        }
        return best
    }

    private func boundaryOrder(
        _ lhs: FaceTrimBoundaryProjection,
        _ rhs: FaceTrimBoundaryProjection
    ) -> Bool {
        if lhs.parameter.u != rhs.parameter.u {
            return lhs.parameter.u < rhs.parameter.u
        }
        return lhs.parameter.v < rhs.parameter.v
    }

    private func corners(of box: BoundingBox3D) -> [Point3D] {
        [
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
        ]
    }
}

private struct RectangularBoundarySide: Sendable {
    enum FixedDirection: Equatable, Sendable {
        case u
        case v
    }

    let fixedDirection: FixedDirection
    let fixedValue: Double
    let variableLower: Double
    let variableUpper: Double
    let initialVariable: Double

    func clamped(_ value: Double) -> Double {
        min(max(value, variableLower), variableUpper)
    }

    func parameter(variable: Double) -> SurfaceParameter {
        switch fixedDirection {
        case .u:
            return SurfaceParameter(u: fixedValue, v: variable)
        case .v:
            return SurfaceParameter(u: variable, v: fixedValue)
        }
    }
}

private struct BoundaryProjectionCell: Sendable {
    let variableInterval: ScalarInterval
    let depth: Int
}
