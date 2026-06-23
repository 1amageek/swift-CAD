import Foundation
import CADCore
import CADIR

public struct ResolvedSurface: Sendable, Hashable {
    public var reference: SurfaceReference
    public var faceID: FaceID
    public var surfaceID: SurfaceID
    public var surface: Surface3D

    public init(
        reference: SurfaceReference,
        faceID: FaceID,
        surfaceID: SurfaceID,
        surface: Surface3D
    ) {
        self.reference = reference
        self.faceID = faceID
        self.surfaceID = surfaceID
        self.surface = surface
    }
}

public struct SurfaceQueryFrame: Sendable, Hashable {
    public var reference: SurfaceParameterReference
    public var point: Point3D
    public var tangentU: Vector3D
    public var tangentV: Vector3D
    public var normal: Vector3D
    public var normalCurvatureU: Double
    public var normalCurvatureV: Double
    public var meanCurvature: Double
    public var gaussianCurvature: Double
    public var minimumPrincipalCurvature: Double
    public var maximumPrincipalCurvature: Double
    public var minimumPrincipalDirection: Vector3D
    public var maximumPrincipalDirection: Vector3D

    public init(
        reference: SurfaceParameterReference,
        geometry: Surface3D.DifferentialGeometry
    ) {
        self.reference = reference
        self.point = geometry.position
        self.tangentU = geometry.tangentU
        self.tangentV = geometry.tangentV
        self.normal = geometry.normal
        self.normalCurvatureU = geometry.normalCurvatureU
        self.normalCurvatureV = geometry.normalCurvatureV
        self.meanCurvature = geometry.meanCurvature
        self.gaussianCurvature = geometry.gaussianCurvature
        self.minimumPrincipalCurvature = geometry.minimumPrincipalCurvature
        self.maximumPrincipalCurvature = geometry.maximumPrincipalCurvature
        self.minimumPrincipalDirection = geometry.minimumPrincipalDirection
        self.maximumPrincipalDirection = geometry.maximumPrincipalDirection
    }
}

public struct SurfaceSpanQueryResult: Sendable, Hashable {
    public var reference: SurfaceSpanReference
    public var lowerParameter: Double
    public var upperParameter: Double

    public init(reference: SurfaceSpanReference, lowerParameter: Double, upperParameter: Double) {
        self.reference = reference
        self.lowerParameter = lowerParameter
        self.upperParameter = upperParameter
    }
}

public struct SurfaceProjectionOptions: Sendable, Hashable {
    public var sampleCount: Int
    public var maximumIterations: Int

    public init(sampleCount: Int = 9, maximumIterations: Int = 32) {
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Surface projection sample count must be at least two.")
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface projection iteration count must not be negative.")
        }
    }
}

public struct SurfaceProjectionResult: Sendable, Hashable {
    public var sourcePoint: Point3D
    public var parameterReference: SurfaceParameterReference
    public var projectedPoint: Point3D
    public var residual: Vector3D
    public var distance: Double
    public var frame: SurfaceQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        frame: SurfaceQueryFrame,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.parameterReference = frame.reference
        self.projectedPoint = frame.point
        self.residual = sourcePoint - frame.point
        self.distance = self.residual.length
        self.frame = frame
        self.iterations = iterations
        self.converged = converged
    }
}

public enum SurfaceDirectionalProjectionRange: Sendable, Hashable {
    case line
    case ray

    fileprivate func accepts(_ signedDistance: Double, tolerance: ModelingTolerance) -> Bool {
        switch self {
        case .line:
            return true
        case .ray:
            return signedDistance >= -tolerance.distance
        }
    }
}

public struct SurfaceDirectionalProjectionOptions: Sendable, Hashable {
    public var sampleCount: Int
    public var maximumIterations: Int
    public var range: SurfaceDirectionalProjectionRange

    public init(
        sampleCount: Int = 9,
        maximumIterations: Int = 32,
        range: SurfaceDirectionalProjectionRange = .line
    ) {
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
        self.range = range
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Surface projection sample count must be at least two.")
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Surface projection iteration count must not be negative.")
        }
    }
}

