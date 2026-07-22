import Foundation
import CADCore
import CADGeometry
import CADIR

public struct CurveOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .curveOffset(curveOffset) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve offset evaluator requires a curveOffset feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try curveOffset.validate(tolerance: context.tolerance)
        }
        let distance = try resolvedDistance(for: curveOffset, featureID: feature.id, context: context)
        let source = try sourceCurve(curveOffset.source, featureID: feature.id, context: context)
        let generatedCurve = try offsetCurve(
            featureID: feature.id,
            source: source,
            distance: distance,
            planeNormal: curveOffset.planeNormal,
            side: curveOffset.side,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
    }

    private func resolvedDistance(
        for curveOffset: CurveOffsetFeature,
        featureID: FeatureID,
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
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Curve offset distance must be a positive length above modeling tolerance."
            )
        }
        return quantity.value
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve offset source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve offset source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Curve offset requires an exact source curve.")
        }
        return curve
    }

    private func offsetCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Curve offset requires an exact source curve.")
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
                tolerance: tolerance
            )
        case let .analytic(curve):
            switch curve {
            case let .line(origin, direction):
                return try offsetLine(
                    featureID: featureID,
                    source: source,
                    line: Line3D(origin: origin, direction: direction),
                    distance: distance,
                    planeNormal: planeNormal,
                    side: side,
                    tolerance: tolerance
                )
            case let .circle(center, normal, radius):
                return try offsetAnalyticCircle(
                    featureID: featureID,
                    source: source,
                    center: center,
                    normal: normal,
                    radius: radius,
                    distance: distance,
                    planeNormal: planeNormal,
                    side: side,
                    tolerance: tolerance
                )
            case let .arc(center, normal, radius, startAngle, endAngle):
                return try offsetAnalyticArc(
                    featureID: featureID,
                    source: source,
                    center: center,
                    normal: normal,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    distance: distance,
                    planeNormal: planeNormal,
                    side: side,
                    tolerance: tolerance
                )
            case .ellipse, .hyperbola, .parabola:
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                    "Exact noncircular conic offsets require an exact offset-locus representation."
                )
            case .planeTorus:
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                    "A certified plane-torus curve offset requires a certified offset-locus implementation."
                )
            }
        case .bSpline:
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                "Exact B-spline curve offsets are not available without an explicit offset-approximation contract."
            )
        case .implicit:
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                "Implicit intersection curve offset requires a certified offset-locus implementation."
            )
        case .surfaceLift:
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                "A surface-lift curve offset requires a certified offset-locus implementation."
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
        let planeResidual = abs(normal.dot(line.direction))
        guard planeResidual <= sin(tolerance.angle) else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                residual: planeResidual,
                tolerance: tolerance,
                message: "Curve offset plane normal must be perpendicular to the source line."
            )
        }
        let sideSign = side == .left ? 1.0 : -1.0
        let offsetDirection = try normal.cross(line.direction).normalized(tolerance: tolerance.distance)
        let offsetVector = offsetDirection * (sideSign * distance)
        let offsetLine = Line3D(origin: line.origin + offsetVector, direction: line.direction)
        let exactCurve: Curve3D
        if case .analytic(.line) = source.exactCurve {
            exactCurve = .analytic(.line(
                origin: offsetLine.origin,
                direction: offsetLine.direction
            ))
        } else {
            exactCurve = .line(offsetLine)
        }
        let points = source.points.map { $0 + offsetVector }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .line,
            points: points,
            plane: source.plane,
            exactCurve: exactCurve,
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
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        try circle.validate(tolerance: tolerance)
        let radius = try offsetRadius(
            sourceRadius: circle.radius,
            sourceNormal: circle.normal,
            planeNormal: planeNormal,
            distance: distance,
            side: side,
            featureID: featureID,
            tolerance: tolerance
        )
        let offsetCircle = Circle3D(center: circle.center, normal: circle.normal, radius: radius)
        let exactCurve = Curve3D.circle(offsetCircle)
        let domain = source.exactParameterDomain
        let points = try samplePoints(
            exactCurve,
            domain: domain,
            tolerance: tolerance
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: source.kind == .arc ? .arc : .circle,
            points: points,
            isClosed: circularDomainIsClosed(domain, tolerance: tolerance),
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func offsetAnalyticCircle(
        featureID: FeatureID,
        source: EvaluatedCurve,
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let offsetRadius = try offsetRadius(
            sourceRadius: radius,
            sourceNormal: normal,
            planeNormal: planeNormal,
            distance: distance,
            side: side,
            featureID: featureID,
            tolerance: tolerance
        )
        return try circularCurve(
            featureID: featureID,
            source: source,
            exactCurve: .analytic(.circle(center: center, normal: normal, radius: offsetRadius)),
            kind: source.kind == .arc ? .arc : .circle,
            domain: source.exactParameterDomain,
            tolerance: tolerance
        )
    }

    private func offsetAnalyticArc(
        featureID: FeatureID,
        source: EvaluatedCurve,
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        distance: Double,
        planeNormal: Vector3D,
        side: CurveOffsetSide,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let offsetRadius = try offsetRadius(
            sourceRadius: radius,
            sourceNormal: normal,
            planeNormal: planeNormal,
            distance: distance,
            side: side,
            featureID: featureID,
            tolerance: tolerance
        )
        return try circularCurve(
            featureID: featureID,
            source: source,
            exactCurve: .analytic(.arc(
                center: center,
                normal: normal,
                radius: offsetRadius,
                startAngle: startAngle,
                endAngle: endAngle
            )),
            kind: .arc,
            domain: source.exactParameterDomain ?? .closed(startAngle, endAngle),
            tolerance: tolerance
        )
    }

    private func circularCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        exactCurve: Curve3D,
        kind: EvaluatedCurveKind,
        domain: ParameterDomain?,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let points = try samplePoints(exactCurve, domain: domain, tolerance: tolerance)
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: kind,
            points: points,
            isClosed: circularDomainIsClosed(domain, tolerance: tolerance),
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func offsetRadius(
        sourceRadius: Double,
        sourceNormal: Vector3D,
        planeNormal: Vector3D,
        distance: Double,
        side: CurveOffsetSide,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let alignment = normal.dot(sourceNormal)
        let angularResidual = normal.cross(sourceNormal).length
        guard angularResidual <= sin(tolerance.angle),
              abs(alignment) > Double.ulpOfOne else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Curve offset plane normal must align with the source circle or arc normal."
            )
        }
        let sideSign = side == .left ? 1.0 : -1.0
        let orientationSign = alignment >= 0.0 ? 1.0 : -1.0
        let radius = sourceRadius - sideSign * orientationSign * distance
        guard radius > tolerance.distance else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Curve offset collapses or reverses the source radius."
            )
        }
        return radius
    }

    private func circularDomainIsClosed(
        _ domain: ParameterDomain?,
        tolerance: ModelingTolerance
    ) -> Bool {
        switch domain {
        case let .closed(lower, upper):
            return upper - lower >= 2.0 * .pi - tolerance.angle
        case .periodic, .none:
            return true
        case .unbounded:
            return false
        }
    }

    private func samplePoints(
        _ curve: Curve3D,
        domain: ParameterDomain?,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let lowerBound: Double
        let upperBound: Double
        switch domain {
        case let .closed(lower, upper):
            lowerBound = lower
            upperBound = upper
        case .unbounded:
            throw kernelError(.unsupportedCapability, tolerance: tolerance, "Curve offset cannot derive display samples for an unbounded circle domain.")
        case .periodic, .none:
            lowerBound = 0.0
            upperBound = Double.pi * 2.0
        }
        let span = upperBound - lowerBound
        guard span > tolerance.angle else {
            throw GeometryError.invalidAngle(span)
        }
        let sampleCount = 33
        return try (0..<sampleCount).map { index in
            try curve.point(
                at: lowerBound + span * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
