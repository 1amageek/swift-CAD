import Foundation
import CADCore
import CADIR
import CADModeling

public struct CurveQueryPoint: Codable, Sendable, Hashable {
    public var reference: CurveParameterReference
    public var point: Point3D
    public var tangent: Vector3D?
    public var curvature: Double?
    public var isExact: Bool

    public init(
        reference: CurveParameterReference,
        point: Point3D,
        tangent: Vector3D?,
        curvature: Double?,
        isExact: Bool
    ) {
        self.reference = reference
        self.point = point
        self.tangent = tangent
        self.curvature = curvature
        self.isExact = isExact
    }
}

public struct CurveEndpointQueryResult: Codable, Sendable, Hashable {
    public var curve: CurveOutputReference
    public var start: Point3D
    public var end: Point3D

    public init(curve: CurveOutputReference, start: Point3D, end: Point3D) {
        self.curve = curve
        self.start = start
        self.end = end
    }
}

public struct CurveSpanQueryResult: Codable, Sendable, Hashable {
    public var reference: CurveSpanReference
    public var lowerParameter: Double
    public var upperParameter: Double

    public init(reference: CurveSpanReference, lowerParameter: Double, upperParameter: Double) {
        self.reference = reference
        self.lowerParameter = lowerParameter
        self.upperParameter = upperParameter
    }
}