public struct SurfaceDirectionalProjectionResult: Sendable, Hashable {
    public var sourcePoint: Point3D
    public var direction: Vector3D
    public var signedDistanceAlongDirection: Double
    public var linePoint: Point3D
    public var parameterReference: SurfaceParameterReference
    public var projectedPoint: Point3D
    public var lineResidual: Vector3D
    public var lineDistance: Double
    public var frame: SurfaceQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        frame: SurfaceQueryFrame,
        iterations: Int,
        converged: Bool
    ) {
        self.sourcePoint = sourcePoint
        self.direction = direction
        self.signedDistanceAlongDirection = signedDistanceAlongDirection
        self.linePoint = sourcePoint + direction * signedDistanceAlongDirection
        self.parameterReference = frame.reference
        self.projectedPoint = frame.point
        self.lineResidual = frame.point - self.linePoint
        self.lineDistance = self.lineResidual.length
        self.frame = frame
        self.iterations = iterations
        self.converged = converged
    }
}

public struct SurfaceQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func resolve(
        _ reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> ResolvedSurface {
        try reference.validate()
        guard let topologyReference = document.generatedNames[reference.faceName] else {
            throw FeatureEvaluationError.missingInput("Surface face name could not be resolved.")
        }
        guard case let .face(faceID) = topologyReference else {
            throw FeatureEvaluationError.unsupportedOperation("Surface query requires a face persistent name.")
        }
        guard let face = document.brep.faces[faceID] else {
            throw FeatureEvaluationError.missingInput("Surface query references a missing face.")
        }
        guard let surface = document.brep.geometry.surfaces[face.surfaceID] else {
            throw FeatureEvaluationError.missingInput("Surface query references a missing surface.")
        }
        try surface.validate(tolerance: tolerance)
        return ResolvedSurface(
            reference: reference,
            faceID: faceID,
            surfaceID: face.surfaceID,
            surface: surface
        )
    }

    public func frame(
        at reference: SurfaceParameterReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceQueryFrame {
        try reference.validate()
        let resolved = try resolve(reference.surface, in: document)
        guard try resolved.surface.uDomain.contains(reference.u, tolerance: tolerance),
              try resolved.surface.vDomain.contains(reference.v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let geometry = try resolved.surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        return SurfaceQueryFrame(reference: reference, geometry: geometry)
    }

    public func closestPoint(
        to point: Point3D,
        on reference: SurfaceReference,
        in document: EvaluatedDocument,
        options: SurfaceProjectionOptions = SurfaceProjectionOptions()
    ) throws -> SurfaceProjectionResult {
        try point.validate()
        try options.validate()
        let resolved = try resolve(reference, in: document)
        switch resolved.surface {
        case let .plane(plane):
            return try closestPointOnPlane(point, plane: plane, reference: reference)
        case let .cylinder(cylinder):
            return try closestPointOnCylinder(point, cylinder: cylinder, reference: reference)
        case let .bSpline(surface):
            return try closestPointOnBSpline(
                point,
                surface: surface,
                reference: reference,
                options: options
            )
        }
    }

    public func project(
        _ point: Point3D,
        along direction: Vector3D,
        onto reference: SurfaceReference,
        in document: EvaluatedDocument,
        options: SurfaceDirectionalProjectionOptions = SurfaceDirectionalProjectionOptions()
    ) throws -> SurfaceDirectionalProjectionResult {
        try point.validate()
        try options.validate()
        let unitDirection = try direction.normalized(tolerance: tolerance.distance)
        let resolved = try resolve(reference, in: document)
        switch resolved.surface {
        case let .plane(plane):
            return try projectOntoPlane(
                point,
                direction: unitDirection,
                plane: plane,
                reference: reference,
                range: options.range
            )
        case let .cylinder(cylinder):
            return try projectOntoCylinder(
                point,
                direction: unitDirection,
                cylinder: cylinder,
                reference: reference,
                range: options.range
            )
        case let .bSpline(surface):
            return try projectOntoBSpline(
                point,
                direction: unitDirection,
                surface: surface,
                reference: reference,
                options: options
            )
        }
    }

    public func controlPoint(
        _ reference: SurfaceControlPointReference,
        in document: EvaluatedDocument
    ) throws -> Point3D {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        guard reference.vIndex < surface.controlPoints.count else {
            throw FeatureEvaluationError.missingInput("Surface control point V index could not be resolved.")
        }
        guard reference.uIndex < surface.controlPoints[reference.vIndex].count else {
            throw FeatureEvaluationError.missingInput("Surface control point U index could not be resolved.")
        }
        return surface.controlPoints[reference.vIndex][reference.uIndex]
    }

    public func knot(
        _ reference: SurfaceKnotReference,
        in document: EvaluatedDocument
    ) throws -> Double {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        let knots = knotVector(for: reference.direction, surface: surface)
        guard reference.knotIndex < knots.count else {
            throw FeatureEvaluationError.missingInput("Surface knot index could not be resolved.")
        }
        return knots[reference.knotIndex]
    }

    public func span(
        _ reference: SurfaceSpanReference,
        in document: EvaluatedDocument
    ) throws -> SurfaceSpanQueryResult {
        try reference.validate()
        let surface = try exactBSpline(for: reference.surface, in: document)
        let knots = knotVector(for: reference.direction, surface: surface)
        let degree = degree(for: reference.direction, surface: surface)
        var ordinal = 0
        let lowerIndex = degree
        let upperIndex = knots.count - degree - 1
        guard lowerIndex < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Surface has no queryable knot spans.")
        }
        for index in lowerIndex..<upperIndex {
            let lower = knots[index]
            let upper = knots[index + 1]
            guard upper - lower > tolerance.distance else {
                continue
            }
            if ordinal == reference.spanIndex {
                return SurfaceSpanQueryResult(
                    reference: reference,
                    lowerParameter: lower,
                    upperParameter: upper
                )
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Surface span index could not be resolved.")
    }

    private func exactBSpline(
        for reference: SurfaceReference,
        in document: EvaluatedDocument
    ) throws -> BSplineSurface3D {
        let resolved = try resolve(reference, in: document)
        guard case let .bSpline(surface) = resolved.surface else {
            throw FeatureEvaluationError.unsupportedOperation("Surface query requires an exact B-spline surface.")
        }
        return surface
    }

    private func knotVector(
        for direction: SurfaceParameterDirection,
        surface: BSplineSurface3D
    ) -> [Double] {
        switch direction {
        case .u:
            return surface.uKnots
        case .v:
            return surface.vKnots
        }
    }

    private func degree(
        for direction: SurfaceParameterDirection,
        surface: BSplineSurface3D
    ) -> Int {
        switch direction {
        case .u:
            return surface.uDegree
        case .v:
            return surface.vDegree
        }
    }

    private func closestPointOnPlane(
        _ point: Point3D,
        plane: Plane3D,
        reference: SurfaceReference
    ) throws -> SurfaceProjectionResult {
        try plane.validate(tolerance: tolerance)
        let (basisU, basisV) = try planeBasis(for: plane.normal)
        let offset = point - plane.origin
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(
                surface: reference,
                u: offset.dot(basisU),
                v: offset.dot(basisV)
            ),
            surface: .plane(plane),
            iterations: 0,
            converged: true
        )
    }

    private func closestPointOnCylinder(
        _ point: Point3D,
        cylinder: Cylinder3D,
        reference: SurfaceReference
    ) throws -> SurfaceProjectionResult {
        try cylinder.validate(tolerance: tolerance)
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let (radialU, radialV) = try planeBasis(for: axis)
        let offset = point - cylinder.origin
        let height = offset.dot(axis)
        let radialOffset = offset - axis * height
        let angle: Double
        if radialOffset.length > tolerance.distance {
            let rawAngle = atan2(radialOffset.dot(radialV), radialOffset.dot(radialU))
            angle = rawAngle >= 0.0 ? rawAngle : rawAngle + Double.pi * 2.0
        } else {
            angle = 0.0
        }
        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(surface: reference, u: angle, v: height),
            surface: .cylinder(cylinder),
            iterations: 0,
            converged: true
        )
    }

    private func closestPointOnBSpline(
        _ point: Point3D,
        surface: BSplineSurface3D,
        reference: SurfaceReference,
        options: SurfaceProjectionOptions
    ) throws -> SurfaceProjectionResult {
        try surface.validate(tolerance: tolerance)
        let bounds = try SurfaceParameterBounds(
            u: parameterBounds(for: surface.uDomain),
            v: parameterBounds(for: surface.vDomain)
        )
        let uSamples = try parameterSamples(
            knots: surface.uKnots,
            degree: surface.uDegree,
            domain: surface.uDomain,
            fallbackCount: options.sampleCount
        )
        let vSamples = try parameterSamples(
            knots: surface.vKnots,
            degree: surface.vDegree,
            domain: surface.vDomain,
            fallbackCount: options.sampleCount
        )

        var candidates: [SurfaceProjectionCandidate] = []
        for u in uSamples {
            for v in vSamples {
                candidates.append(try projectionCandidate(
                    point,
                    surface: surface,
                    u: u,
                    v: v
                ))
            }
        }
        guard !candidates.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Surface projection has no parameter samples.")
        }

        candidates.sort { lhs, rhs in
            lhs.squaredDistance < rhs.squaredDistance
        }

        var best: SurfaceProjectionCandidate?
        let seedCount = min(6, candidates.count)
        for seed in candidates.prefix(seedCount) {
            let refined = try refineProjection(
                from: seed,
                point: point,
                surface: surface,
                bounds: bounds,
                maximumIterations: options.maximumIterations
            )
            if shouldReplaceProjectionCandidate(current: best, candidate: refined) {
                best = refined
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Surface projection refinement produced no candidate.")
        }

        return try projectionResult(
            sourcePoint: point,
            reference: SurfaceParameterReference(surface: reference, u: best.u, v: best.v),
            surface: .bSpline(surface),
            iterations: best.iterations,
            converged: best.converged
        )
    }

    private func projectOntoPlane(
        _ point: Point3D,
        direction: Vector3D,
        plane: Plane3D,
        reference: SurfaceReference,
        range: SurfaceDirectionalProjectionRange
    ) throws -> SurfaceDirectionalProjectionResult {
        try plane.validate(tolerance: tolerance)
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let denominator = direction.dot(normal)
        guard abs(denominator) > tolerance.angle else {
            throw FeatureEvaluationError.emptyResult("Projection direction is parallel to the plane.")
        }
        let signedDistance = (plane.origin - point).dot(normal) / denominator
        guard range.accepts(signedDistance, tolerance: tolerance) else {
            throw FeatureEvaluationError.emptyResult("Projection target is outside the requested direction range.")
        }
        let projectedPoint = point + direction * signedDistance
        let (basisU, basisV) = try planeBasis(for: normal)
        let offset = projectedPoint - plane.origin
        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: signedDistance,
            reference: SurfaceParameterReference(
                surface: reference,
                u: offset.dot(basisU),
                v: offset.dot(basisV)
            ),
            surface: .plane(plane),
            iterations: 0,
            converged: true
        )
    }

    private func projectOntoCylinder(
        _ point: Point3D,
        direction: Vector3D,
        cylinder: Cylinder3D,
        reference: SurfaceReference,
        range: SurfaceDirectionalProjectionRange
    ) throws -> SurfaceDirectionalProjectionResult {
        try cylinder.validate(tolerance: tolerance)
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let (radialU, radialV) = try planeBasis(for: axis)
        let offset = point - cylinder.origin
        let radialPoint = offset - axis * offset.dot(axis)
        let radialDirection = direction - axis * direction.dot(axis)
        let quadraticA = radialDirection.dot(radialDirection)
        guard quadraticA > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Projection direction does not intersect the cylinder radius.")
        }
        let quadraticB = 2.0 * radialPoint.dot(radialDirection)
        let quadraticC = radialPoint.dot(radialPoint) - cylinder.radius * cylinder.radius
        let discriminant = quadraticB * quadraticB - 4.0 * quadraticA * quadraticC
        guard discriminant >= -tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Projection line does not intersect the cylinder.")
        }

        let root = sqrt(max(discriminant, 0.0))
        let denominator = 2.0 * quadraticA
        let candidates = [
            (-quadraticB - root) / denominator,
            (-quadraticB + root) / denominator,
        ].filter { value in
            value.isFinite && range.accepts(value, tolerance: tolerance)
        }
        guard let signedDistance = bestSignedDistance(candidates, range: range) else {
            throw FeatureEvaluationError.emptyResult("Cylinder projection is outside the requested direction range.")
        }

        let projectedPoint = point + direction * signedDistance
        let projectedOffset = projectedPoint - cylinder.origin
        let height = projectedOffset.dot(axis)
        let projectedRadial = projectedOffset - axis * height
        let rawAngle = atan2(projectedRadial.dot(radialV), projectedRadial.dot(radialU))
        let angle = rawAngle >= 0.0 ? rawAngle : rawAngle + Double.pi * 2.0
        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: signedDistance,
            reference: SurfaceParameterReference(surface: reference, u: angle, v: height),
            surface: .cylinder(cylinder),
            iterations: 0,
            converged: true
        )
    }

    private func projectOntoBSpline(
        _ point: Point3D,
        direction: Vector3D,
        surface: BSplineSurface3D,
        reference: SurfaceReference,
        options: SurfaceDirectionalProjectionOptions
    ) throws -> SurfaceDirectionalProjectionResult {
        try surface.validate(tolerance: tolerance)
        let bounds = try SurfaceParameterBounds(
            u: parameterBounds(for: surface.uDomain),
            v: parameterBounds(for: surface.vDomain)
        )
        let uSamples = try parameterSamples(
            knots: surface.uKnots,
            degree: surface.uDegree,
            domain: surface.uDomain,
            fallbackCount: options.sampleCount
        )
        let vSamples = try parameterSamples(
            knots: surface.vKnots,
            degree: surface.vDegree,
            domain: surface.vDomain,
            fallbackCount: options.sampleCount
        )

        var candidates: [SurfaceDirectionalProjectionCandidate] = []
        for u in uSamples {
            for v in vSamples {
                if let candidate = try directionalProjectionCandidate(
                    point,
                    direction: direction,
                    surface: surface,
                    u: u,
                    v: v,
                    range: options.range
                ) {
                    candidates.append(candidate)
                }
            }
        }
        guard !candidates.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Surface directional projection has no parameter samples.")
        }

        candidates.sort { lhs, rhs in
            lhs.squaredLineDistance < rhs.squaredLineDistance
        }

        var best: SurfaceDirectionalProjectionCandidate?
        let seedCount = min(8, candidates.count)
        for seed in candidates.prefix(seedCount) {
            let refined = try refineDirectionalProjection(
                from: seed,
                point: point,
                direction: direction,
                surface: surface,
                bounds: bounds,
                range: options.range,
                maximumIterations: options.maximumIterations
            )
            if shouldReplaceDirectionalProjectionCandidate(current: best, candidate: refined) {
                best = refined
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Surface directional projection refinement produced no candidate.")
        }

        return try directionalProjectionResult(
            sourcePoint: point,
            direction: direction,
            signedDistanceAlongDirection: best.signedDistanceAlongDirection,
            reference: SurfaceParameterReference(surface: reference, u: best.u, v: best.v),
            surface: .bSpline(surface),
            iterations: best.iterations,
            converged: best.converged
        )
    }

    private func refineDirectionalProjection(
        from seed: SurfaceDirectionalProjectionCandidate,
        point: Point3D,
        direction: Vector3D,
        surface: BSplineSurface3D,
        bounds: SurfaceParameterBounds,
        range: SurfaceDirectionalProjectionRange,
        maximumIterations: Int
    ) throws -> SurfaceDirectionalProjectionCandidate {
        var current = seed
        guard maximumIterations > 0 else {
            return current
        }

        for iteration in 1...maximumIterations {
            let geometry = try surface.differentialGeometry(
                atU: current.u,
                v: current.v,
                tolerance: tolerance
            )
            let linePoint = point + direction * current.signedDistanceAlongDirection
            let residual = geometry.position - linePoint
            if residual.length <= tolerance.distance {
                current.iterations = iteration
                current.converged = true
                return current
            }

            let columnU = geometry.tangentU
            let columnV = geometry.tangentV
            let columnT = -direction
            let jacobianDeterminant = determinant(columnU, columnV, columnT)
            guard abs(jacobianDeterminant) > max(tolerance.distance * tolerance.distance, Double.ulpOfOne) else {
                return current
            }

            let rightHandSide = -residual
            let deltaU = determinant(rightHandSide, columnV, columnT) / jacobianDeterminant
            let deltaV = determinant(columnU, rightHandSide, columnT) / jacobianDeterminant
            let deltaT = determinant(columnU, columnV, rightHandSide) / jacobianDeterminant
            guard deltaU.isFinite, deltaV.isFinite, deltaT.isFinite else {
                throw GeometryError.invalidDistance(deltaU.isFinite ? (deltaV.isFinite ? deltaT : deltaV) : deltaU)
            }

            let stepLength = hypot(hypot(deltaU, deltaV), deltaT)
            if stepLength <= tolerance.distance {
                current.iterations = iteration
                current.converged = true
                return current
            }

            let previousSquaredDistance = current.squaredLineDistance
            var stepScale = 1.0
            var accepted: SurfaceDirectionalProjectionCandidate?
            while stepScale >= 1.0 / 128.0 {
                let nextU = bounds.clampedU(current.u + deltaU * stepScale)
                let nextV = bounds.clampedV(current.v + deltaV * stepScale)
                let nextSignedDistance = current.signedDistanceAlongDirection + deltaT * stepScale
                guard range.accepts(nextSignedDistance, tolerance: tolerance) else {
                    stepScale *= 0.5
                    continue
                }
                let next = try directionalProjectionCandidate(
                    point,
                    direction: direction,
                    surface: surface,
                    u: nextU,
                    v: nextV,
                    signedDistanceAlongDirection: nextSignedDistance,
                    range: range,
                    iterations: iteration
                )
                if next.squaredLineDistance <= previousSquaredDistance {
                    accepted = next
                    break
                }
                stepScale *= 0.5
            }

            guard var next = accepted else {
                current.iterations = iteration
                return current
            }

            let improvement = previousSquaredDistance - next.squaredLineDistance
            if next.lineDistance <= tolerance.distance ||
                improvement <= tolerance.distance * tolerance.distance {
                next.converged = next.lineDistance <= tolerance.distance
                return next
            }
            current = next
        }

        return current
    }

    private func shouldReplaceDirectionalProjectionCandidate(
        current: SurfaceDirectionalProjectionCandidate?,
        candidate: SurfaceDirectionalProjectionCandidate
    ) -> Bool {
        guard let current else {
            return true
        }
        let squaredDistanceTolerance = tolerance.distance * tolerance.distance
        if candidate.squaredLineDistance < current.squaredLineDistance - squaredDistanceTolerance {
            return true
        }
        if abs(candidate.squaredLineDistance - current.squaredLineDistance) <= squaredDistanceTolerance {
            if candidate.converged != current.converged {
                return candidate.converged
            }
            return abs(candidate.signedDistanceAlongDirection) < abs(current.signedDistanceAlongDirection)
        }
        return false
    }

    private func refineProjection(
        from seed: SurfaceProjectionCandidate,
        point: Point3D,
        surface: BSplineSurface3D,
        bounds: SurfaceParameterBounds,
        maximumIterations: Int
    ) throws -> SurfaceProjectionCandidate {
        var current = seed
        guard maximumIterations > 0 else {
            return current
        }

        for iteration in 1...maximumIterations {
            let geometry = try surface.differentialGeometry(
                atU: current.u,
                v: current.v,
                tolerance: tolerance
            )
            let residual = geometry.position - point
            let gradientU = residual.dot(geometry.tangentU)
            let gradientV = residual.dot(geometry.tangentV)
            let firstE = geometry.tangentU.dot(geometry.tangentU)
            let firstF = geometry.tangentU.dot(geometry.tangentV)
            let firstG = geometry.tangentV.dot(geometry.tangentV)
            let determinant = firstE * firstG - firstF * firstF
            let metricTolerance = tolerance.distance * tolerance.distance
            guard determinant > max(metricTolerance, Double.ulpOfOne) else {
                return current
            }

            let deltaU = (firstG * gradientU - firstF * gradientV) / determinant
            let deltaV = (-firstF * gradientU + firstE * gradientV) / determinant
            guard deltaU.isFinite, deltaV.isFinite else {
                throw GeometryError.invalidDistance(deltaU.isFinite ? deltaV : deltaU)
            }

            let stepLength = hypot(deltaU, deltaV)
            if stepLength <= tolerance.distance {
                current.iterations = iteration
                current.converged = true
                return current
            }

            let previousSquaredDistance = current.squaredDistance
            var stepScale = 1.0
            var accepted: SurfaceProjectionCandidate?
            while stepScale >= 1.0 / 128.0 {
                let nextU = bounds.clampedU(current.u - deltaU * stepScale)
                let nextV = bounds.clampedV(current.v - deltaV * stepScale)
                if abs(nextU - current.u) <= Double.ulpOfOne,
                   abs(nextV - current.v) <= Double.ulpOfOne {
                    stepScale *= 0.5
                    continue
                }
                let next = try projectionCandidate(
                    point,
                    surface: surface,
                    u: nextU,
                    v: nextV,
                    iterations: iteration
                )
                if next.squaredDistance <= previousSquaredDistance {
                    accepted = next
                    break
                }
                stepScale *= 0.5
            }

            guard var next = accepted else {
                current.iterations = iteration
                return current
            }

            let improvement = previousSquaredDistance - next.squaredDistance
            if improvement <= tolerance.distance * tolerance.distance {
                next.converged = true
                return next
            }
            current = next
        }

        return current
    }

    private func shouldReplaceProjectionCandidate(
        current: SurfaceProjectionCandidate?,
        candidate: SurfaceProjectionCandidate
    ) -> Bool {
        guard let current else {
            return true
        }
        let squaredDistanceTolerance = tolerance.distance * tolerance.distance
        if candidate.squaredDistance < current.squaredDistance - squaredDistanceTolerance {
            return true
        }
        if abs(candidate.squaredDistance - current.squaredDistance) <= squaredDistanceTolerance {
            return candidate.converged && !current.converged
        }
        return false
    }

    private func projectionResult(
        sourcePoint: Point3D,
        reference: SurfaceParameterReference,
        surface: Surface3D,
        iterations: Int,
        converged: Bool
    ) throws -> SurfaceProjectionResult {
        let geometry = try surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        let frame = SurfaceQueryFrame(reference: reference, geometry: geometry)
        return SurfaceProjectionResult(
            sourcePoint: sourcePoint,
            frame: frame,
            iterations: iterations,
            converged: converged
        )
    }

    private func directionalProjectionResult(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        reference: SurfaceParameterReference,
        surface: Surface3D,
        iterations: Int,
        converged: Bool
    ) throws -> SurfaceDirectionalProjectionResult {
        let geometry = try surface.differentialGeometry(
            atU: reference.u,
            v: reference.v,
            tolerance: tolerance
        )
        let frame = SurfaceQueryFrame(reference: reference, geometry: geometry)
        return SurfaceDirectionalProjectionResult(
            sourcePoint: sourcePoint,
            direction: direction,
            signedDistanceAlongDirection: signedDistanceAlongDirection,
            frame: frame,
            iterations: iterations,
            converged: converged
        )
    }

    private func projectionCandidate(
        _ point: Point3D,
        surface: BSplineSurface3D,
        u: Double,
        v: Double,
        iterations: Int = 0
    ) throws -> SurfaceProjectionCandidate {
        let projectedPoint = try surface.point(u: u, v: v, tolerance: tolerance)
        let residual = projectedPoint - point
        let squaredDistance = residual.dot(residual)
        guard squaredDistance.isFinite else {
            throw GeometryError.invalidDistance(squaredDistance)
        }
        return SurfaceProjectionCandidate(
            u: u,
            v: v,
            squaredDistance: squaredDistance,
            iterations: iterations,
            converged: false
        )
    }

    private func directionalProjectionCandidate(
        _ point: Point3D,
        direction: Vector3D,
        surface: BSplineSurface3D,
        u: Double,
        v: Double,
        range: SurfaceDirectionalProjectionRange
    ) throws -> SurfaceDirectionalProjectionCandidate? {
        let projectedPoint = try surface.point(u: u, v: v, tolerance: tolerance)
        let signedDistance = (projectedPoint - point).dot(direction)
        guard range.accepts(signedDistance, tolerance: tolerance) else {
            return nil
        }
        return try directionalProjectionCandidate(
            point,
            direction: direction,
            surface: surface,
            u: u,
            v: v,
            signedDistanceAlongDirection: signedDistance,
            range: range
        )
    }

    private func directionalProjectionCandidate(
        _ point: Point3D,
        direction: Vector3D,
        surface: BSplineSurface3D,
        u: Double,
        v: Double,
        signedDistanceAlongDirection: Double,
        range: SurfaceDirectionalProjectionRange,
        iterations: Int = 0
    ) throws -> SurfaceDirectionalProjectionCandidate {
        guard range.accepts(signedDistanceAlongDirection, tolerance: tolerance) else {
            throw FeatureEvaluationError.emptyResult("Surface directional projection candidate is outside the requested range.")
        }
        let projectedPoint = try surface.point(u: u, v: v, tolerance: tolerance)
        let linePoint = point + direction * signedDistanceAlongDirection
        let lineResidual = projectedPoint - linePoint
        let squaredLineDistance = lineResidual.dot(lineResidual)
        guard squaredLineDistance.isFinite else {
            throw GeometryError.invalidDistance(squaredLineDistance)
        }
        return SurfaceDirectionalProjectionCandidate(
            u: u,
            v: v,
            signedDistanceAlongDirection: signedDistanceAlongDirection,
            squaredLineDistance: squaredLineDistance,
            lineDistance: sqrt(squaredLineDistance),
            iterations: iterations,
            converged: false
        )
    }

    private func parameterSamples(
        knots: [Double],
        degree: Int,
        domain: ParameterDomain,
        fallbackCount: Int
    ) throws -> [Double] {
        let bounds = try parameterBounds(for: domain)
        var samples: [Double] = []
        appendUnique(bounds.lower, to: &samples)
        appendUnique(bounds.upper, to: &samples)

        if knots.count > degree + 1 {
            let lowerIndex = degree
            let upperIndex = knots.count - degree - 1
            if lowerIndex < upperIndex {
                for index in lowerIndex...upperIndex {
                    appendUnique(clamped(knots[index], lower: bounds.lower, upper: bounds.upper), to: &samples)
                    if index < upperIndex {
                        let lower = knots[index]
                        let upper = knots[index + 1]
                        if upper - lower > tolerance.distance {
                            appendUnique(
                                clamped((lower + upper) * 0.5, lower: bounds.lower, upper: bounds.upper),
                                to: &samples
                            )
                        }
                    }
                }
            }
        }

        if fallbackCount > 1 {
            for index in 0..<fallbackCount {
                let ratio = Double(index) / Double(fallbackCount - 1)
                appendUnique(bounds.lower + (bounds.upper - bounds.lower) * ratio, to: &samples)
            }
        }

        samples.sort()
        return samples
    }

    private func appendUnique(_ value: Double, to samples: inout [Double]) {
        guard value.isFinite else {
            return
        }
        if samples.contains(where: { abs($0 - value) <= tolerance.distance }) {
            return
        }
        samples.append(value)
    }

    private func parameterBounds(for domain: ParameterDomain) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case .unbounded, .periodic:
            throw FeatureEvaluationError.unsupportedOperation("Surface projection requires bounded B-spline parameters.")
        }
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func bestSignedDistance(
        _ candidates: [Double],
        range: SurfaceDirectionalProjectionRange
    ) -> Double? {
        switch range {
        case .line:
            return candidates.min { lhs, rhs in
                abs(lhs) < abs(rhs)
            }
        case .ray:
            return candidates.min()
        }
    }

    private func planeBasis(for normal: Vector3D) throws -> (Vector3D, Vector3D) {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalizedNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalizedNormal).normalized(tolerance: tolerance.distance)
        let v = normalizedNormal.cross(u)
        return (u, v)
    }

    private func determinant(
        _ first: Vector3D,
        _ second: Vector3D,
        _ third: Vector3D
    ) -> Double {
        first.dot(second.cross(third))
    }
}

