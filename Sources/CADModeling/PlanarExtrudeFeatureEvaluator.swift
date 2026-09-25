import CADCore
import CADGeometry
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.resolver = resolver
        self.sewer = sewer
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
        try context.tolerance.validate()
        guard case let .extrude(extrude) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarExtrudeFeatureEvaluator only supports extrude."
            )
        }
        guard extrude.operation == .newBody else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "PlanarExtrudeFeatureEvaluator only supports newBody extrude."
            )
        }
        try extrude.validate()
        let range = try extrude.resolvedAxialRange(tolerance: context.tolerance) {
            try resolver.evaluate($0, parameters: context.parameters, variables: [:])
        }
        let span = range.upperBound - range.lowerBound
        let result: EvaluationResult
        switch extrude.section {
        case .profile(let reference):
            let profile = try ResolvedModelingSection.resolveProfile(
                reference, from: context.profiles[reference.featureID]
            )
            result = try ExactProfileExtrudeBodyBuilder(
                featureID: feature.id,
                context: context,
                sewer: sewer
            ).build(
                from: profile,
                direction: extrude.direction,
                distance: span,
                startOffset: range.lowerBound,
                bodyKind: extrude.resultKind == .solid ? .solid : .sheet,
                includesCaps: extrude.resultKind == .solid
            )
        case .curve(let reference):
            let curve = try ResolvedModelingSection.resolveCurve(
                reference, from: context.curves[reference.featureID], tolerance: context.tolerance
            )
            result = try evaluateCurveSheet(
                curve, featureID: feature.id, direction: extrude.direction,
                distance: span, startOffset: range.lowerBound, context: context
            )
        }
        return try ValidatedFeatureEvaluation(
            planarExtrusion: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateCurveSheet(
        _ curve: EvaluatedCurve,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        startOffset: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let axis: Vector3D
        switch direction {
        case .normal, .symmetric:
            guard let sourcePlane = curve.plane else {
                throw KernelError(phase: .validation, code: .invalidInput,
                    featureID: featureID, tolerance: context.tolerance,
                    message: "A spatial curve has no source-plane normal; specify an extrusion vector.")
            }
            axis = try ExactSweepSectionPlane(sourcePlane, tolerance: context.tolerance).plane.normal
        case .vector(let vector):
            do { axis = try vector.normalized(tolerance: context.tolerance.distance) }
            catch GeometryError.invalidVectorLength {
                throw FeatureEvaluationError.invalidDirection(vector)
            }
        }
        let start = axis * (direction == .symmetric ? -0.5 * distance : startOffset)
        return try ExactLinearSectionSweepBodyBuilder(
            featureID: featureID, context: context, sewer: sewer
        ).buildTranslatedSheet(section: curve, startOffset: start, endOffset: start + axis * distance)
    }

    package func evaluateSheet(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try ExactProfileExtrudeBodyBuilder(
            featureID: featureID,
            context: context,
            sewer: sewer
        ).build(
            from: profile,
            direction: direction,
            distance: distance,
            bodyKind: .sheet,
            includesCaps: false
        )
    }

}
