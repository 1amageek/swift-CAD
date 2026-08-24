import Foundation
import CADCore
import CADGeometry
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
    public var limits: ProjectionResourceLimits

    public init(limits: ProjectionResourceLimits = ProjectionResourceLimits()) {
        self.limits = limits
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
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
    public var limits: ProjectionResourceLimits
    public var range: EdgeDirectionalProjectionRange

    public init(
        limits: ProjectionResourceLimits = ProjectionResourceLimits(),
        range: EdgeDirectionalProjectionRange = .line
    ) {
        self.limits = limits
        self.range = range
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
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
        try options.validate(tolerance: tolerance)
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
             .certifiedIntersection,
             .rigidImage,
             .affineImage:
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
        try options.validate(tolerance: tolerance)
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
        let projection = try curve.closestParameterProjection(
            of: point,
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(
                    lower: range.lower,
                    upper: range.upper
                ),
                maximumIterations: options.limits.maximumIterations,
                seedCount: options.limits.seedCount,
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        return EdgeProjectionCandidate(
            parameter: projection.parameter,
            squaredDistance: projection.residual * projection.residual,
            iterations: projection.iterations,
            converged: true
        )
    }

    private func projectOntoCurve(
        _ point: Point3D,
        direction: Vector3D,
        curve: Curve3D,
        range: EdgeParameterRange,
        options: EdgeDirectionalProjectionOptions
    ) throws -> EdgeDirectionalProjectionCandidate {
        let projection = try curve.directionalParameterProjection(
            from: point,
            along: direction,
            options: CurveDirectionalParameterProjectionOptions(
                parameterRange: try ScalarInterval(
                    lower: range.lower,
                    upper: range.upper
                ),
                range: directionalProjectionRange(options.range),
                maximumSubdivisionDepth: options.limits.maximumSubdivisionDepth,
                maximumSubdivisionCells: options.limits.maximumSubdivisionCells,
                maximumIterations: options.limits.maximumIterations,
                maximumCandidateCount: options.limits.maximumCandidateCount
            ),
            tolerance: tolerance
        )
        return EdgeDirectionalProjectionCandidate(
            parameter: projection.parameter,
            signedDistanceAlongDirection: projection.signedDistanceAlongDirection,
            iterations: projection.iterations,
            converged: true
        )
    }

    private func directionalProjectionRange(
        _ range: EdgeDirectionalProjectionRange
    ) -> DirectionalProjectionRange3D {
        switch range {
        case .line:
            return .line
        case .ray:
            return .ray
        }
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
        if case let .closed(lower, upper) = curve.parameterDomain {
            return EdgeParameterRange(start: lower, end: upper)
        }
        switch curve {
        case let .line(line):
            return EdgeParameterRange(
                start: (startPoint - line.origin).dot(line.direction),
                end: (endPoint - line.origin).dot(line.direction)
            )
        case .circle:
            throw missingNonlinearEdgeTrimError(edgeID: edge.id)
        case let .analytic(.line(origin, direction)):
            return EdgeParameterRange(
                start: (startPoint - origin).dot(direction),
                end: (endPoint - origin).dot(direction)
            )
        case .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            throw missingNonlinearEdgeTrimError(edgeID: edge.id)
        case let .rigidImage(image):
            let inverse = image.transform.inverted()
            return try edgeParameterRange(
                edge: edge,
                curve: image.source,
                startPoint: inverse.applying(to: startPoint),
                endPoint: inverse.applying(to: endPoint)
            )
        case .affineImage:
            if case let .closed(lower, upper) = curve.parameterDomain {
                return EdgeParameterRange(start: lower, end: upper)
            }
            guard let line = curve.exactLinearLocus else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    subshapeID: nil,
                    tolerance: tolerance,
                    message: "An untrimmed affine-image edge requires an exact linear parameterization."
                )
            }
            let denominator = line.direction.dot(line.direction)
            guard denominator > tolerance.distance * tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: sqrt(max(0.0, denominator)),
                    tolerance: tolerance,
                    message: "An affine-image edge has a singular line direction."
                )
            }
            return EdgeParameterRange(
                start: (startPoint - line.origin).dot(line.direction) / denominator,
                end: (endPoint - line.origin).dot(line.direction) / denominator
            )
        }
    }

    private func missingNonlinearEdgeTrimError(edgeID: EdgeID) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Non-linear edge \(edgeID) requires either explicit trim parameters or a bounded exact curve domain."
        )
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
    var iterations: Int
    var converged: Bool
}
