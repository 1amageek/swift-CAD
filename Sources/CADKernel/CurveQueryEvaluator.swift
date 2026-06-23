import CADCore
import CADIR

public struct CurveQueryPoint: Sendable, Hashable {
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

public struct CurveEndpointQueryResult: Sendable, Hashable {
    public var curve: CurveOutputReference
    public var start: Point3D
    public var end: Point3D

    public init(curve: CurveOutputReference, start: Point3D, end: Point3D) {
        self.curve = curve
        self.start = start
        self.end = end
    }
}

public struct CurveSpanQueryResult: Sendable, Hashable {
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

    public init(tolerance: ModelingTolerance = .standard) {
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
            throw FeatureEvaluationError.unsupportedOperation("Curve query requires an exact B-spline curve.")
        }
        return curve
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
