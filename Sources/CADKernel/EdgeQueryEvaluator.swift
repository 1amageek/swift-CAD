import Foundation
import CADCore
import CADIR
import CADTopology

public struct ResolvedEdge: Sendable {
    public var reference: EdgeReference
    public var edgeID: EdgeID
    public var curveID: CurveID
    public var edge: Edge
    public var curve: Curve3D
    public var startPoint: Point3D
    public var endPoint: Point3D
    public var startParameter: Double
    public var endParameter: Double

    public init(
        reference: EdgeReference,
        edgeID: EdgeID,
        curveID: CurveID,
        edge: Edge,
        curve: Curve3D,
        startPoint: Point3D,
        endPoint: Point3D,
        startParameter: Double,
        endParameter: Double
    ) {
        self.reference = reference
        self.edgeID = edgeID
        self.curveID = curveID
        self.edge = edge
        self.curve = curve
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.startParameter = startParameter
        self.endParameter = endParameter
    }
}

public struct EdgeEndpointQueryResult: Codable, Sendable, Hashable {
    public var edge: EdgeReference
    public var start: Point3D
    public var end: Point3D

    public init(edge: EdgeReference, start: Point3D, end: Point3D) {
        self.edge = edge
        self.start = start
        self.end = end
    }
}

public struct EdgeQueryFrame: Codable, Sendable, Hashable {
    public var reference: EdgeParameterReference
    public var point: Point3D
    public var tangent: Vector3D
    public var curvature: Double
    public var curvatureVector: Vector3D

    public init(
        reference: EdgeParameterReference,
        point: Point3D,
        tangent: Vector3D,
        curvature: Double,
        curvatureVector: Vector3D
    ) {
        self.reference = reference
        self.point = point
        self.tangent = tangent
        self.curvature = curvature
        self.curvatureVector = curvatureVector
    }
}

public struct EdgeProjectionOptions: Sendable, Hashable {
    public var sampleCount: Int
    public var maximumIterations: Int

    public init(sampleCount: Int = 9, maximumIterations: Int = 32) {
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Edge projection sample count must be at least two.")
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Edge projection iteration count must not be negative.")
        }
    }
}

public struct EdgeProjectionResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var parameterReference: EdgeParameterReference
    public var projectedPoint: Point3D
    public var residual: Vector3D
    public var distance: Double
    public var frame: EdgeQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        frame: EdgeQueryFrame,
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

public enum EdgeDirectionalProjectionRange: Sendable, Hashable {
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

public struct EdgeDirectionalProjectionOptions: Sendable, Hashable {
    public var sampleCount: Int
    public var maximumIterations: Int
    public var range: EdgeDirectionalProjectionRange

    public init(
        sampleCount: Int = 9,
        maximumIterations: Int = 32,
        range: EdgeDirectionalProjectionRange = .line
    ) {
        self.sampleCount = sampleCount
        self.maximumIterations = maximumIterations
        self.range = range
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Edge projection sample count must be at least two.")
        }
        guard maximumIterations >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Edge projection iteration count must not be negative.")
        }
    }
}

public struct EdgeDirectionalProjectionResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var direction: Vector3D
    public var signedDistanceAlongDirection: Double
    public var linePoint: Point3D
    public var parameterReference: EdgeParameterReference
    public var projectedPoint: Point3D
    public var lineResidual: Vector3D
    public var lineDistance: Double
    public var frame: EdgeQueryFrame
    public var iterations: Int
    public var converged: Bool

    public init(
        sourcePoint: Point3D,
        direction: Vector3D,
        signedDistanceAlongDirection: Double,
        frame: EdgeQueryFrame,
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

public struct EdgeQueryEvaluator: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func resolve(
        _ reference: EdgeReference,
        in document: EvaluatedDocument
    ) throws -> ResolvedEdge {
        try reference.validate()
        let topologyReference = try document.topologyReference(for: reference.subshape)
        guard case let .edge(edgeID) = topologyReference else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                subshapeID: reference.subshape.subshapeID,
                tolerance: tolerance,
                message: "Stable edge reference did not resolve to an edge."
            )
        }
        guard let edge = document.brep.edges[edgeID] else {
            throw FeatureEvaluationError.missingInput("Edge query references a missing edge.")
        }
        guard let curve = document.brep.geometry.curves[edge.curveID] else {
            throw FeatureEvaluationError.missingInput("Edge query references a missing curve.")
        }
        guard let startPoint = document.brep.vertices[edge.startVertexID]?.point,
              let endPoint = document.brep.vertices[edge.endVertexID]?.point else {
            throw FeatureEvaluationError.missingInput("Edge query references a missing vertex.")
        }
        try curve.validate(tolerance: tolerance)
        let range = try edgeParameterRange(edge: edge, curve: curve, startPoint: startPoint, endPoint: endPoint)
        return ResolvedEdge(
            reference: reference,
            edgeID: edgeID,
            curveID: edge.curveID,
            edge: edge,
            curve: curve,
            startPoint: startPoint,
            endPoint: endPoint,
            startParameter: range.start,
            endParameter: range.end
        )
    }

    public func endpoints(
        of reference: EdgeReference,
        in document: EvaluatedDocument
    ) throws -> EdgeEndpointQueryResult {
        let resolved = try resolve(reference, in: document)
        return EdgeEndpointQueryResult(
            edge: reference,
            start: resolved.startPoint,
            end: resolved.endPoint
        )
    }

    public func midpoint(
        of reference: EdgeReference,
        in document: EvaluatedDocument
    ) throws -> EdgeQueryFrame {
        let resolved = try resolve(reference, in: document)
        let range = EdgeParameterRange(start: resolved.startParameter, end: resolved.endParameter)
        return try frame(
            at: EdgeParameterReference(edge: reference, parameter: range.midpoint),
            resolved: resolved,
            range: range
        )
    }

    public func frame(
        at reference: EdgeParameterReference,
        in document: EvaluatedDocument
    ) throws -> EdgeQueryFrame {
        try reference.validate()
        let resolved = try resolve(reference.edge, in: document)
        let range = EdgeParameterRange(start: resolved.startParameter, end: resolved.endParameter)
        return try frame(at: reference, resolved: resolved, range: range)
    }

    public func closestPoint(
        to point: Point3D,
        on reference: EdgeReference,
        in document: EvaluatedDocument,
        options: EdgeProjectionOptions = EdgeProjectionOptions()
    ) throws -> EdgeProjectionResult {
        try point.validate()
        try options.validate()
        let resolved = try resolve(reference, in: document)
        let range = EdgeParameterRange(start: resolved.startParameter, end: resolved.endParameter)
        let candidate: EdgeProjectionCandidate
        switch resolved.curve {
        case let .line(line):
            let parameter = range.clamped((point - line.origin).dot(line.direction))
            candidate = try projectionCandidate(point, curve: resolved.curve, parameter: parameter)
                .withConvergence(true)
        case let .analytic(.line(origin, direction)):
            let parameter = range.clamped((point - origin).dot(direction))
            candidate = try projectionCandidate(point, curve: resolved.curve, parameter: parameter)
                .withConvergence(true)
        case .circle,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            candidate = try closestPointOnCurve(
                point,
                curve: resolved.curve,
                range: range,
                options: options
            )
        }
        let frame = try frame(
            at: EdgeParameterReference(edge: reference, parameter: candidate.parameter),
            resolved: resolved,
            range: range
        )
        return EdgeProjectionResult(
            sourcePoint: point,
            frame: frame,
            iterations: candidate.iterations,
            converged: candidate.converged
        )
    }

    public func project(
        _ point: Point3D,
        along direction: Vector3D,
        onto reference: EdgeReference,
        in document: EvaluatedDocument,
        options: EdgeDirectionalProjectionOptions = EdgeDirectionalProjectionOptions()
    ) throws -> EdgeDirectionalProjectionResult {
        try point.validate()
        try options.validate()
        let unitDirection = try direction.normalized(tolerance: tolerance.distance)
        let resolved = try resolve(reference, in: document)
        let range = EdgeParameterRange(start: resolved.startParameter, end: resolved.endParameter)
        let candidate = try projectOntoCurve(
            point,
            direction: unitDirection,
            curve: resolved.curve,
            range: range,
            options: options
        )
        let frame = try frame(
            at: EdgeParameterReference(edge: reference, parameter: candidate.parameter),
            resolved: resolved,
            range: range
        )
        return EdgeDirectionalProjectionResult(
            sourcePoint: point,
            direction: unitDirection,
            signedDistanceAlongDirection: candidate.signedDistanceAlongDirection,
            frame: frame,
            iterations: candidate.iterations,
            converged: candidate.converged
        )
    }

    private func frame(
        at reference: EdgeParameterReference,
        resolved: ResolvedEdge,
        range: EdgeParameterRange
    ) throws -> EdgeQueryFrame {
        try reference.validate()
        guard range.contains(reference.parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(reference.parameter)
        }
        let geometry = try resolved.curve.differentialGeometry(
            at: reference.parameter,
            tolerance: tolerance
        )
        return EdgeQueryFrame(
            reference: reference,
            point: geometry.position,
            tangent: geometry.tangent * range.directionSign,
            curvature: geometry.curvature,
            curvatureVector: geometry.curvatureVector
        )
    }

    private func closestPointOnCurve(
        _ point: Point3D,
        curve: Curve3D,
        range: EdgeParameterRange,
        options: EdgeProjectionOptions
    ) throws -> EdgeProjectionCandidate {
        let candidates = try sampleParameters(curve: curve, range: range, sampleCount: options.sampleCount)
            .map { try projectionCandidate(point, curve: curve, parameter: $0) }
            .sorted { $0.squaredDistance < $1.squaredDistance }
        guard !candidates.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Edge projection has no parameter samples.")
        }
        var best: EdgeProjectionCandidate?
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
            throw FeatureEvaluationError.emptyResult("Edge projection refinement produced no candidate.")
        }
        return best
    }

    private func refineClosestProjection(
        from seed: EdgeProjectionCandidate,
        point: Point3D,
        curve: Curve3D,
        range: EdgeParameterRange,
        maximumIterations: Int
    ) throws -> EdgeProjectionCandidate {
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
            var accepted: EdgeProjectionCandidate?
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
        range: EdgeParameterRange,
        options: EdgeDirectionalProjectionOptions
    ) throws -> EdgeDirectionalProjectionCandidate {
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
            throw FeatureEvaluationError.emptyResult("Edge directional projection has no parameter samples.")
        }
        var best: EdgeDirectionalProjectionCandidate?
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
            throw FeatureEvaluationError.emptyResult("Edge directional projection refinement produced no candidate.")
        }
        return best
    }

    private func refineDirectionalProjection(
        from seed: EdgeDirectionalProjectionCandidate,
        point: Point3D,
        direction: Vector3D,
        curve: Curve3D,
        parameterRange: EdgeParameterRange,
        directionalRange: EdgeDirectionalProjectionRange,
        maximumIterations: Int
    ) throws -> EdgeDirectionalProjectionCandidate {
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
            var accepted: EdgeDirectionalProjectionCandidate?
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

    private func projectionCandidate(
        _ point: Point3D,
        curve: Curve3D,
        parameter: Double,
        iterations: Int = 0
    ) throws -> EdgeProjectionCandidate {
        let curvePoint = try curve.point(at: parameter, tolerance: tolerance)
        let residual = curvePoint - point
        let squaredDistance = residual.dot(residual)
        guard squaredDistance.isFinite else {
            throw GeometryError.invalidDistance(squaredDistance)
        }
        return EdgeProjectionCandidate(
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
        range: EdgeDirectionalProjectionRange,
        iterations: Int = 0
    ) throws -> EdgeDirectionalProjectionCandidate? {
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
        return EdgeDirectionalProjectionCandidate(
            parameter: parameter,
            signedDistanceAlongDirection: signedDistance,
            lineResidual: lineResidual,
            squaredLineDistance: squaredLineDistance,
            lineDistance: sqrt(squaredLineDistance),
            iterations: iterations,
            converged: false
        )
    }

    private func edgeParameterRange(
        edge: Edge,
        curve: Curve3D,
        startPoint: Point3D,
        endPoint: Point3D
    ) throws -> EdgeParameterRange {
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: edge.id, tolerance: tolerance)
            return EdgeParameterRange(
                start: trim.startParameter,
                end: trim.endParameter
            )
        }
        switch curve {
        case let .line(line):
            return EdgeParameterRange(
                start: (startPoint - line.origin).dot(line.direction),
                end: (endPoint - line.origin).dot(line.direction)
            )
        case .circle:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Circle edge queries require explicit trim parameters.")
        case let .analytic(.line(origin, direction)):
            return EdgeParameterRange(
                start: (startPoint - origin).dot(direction),
                end: (endPoint - origin).dot(direction)
            )
        case .analytic:
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Bounded analytic edge queries require explicit trim parameters."
            )
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "B-spline edge queries require bounded parameters.")
            }
            return EdgeParameterRange(start: lower, end: upper)
        case .implicit:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Implicit intersection edge queries require explicit trim parameters."
            )
        case .surfaceLift:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Surface-lift edge queries require explicit trim parameters."
            )
        case .certifiedIntersection:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Certified intersection edge queries require explicit trim parameters."
            )
        }
    }

    private func sampleParameters(
        curve: Curve3D,
        range: EdgeParameterRange,
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
        current: EdgeProjectionCandidate?,
        candidate: EdgeProjectionCandidate
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
        current: EdgeDirectionalProjectionCandidate?,
        candidate: EdgeDirectionalProjectionCandidate
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
        case .analytic(.hyperbola),
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            return tolerance.relative
        }
    }
}

private struct EdgeParameterRange: Sendable, Hashable {
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

    var directionSign: Double {
        end >= start ? 1.0 : -1.0
    }

    func contains(_ parameter: Double, tolerance: ModelingTolerance) -> Bool {
        parameter >= lower - tolerance.distance && parameter <= upper + tolerance.distance
    }

    func clamped(_ parameter: Double) -> Double {
        min(max(parameter, lower), upper)
    }
}

private struct EdgeProjectionCandidate: Sendable, Hashable {
    var parameter: Double
    var squaredDistance: Double
    var iterations: Int
    var converged: Bool

    func withConvergence(_ converged: Bool) -> EdgeProjectionCandidate {
        EdgeProjectionCandidate(
            parameter: parameter,
            squaredDistance: squaredDistance,
            iterations: iterations,
            converged: converged
        )
    }
}

private struct EdgeDirectionalProjectionCandidate: Sendable, Hashable {
    var parameter: Double
    var signedDistanceAlongDirection: Double
    var lineResidual: Vector3D
    var squaredLineDistance: Double
    var lineDistance: Double
    var iterations: Int
    var converged: Bool
}