private struct SurfaceProjectionCandidate: Sendable, Hashable {
    var u: Double
    var v: Double
    var squaredDistance: Double
    var iterations: Int
    var converged: Bool
}

private struct SurfaceDirectionalProjectionCandidate: Sendable, Hashable {
    var u: Double
    var v: Double
    var signedDistanceAlongDirection: Double
    var squaredLineDistance: Double
    var lineDistance: Double
    var iterations: Int
    var converged: Bool
}

private struct SurfaceParameterBounds: Sendable, Hashable {
    var uLower: Double
    var uUpper: Double
    var vLower: Double
    var vUpper: Double

    init(
        u: (lower: Double, upper: Double),
        v: (lower: Double, upper: Double)
    ) throws {
        guard u.lower.isFinite,
              u.upper.isFinite,
              v.lower.isFinite,
              v.upper.isFinite,
              u.upper >= u.lower,
              v.upper >= v.lower else {
            throw GeometryError.invalidDistance(0.0)
        }
        self.uLower = u.lower
        self.uUpper = u.upper
        self.vLower = v.lower
        self.vUpper = v.upper
    }

    func clampedU(_ value: Double) -> Double {
        min(max(value, uLower), uUpper)
    }

    func clampedV(_ value: Double) -> Double {
        min(max(value, vLower), vUpper)
    }
}
