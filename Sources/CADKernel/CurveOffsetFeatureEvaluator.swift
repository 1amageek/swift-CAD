import Foundation
import CADCore
import CADIR

public struct CurveOffsetFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .curveOffset(curveOffset) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("CurveOffsetFeatureEvaluator requires a curve offset feature.")
        }
        try curveOffset.validate(tolerance: context.tolerance)
        let distance = try resolvedDistance(for: curveOffset, context: context)
        let source = try sourceCurve(curveOffset.source, context: context)
        let generatedCurve = try offsetCurve(
            featureID: feature.id,
            source: source,
            distance: distance,
            planeNormal: curveOffset.planeNormal,
            side: curveOffset.side,
            sampleCount: curveOffset.sampleCount,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedNames: [:],
            generatedCurves: [generatedCurve]
        )
    }

    private func resolvedDistance(
        for curveOffset: CurveOffsetFeature,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(
            curveOffset.distance,
            parameters: context.parameters,
            variables: [:]
        )
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "curveOffset.distance",
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value.isFinite, quantity.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw FeatureEvaluationError.missingInput("Curve offset source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw FeatureEvaluationError.missingInput("Curve offset source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw FeatureEvaluationError.unsupportedOperation("Curve offset requires an exact source curve.")
        }
        return curve
    }

    private func offsetCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw FeatureEvaluationError.unsupportedOperation("Curve offset requires an exact source curve.")
        }
        switch exactCurve {
        case let .line(line):
            return try offsetLine(
                featureID: featureID,
                source: source,
                line: line,
                distance: distance,
                planeNormal: planeNormal,
                side: side,
                tolerance: tolerance
            )
        case let .circle(circle):
            return try offsetCircle(
                featureID: featureID,
                source: source,
                circle: circle,
                distance: distance,
                planeNormal: planeNormal,
                side: side,
                sampleCount: sampleCount,
                tolerance: tolerance
            )
        case .bSpline:
            throw FeatureEvaluationError.unsupportedOperation(
                "Exact B-spline curve offsets are not available without an explicit offset-approximation contract."
            )
        }
    }

    private func offsetLine(
        featureID: FeatureID,
        source: EvaluatedCurve,
        line: Line3D,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try line.validate(tolerance: tolerance)
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let sideSign = side == .left ? 1.0 : -1.0
        let offsetDirection = try normal.cross(line.direction).normalized(tolerance: tolerance.distance)
        let offsetVector = offsetDirection * (sideSign * distance)
        let offsetLine = Line3D(origin: line.origin + offsetVector, direction: line.direction)
        let points = source.points.map { $0 + offsetVector }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .line,
            points: points,
            plane: source.plane,
            exactCurve: .line(offsetLine),
            exactParameterDomain: source.exactParameterDomain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func offsetCircle(
        featureID: FeatureID,
        source: EvaluatedCurve,
        circle: Circle3D,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try circle.validate(tolerance: tolerance)
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let alignment = normal.dot(circle.normal)
        guard abs(alignment) >= 1.0 - max(tolerance.angle, tolerance.distance) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Curve offset plane normal must align with the source circle normal."
            )
        }
        let sideSign = side == .left ? 1.0 : -1.0
        let orientationSign = alignment >= 0.0 ? 1.0 : -1.0
        let radius = circle.radius - sideSign * orientationSign * distance
        guard radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
        let offsetCircle = Circle3D(center: circle.center, normal: circle.normal, radius: radius)
        let exactCurve = Curve3D.circle(offsetCircle)
        let domain = source.exactParameterDomain
        let points = try samplePoints(
            exactCurve,
            domain: domain,
            sampleCount: sampleCount,
            tolerance: tolerance
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: source.kind == .arc ? .arc : .circle,
            points: points,
            isClosed: source.isClosed,
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func samplePoints(
        _ curve: Curve3D,
        domain: ParameterDomain?,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let lowerBound: Double
        let upperBound: Double
        switch domain {
        case let .closed(lower, upper):
            lowerBound = lower
            upperBound = upper
        case .unbounded:
            throw FeatureEvaluationError.unsupportedOperation("Curve offset cannot sample an unbounded circle domain.")
        case .periodic, .none:
            lowerBound = 0.0
            upperBound = Double.pi * 2.0
        }
        let span = upperBound - lowerBound
        guard span > tolerance.angle else {
            throw GeometryError.invalidAngle(span)
        }
        return try (0..<sampleCount).map { index in
            try curve.point(
                at: lowerBound + span * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
    }
}