public struct CurveQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func resolve(
        _ reference: CurveOutputReference,
        in document: EvaluatedDocument
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = document.curves[reference.featureID] else {
            throw FeatureEvaluationError.missingInput("Curve output feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw FeatureEvaluationError.missingInput("Curve output index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: tolerance)
        return curve
    }

    public func endpoints(
        of reference: CurveOutputReference,
        in document: EvaluatedDocument
    ) throws -> CurveEndpointQueryResult {
        let curve = try resolve(reference, in: document)
        guard let start = curve.points.first,
              let end = curve.points.last else {
            throw FeatureEvaluationError.emptyResult("Curve output contains no evaluated endpoints.")
        }
        return CurveEndpointQueryResult(curve: reference, start: start, end: end)
    }

    public func midpoint(
        of reference: CurveOutputReference,
        in document: EvaluatedDocument
    ) throws -> CurveQueryPoint {
        let curve = try resolve(reference, in: document)
        if case .unbounded = curve.parameterDomain {
            return try polylinePoint(
                at: CurveParameterReference(curve: reference, parameter: 0.5),
                curve: curve
            )
        }
        let parameter = midpointParameter(for: curve)
        return try point(at: CurveParameterReference(curve: reference, parameter: parameter), in: document)
    }

    public func point(
        at reference: CurveParameterReference,
        in document: EvaluatedDocument
    ) throws -> CurveQueryPoint {
        try reference.validate()
        let curve = try resolve(reference.curve, in: document)
        guard try curve.parameterDomain.contains(reference.parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(reference.parameter)
        }
        if let exactCurve = curve.exactCurve {
            let geometry = try exactCurve.differentialGeometry(
                at: reference.parameter,
                tolerance: tolerance
            )
            return CurveQueryPoint(
                reference: reference,
                point: geometry.position,
                tangent: geometry.tangent,
                curvature: geometry.curvature,
                isExact: true
            )
        }
        return try polylinePoint(at: reference, curve: curve)
    }

    public func closestPoint(
        to point: Point3D,
        on reference: CurveOutputReference,
        in document: EvaluatedDocument,
        options: CurveProjectionOptions = CurveProjectionOptions()
    ) throws -> CurveProjectionResult {
        try point.validate()
        try options.validate()
        let curve = try resolve(reference, in: document)
        let candidate: CurveProjectionCandidate
        if let exactCurve = curve.exactCurve {
            switch exactCurve {
            case let .line(line):
                let parameter = try closestLineParameter(to: point, on: line, domain: curve.parameterDomain)
                candidate = try projectionCandidate(point, curve: exactCurve, parameter: parameter)
                    .withConvergence(true)
            case let .analytic(.line(origin, direction)):
                let parameter = try closestLineParameter(
                    to: point,
                    on: Line3D(origin: origin, direction: direction),
                    domain: curve.parameterDomain
                )
                candidate = try projectionCandidate(point, curve: exactCurve, parameter: parameter)
                    .withConvergence(true)
            case .circle, .analytic, .bSpline, .implicit, .surfaceLift:
                candidate = try closestPointOnCurve(
                    point,
                    curve: exactCurve,
                    range: parameterRange(for: curve),
                    options: options
                )
            }
        } else {
            candidate = try closestPointOnPolyline(point, points: curve.points)
                .withConvergence(true)
        }
        let queryPoint = try self.point(
            at: CurveParameterReference(curve: reference, parameter: candidate.parameter),
            in: document
        )
        return CurveProjectionResult(
            sourcePoint: point,
            queryPoint: queryPoint,
            iterations: candidate.iterations,
            converged: candidate.converged
        )
    }

    public func project(
        _ point: Point3D,
        along direction: Vector3D,
        onto reference: CurveOutputReference,
        in document: EvaluatedDocument,
        options: CurveDirectionalProjectionOptions = CurveDirectionalProjectionOptions()
    ) throws -> CurveDirectionalProjectionResult {
        try point.validate()
        try options.validate()
        let unitDirection = try direction.normalized(tolerance: tolerance.distance)
        let curve = try resolve(reference, in: document)
        let candidate: CurveDirectionalProjectionCandidate
        if let exactCurve = curve.exactCurve {
            switch exactCurve {
            case let .line(line):
                candidate = try projectOntoLine(
                    point,
                    direction: unitDirection,
                    line: line,
                    domain: curve.parameterDomain,
                    range: options.range
                )
            case let .analytic(.line(origin, direction)):
                candidate = try projectOntoLine(
                    point,
                    direction: unitDirection,
                    line: Line3D(origin: origin, direction: direction),
                    domain: curve.parameterDomain,
                    range: options.range
                )
            case .circle, .analytic, .bSpline, .implicit, .surfaceLift:
                candidate = try projectOntoCurve(
                    point,
                    direction: unitDirection,
                    curve: exactCurve,
                    range: parameterRange(for: curve),
                    options: options
                )
            }
        } else {
            candidate = try projectOntoPolyline(
                point,
                direction: unitDirection,
                points: curve.points,
                range: options.range
            )
        }
        let queryPoint = try self.point(
            at: CurveParameterReference(curve: reference, parameter: candidate.parameter),
            in: document
        )
        return CurveDirectionalProjectionResult(
            sourcePoint: point,
            direction: unitDirection,
            signedDistanceAlongDirection: candidate.signedDistanceAlongDirection,
            queryPoint: queryPoint,
            iterations: candidate.iterations,
            converged: candidate.converged
        )
    }

    public func controlPoint(
        _ reference: CurveControlPointReference,
        in document: EvaluatedDocument
    ) throws -> Point3D {
        try reference.validate()
        let curve = try exactBSpline(for: reference.curve, in: document)
        guard reference.controlPointIndex < curve.controlPoints.count else {
            throw FeatureEvaluationError.missingInput("Curve control point index could not be resolved.")
        }
        return curve.controlPoints[reference.controlPointIndex]
    }

    public func center(
        _ reference: CurveCenterReference,
        in document: EvaluatedDocument
    ) throws -> Point3D {
        try reference.validate()
        let curve = try resolve(reference.curve, in: document)
        guard case .circle(let circle) = curve.exactCurve else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Curve center selection requires an exact circular curve."
            )
        }
        return circle.center
    }

    public func knot(
        _ reference: CurveKnotReference,
        in document: EvaluatedDocument
    ) throws -> Double {
        try reference.validate()
        let curve = try exactBSpline(for: reference.curve, in: document)
        guard reference.knotIndex < curve.knots.count else {
            throw FeatureEvaluationError.missingInput("Curve knot index could not be resolved.")
        }
        return curve.knots[reference.knotIndex]
    }

    public func span(
        _ reference: CurveSpanReference,
        in document: EvaluatedDocument
    ) throws -> CurveSpanQueryResult {
        try reference.validate()
        let curve = try exactBSpline(for: reference.curve, in: document)
        var ordinal = 0
        let lowerIndex = curve.degree
        let upperIndex = curve.knots.count - curve.degree - 1
        guard lowerIndex < upperIndex else {
            throw FeatureEvaluationError.emptyResult("Curve has no queryable knot spans.")
        }
        for index in lowerIndex..<upperIndex {
            let lower = curve.knots[index]
            let upper = curve.knots[index + 1]
            guard upper - lower > tolerance.distance else {
                continue
            }
            if ordinal == reference.spanIndex {
                return CurveSpanQueryResult(
                    reference: reference,
                    lowerParameter: lower,
                    upperParameter: upper
                )
            }
            ordinal += 1
        }
        throw FeatureEvaluationError.missingInput("Curve span index could not be resolved.")
    }

    private func midpointParameter(for curve: EvaluatedCurve) -> Double {
        switch curve.parameterDomain {
        case let .closed(lowerBound, upperBound):
            return (lowerBound + upperBound) * 0.5
        case let .periodic(period):
            return period * 0.5
        case .unbounded:
            return 0.5
        }
    }

    private func exactBSpline(
        for reference: CurveOutputReference,
        in document: EvaluatedDocument
    ) throws -> BSplineCurve3D {
        let evaluatedCurve = try resolve(reference, in: document)
        guard case let .bSpline(curve) = evaluatedCurve.exactCurve else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Curve query requires an exact B-spline curve.")
        }
        return curve
    }

    private func closestPointOnCurve(
        _ point: Point3D,
        curve: Curve3D,
        range: CurveParameterRange,
        options: CurveProjectionOptions
    ) throws -> CurveProjectionCandidate {
        let candidates = try sampleParameters(curve: curve, range: range, sampleCount: options.sampleCount)
            .map { try projectionCandidate(point, curve: curve, parameter: $0) }
            .sorted { $0.squaredDistance < $1.squaredDistance }
        guard !candidates.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Curve projection has no parameter samples.")
        }
        var best: CurveProjectionCandidate?
        for seed in candidates.prefix(min(6, candidates.count)) {
            let refined = try refineClosestProjection(
                from: seed,
                point: point,
                curve: curve,
                range: range,
                maximumIterations: options.maximumIterations
            )
            if shouldReplaceProjectionCandidate(current: best, candidate: refined) {
                best = refined
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Curve projection refinement produced no candidate.")
        }
        return best
    }

    private func refineClosestProjection(
        from seed: CurveProjectionCandidate,
        point: Point3D,
        curve: Curve3D,
        range: CurveParameterRange,
        maximumIterations: Int
    ) throws -> CurveProjectionCandidate {
        var current = seed
        guard maximumIterations > 0 else {
            return current
        }
        let parameterTolerance = self.parameterTolerance(for: curve)
        for iteration in 1...maximumIterations {
            let geometry = try curve.differentialGeometry(at: current.parameter, tolerance: tolerance)
            let residual = geometry.position - point
            let gradient = residual.dot(geometry.firstDerivative)
            let hessian = geometry.firstDerivative.dot(geometry.firstDerivative) +
                residual.dot(geometry.secondDerivative)
            guard abs(hessian) > max(tolerance.distance * tolerance.distance, Double.ulpOfOne) else {
                return current
            }
            let delta = gradient / hessian
            guard delta.isFinite else {
                throw GeometryError.invalidDistance(delta)
            }
            if abs(delta) <= parameterTolerance {
                current.iterations = iteration
                current.converged = true
                return current
            }
            var stepScale = 1.0
            var accepted: CurveProjectionCandidate?
            while stepScale >= 1.0 / 128.0 {
                let nextParameter = range.clamped(current.parameter - delta * stepScale)
                if abs(nextParameter - current.parameter) <= Double.ulpOfOne {
                    stepScale *= 0.5
                    continue
                }
                let next = try projectionCandidate(
                    point,
                    curve: curve,
                    parameter: nextParameter,
                    iterations: iteration
                )
                if next.squaredDistance <= current.squaredDistance {
                    accepted = next
                    break
                }
                stepScale *= 0.5
            }
            guard var next = accepted else {
                current.iterations = iteration
                return current
            }
            let improvement = current.squaredDistance - next.squaredDistance
            if improvement <= tolerance.distance * tolerance.distance {
                next.converged = true
                return next
            }
            current = next
        }
        return current
    }

    private func projectOntoCurve(
        _ point: Point3D,
        direction: Vector3D,
        curve: Curve3D,
        range: CurveParameterRange,
        options: CurveDirectionalProjectionOptions
    ) throws -> CurveDirectionalProjectionCandidate {
        let candidates = try sampleParameters(curve: curve, range: range, sampleCount: options.sampleCount)
            .compactMap {
                try directionalProjectionCandidate(
                    point,
                    direction: direction,
                    curve: curve,
                    parameter: $0,
                    range: options.range
                )
            }
            .sorted { $0.squaredLineDistance < $1.squaredLineDistance }
        guard !candidates.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Curve directional projection has no parameter samples.")
        }
        var best: CurveDirectionalProjectionCandidate?
        for seed in candidates.prefix(min(6, candidates.count)) {
            let refined = try refineDirectionalProjection(
                from: seed,
                point: point,
                direction: direction,
                curve: curve,
                parameterRange: range,
                directionalRange: options.range,
                maximumIterations: options.maximumIterations
            )
            if shouldReplaceDirectionalProjectionCandidate(current: best, candidate: refined) {
                best = refined
            }
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Curve directional projection refinement produced no candidate.")
        }
        return best
    }

    private func refineDirectionalProjection(
        from seed: CurveDirectionalProjectionCandidate,
        point: Point3D,
        direction: Vector3D,
        curve: Curve3D,
        parameterRange: CurveParameterRange,
        directionalRange: CurveDirectionalProjectionRange,
        maximumIterations: Int
    ) throws -> CurveDirectionalProjectionCandidate {
        var current = seed
        guard maximumIterations > 0 else {
            return current
        }
        let parameterTolerance = self.parameterTolerance(for: curve)
        for iteration in 1...maximumIterations {
            if current.lineDistance <= tolerance.distance {
                current.iterations = iteration
                current.converged = true
                return current
            }
            let geometry = try curve.differentialGeometry(at: current.parameter, tolerance: tolerance)
            let lineDerivative = geometry.firstDerivative -
                direction * geometry.firstDerivative.dot(direction)
            let lineSecondDerivative = geometry.secondDerivative -
                direction * geometry.secondDerivative.dot(direction)
            let gradient = current.lineResidual.dot(lineDerivative)
            let hessian = lineDerivative.dot(lineDerivative) +
                current.lineResidual.dot(lineSecondDerivative)
            guard abs(hessian) > max(tolerance.distance * tolerance.distance, Double.ulpOfOne) else {
                return current
            }
            let delta = gradient / hessian
            guard delta.isFinite else {
                throw GeometryError.invalidDistance(delta)
            }
            if abs(delta) <= parameterTolerance {
                current.iterations = iteration
                current.converged = current.lineDistance <= tolerance.distance
                return current
            }
            var stepScale = 1.0
            var accepted: CurveDirectionalProjectionCandidate?
            while stepScale >= 1.0 / 128.0 {
                let nextParameter = parameterRange.clamped(current.parameter - delta * stepScale)
                if abs(nextParameter - current.parameter) <= Double.ulpOfOne {
                    stepScale *= 0.5
                    continue
                }
                guard let next = try directionalProjectionCandidate(
                    point,
                    direction: direction,
                    curve: curve,
                    parameter: nextParameter,
                    range: directionalRange,
                    iterations: iteration
                ) else {
                    stepScale *= 0.5
                    continue
                }
                if next.squaredLineDistance <= current.squaredLineDistance {
                    accepted = next
                    break
                }
                stepScale *= 0.5
            }
            guard var next = accepted else {
                current.iterations = iteration
                return current
            }
            let improvement = current.squaredLineDistance - next.squaredLineDistance
            if next.lineDistance <= tolerance.distance ||
                improvement <= tolerance.distance * tolerance.distance {
                next.converged = next.lineDistance <= tolerance.distance
                return next
            }
            current = next
        }
        return current
    }

    private func closestLineParameter(
        to point: Point3D,
        on line: Line3D,
        domain: ParameterDomain
    ) throws -> Double {
        try line.validate(tolerance: tolerance)
        let rawParameter = (point - line.origin).dot(line.direction)
        switch domain {
        case let .closed(lower, upper):
            return min(max(rawParameter, min(lower, upper)), max(lower, upper))
        case .periodic:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Line curves cannot use periodic parameter domains.")
        case .unbounded:
            return rawParameter
        }
    }

    private func projectOntoLine(
        _ point: Point3D,
        direction: Vector3D,
        line: Line3D,
        domain: ParameterDomain,
        range: CurveDirectionalProjectionRange
    ) throws -> CurveDirectionalProjectionCandidate {
        try line.validate(tolerance: tolerance)
        let rawParameter = closestLineParameterToProjectionLine(
            point,
            direction: direction,
            line: line
        )
        var parameters: [Double] = []
        switch domain {
        case let .closed(lower, upper):
            let lowerBound = min(lower, upper)
            let upperBound = max(lower, upper)
            appendUnique(min(max(rawParameter, lowerBound), upperBound), to: &parameters)
            appendUnique(lowerBound, to: &parameters)
            appendUnique(upperBound, to: &parameters)
        case .periodic:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Line curves cannot use periodic parameter domains.")
        case .unbounded:
            appendUnique(rawParameter, to: &parameters)
        }
        var best: CurveDirectionalProjectionCandidate?
        for parameter in parameters {
            guard let candidate = try directionalProjectionCandidate(
                point,
                direction: direction,
                curve: .line(line),
                parameter: parameter,
                range: range
            ) else {
                continue
            }
            if shouldReplaceDirectionalProjectionCandidate(current: best, candidate: candidate) {
                best = candidate
            }
        }
        guard var best else {
            throw FeatureEvaluationError.emptyResult("Curve directional projection produced no accepted line candidate.")
        }
        best.converged = best.lineDistance <= tolerance.distance
        return best
    }

    private func closestLineParameterToProjectionLine(
        _ point: Point3D,
        direction: Vector3D,
        line: Line3D
    ) -> Double {
        let alignment = line.direction.dot(direction)
        let originDelta = line.origin - point
        let denominator = 1.0 - alignment * alignment
        guard denominator > tolerance.distance * tolerance.distance else {
            return (point - line.origin).dot(line.direction)
        }
        let curveOriginProjection = line.direction.dot(originDelta)
        let projectionOriginProjection = direction.dot(originDelta)
        return (alignment * projectionOriginProjection - curveOriginProjection) / denominator
    }

    private func closestPointOnPolyline(
        _ point: Point3D,
        points: [Point3D]
    ) throws -> CurveProjectionCandidate {
        let totalLength = try polylineLength(points)
        var traversedDistance = 0.0
        var best: CurveProjectionCandidate?
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let segment = end - start
            let segmentLength = segment.length
            guard segmentLength > tolerance.distance else {
                continue
            }
            let localDistance = min(
                max((point - start).dot(segment / segmentLength), 0.0),
                segmentLength
            )
            let curvePoint = start + (segment / segmentLength) * localDistance
            let residual = curvePoint - point
            let squaredDistance = residual.dot(residual)
            guard squaredDistance.isFinite else {
                throw GeometryError.invalidDistance(squaredDistance)
            }
            let candidate = CurveProjectionCandidate(
                parameter: (traversedDistance + localDistance) / totalLength,
                squaredDistance: squaredDistance,
                iterations: 0,
                converged: false
            )
            if shouldReplaceProjectionCandidate(current: best, candidate: candidate) {
                best = candidate
            }
            traversedDistance += segmentLength
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Curve polyline contains no projectable spans.")
        }
        return best
    }

    private func projectOntoPolyline(
        _ point: Point3D,
        direction: Vector3D,
        points: [Point3D],
        range: CurveDirectionalProjectionRange
    ) throws -> CurveDirectionalProjectionCandidate {
        let totalLength = try polylineLength(points)
        var traversedDistance = 0.0
        var best: CurveDirectionalProjectionCandidate?
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let segment = end - start
            let segmentLength = segment.length
            guard segmentLength > tolerance.distance else {
                continue
            }
            let segmentDirection = segment / segmentLength
            let localDistance = closestSegmentParameterToProjectionLine(
                point,
                direction: direction,
                segmentOrigin: start,
                segmentDirection: segmentDirection,
                segmentLength: segmentLength
            )
            let curvePoint = start + segmentDirection * localDistance
            let signedDistance = (curvePoint - point).dot(direction)
            guard range.accepts(signedDistance, tolerance: tolerance) else {
                traversedDistance += segmentLength
                continue
            }
            let linePoint = point + direction * signedDistance
            let lineResidual = curvePoint - linePoint
            let squaredLineDistance = lineResidual.dot(lineResidual)
            guard squaredLineDistance.isFinite else {
                throw GeometryError.invalidDistance(squaredLineDistance)
            }
            let candidate = CurveDirectionalProjectionCandidate(
                parameter: (traversedDistance + localDistance) / totalLength,
                signedDistanceAlongDirection: signedDistance,
                lineResidual: lineResidual,
                squaredLineDistance: squaredLineDistance,
                lineDistance: sqrt(squaredLineDistance),
                iterations: 0,
                converged: squaredLineDistance <= tolerance.distance * tolerance.distance
            )
            if shouldReplaceDirectionalProjectionCandidate(current: best, candidate: candidate) {
                best = candidate
            }
            traversedDistance += segmentLength
        }
        guard let best else {
            throw FeatureEvaluationError.emptyResult("Curve directional projection has no accepted polyline candidate.")
        }
        return best
    }

    private func closestSegmentParameterToProjectionLine(
        _ point: Point3D,
        direction: Vector3D,
        segmentOrigin: Point3D,
        segmentDirection: Vector3D,
        segmentLength: Double
    ) -> Double {
        let alignment = segmentDirection.dot(direction)
        let originDelta = segmentOrigin - point
        let denominator = 1.0 - alignment * alignment
        let rawParameter: Double
        if denominator > tolerance.distance * tolerance.distance {
            let curveOriginProjection = segmentDirection.dot(originDelta)
            let projectionOriginProjection = direction.dot(originDelta)
            rawParameter = (alignment * projectionOriginProjection - curveOriginProjection) / denominator
        } else {
            rawParameter = (point - segmentOrigin).dot(segmentDirection)
        }
        return min(max(rawParameter, 0.0), segmentLength)
    }

    private func projectionCandidate(
        _ point: Point3D,
        curve: Curve3D,
        parameter: Double,
        iterations: Int = 0
    ) throws -> CurveProjectionCandidate {
        let curvePoint = try curve.point(at: parameter, tolerance: tolerance)
        let residual = curvePoint - point
        let squaredDistance = residual.dot(residual)
        guard squaredDistance.isFinite else {
            throw GeometryError.invalidDistance(squaredDistance)
        }
        return CurveProjectionCandidate(
            parameter: parameter,
            squaredDistance: squaredDistance,
            iterations: iterations,
            converged: false
        )
    }

    private func directionalProjectionCandidate(
        _ point: Point3D,
        direction: Vector3D,
        curve: Curve3D,
        parameter: Double,
        range: CurveDirectionalProjectionRange,
        iterations: Int = 0
    ) throws -> CurveDirectionalProjectionCandidate? {
        let curvePoint = try curve.point(at: parameter, tolerance: tolerance)
        let signedDistance = (curvePoint - point).dot(direction)
        guard range.accepts(signedDistance, tolerance: tolerance) else {
            return nil
        }
        let linePoint = point + direction * signedDistance
        let lineResidual = curvePoint - linePoint
        let squaredLineDistance = lineResidual.dot(lineResidual)
        guard squaredLineDistance.isFinite else {
            throw GeometryError.invalidDistance(squaredLineDistance)
        }
        return CurveDirectionalProjectionCandidate(
            parameter: parameter,
            signedDistanceAlongDirection: signedDistance,
            lineResidual: lineResidual,
            squaredLineDistance: squaredLineDistance,
            lineDistance: sqrt(squaredLineDistance),
            iterations: iterations,
            converged: false
        )
    }

    private func parameterRange(for curve: EvaluatedCurve) throws -> CurveParameterRange {
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            return CurveParameterRange(start: lower, end: upper)
        case let .periodic(period):
            return CurveParameterRange(start: 0.0, end: period)
        case .unbounded:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Curve projection requires a finite parameter range unless the source is an exact line."
            )
        }
    }

    private func sampleParameters(
        curve: Curve3D,
        range: CurveParameterRange,
        sampleCount: Int
    ) throws -> [Double] {
        var samples: [Double] = []
        appendUnique(range.start, to: &samples)
        appendUnique(range.end, to: &samples)
        appendUnique(range.midpoint, to: &samples)
        if case let .bSpline(curve) = curve {
            for knot in curve.knots where knot >= range.lower - tolerance.distance &&
                knot <= range.upper + tolerance.distance {
                appendUnique(range.clamped(knot), to: &samples)
            }
        }
        for index in 0..<sampleCount {
            let ratio = Double(index) / Double(sampleCount - 1)
            appendUnique(range.lower + (range.upper - range.lower) * ratio, to: &samples)
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

    private func shouldReplaceProjectionCandidate(
        current: CurveProjectionCandidate?,
        candidate: CurveProjectionCandidate
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

    private func shouldReplaceDirectionalProjectionCandidate(
        current: CurveDirectionalProjectionCandidate?,
        candidate: CurveDirectionalProjectionCandidate
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

    private func parameterTolerance(for curve: Curve3D) -> Double {
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse), .analytic(.planeTorus):
            return tolerance.angle
        case .line, .analytic(.line), .analytic(.parabola), .bSpline:
            return tolerance.distance
        case .analytic(.hyperbola), .implicit, .surfaceLift:
            return tolerance.relative
        }
    }

    private func polylinePoint(
        at reference: CurveParameterReference,
        curve: EvaluatedCurve
    ) throws -> CurveQueryPoint {
        let targetDistance = try polylineLength(curve.points) * reference.parameter
        var traversedDistance = 0.0
        for index in 0..<(curve.points.count - 1) {
            let start = curve.points[index]
            let end = curve.points[index + 1]
            let segment = end - start
            let segmentLength = segment.length
            guard segmentLength > tolerance.distance else {
                continue
            }
            let isLastSegment = index == curve.points.count - 2
            if targetDistance <= traversedDistance + segmentLength || isLastSegment {
                let localDistance = min(max(targetDistance - traversedDistance, 0.0), segmentLength)
                let ratio = localDistance / segmentLength
                return CurveQueryPoint(
                    reference: reference,
                    point: start + (segment * ratio),
                    tangent: try segment.normalized(tolerance: tolerance.distance),
                    curvature: nil,
                    isExact: false
                )
            }
            traversedDistance += segmentLength
        }
        throw FeatureEvaluationError.emptyResult("Curve polyline contains no queryable spans.")
    }

    private func polylineLength(_ points: [Point3D]) throws -> Double {
        var length = 0.0
        for index in 0..<(points.count - 1) {
            let segmentLength = (points[index + 1] - points[index]).length
            guard segmentLength.isFinite else {
                throw GeometryError.invalidDistance(segmentLength)
            }
            length += segmentLength
        }
        guard length > tolerance.distance else {
            throw GeometryError.invalidDistance(length)
        }
        return length
    }
}

private struct CurveParameterRange: Sendable, Hashable {
    var start: Double
    var end: Double

    var lower: Double {
        min(start, end)
    }

    var upper: Double {
        max(start, end)
    }

    var midpoint: Double {
        (start + end) * 0.5
    }

    func clamped(_ parameter: Double) -> Double {
        min(max(parameter, lower), upper)
    }
}

private struct CurveProjectionCandidate: Sendable, Hashable {
    var parameter: Double
    var squaredDistance: Double
    var iterations: Int
    var converged: Bool

    func withConvergence(_ converged: Bool) -> CurveProjectionCandidate {
        CurveProjectionCandidate(
            parameter: parameter,
            squaredDistance: squaredDistance,
            iterations: iterations,
            converged: converged
        )
    }
}

private struct CurveDirectionalProjectionCandidate: Sendable, Hashable {
    var parameter: Double
    var signedDistanceAlongDirection: Double
    var lineResidual: Vector3D
    var squaredLineDistance: Double
    var lineDistance: Double
    var iterations: Int
    var converged: Bool
}
