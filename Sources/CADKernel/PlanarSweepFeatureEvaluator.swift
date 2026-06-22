import CADCore
import CADIR

public struct PlanarSweepFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let booleanEvaluator: BRepBooleanEvaluating
    private let makePathSampler: @Sendable (ModelingTolerance) -> any SweepPathSampling

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        extrudeEvaluator: PlanarExtrudeFeatureEvaluator? = nil,
        booleanEvaluator: BRepBooleanEvaluating = BoxBRepBooleanEvaluator(),
        pathSamplerFactory: @escaping @Sendable (ModelingTolerance) -> any SweepPathSampling = {
            SweepPathSampler(tolerance: $0)
        }
    ) {
        self.resolver = resolver
        self.extrudeEvaluator = extrudeEvaluator ?? PlanarExtrudeFeatureEvaluator(resolver: resolver)
        self.booleanEvaluator = booleanEvaluator
        self.makePathSampler = pathSamplerFactory
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .sweep(sweep) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarSweepFeatureEvaluator only supports sweep.")
        }
        try SweepEvaluationCapabilities().validate(sweep.options)
        let optionValues = try supportedSweepOptionValues(
            sweep,
            parameters: context.parameters,
            tolerance: context.tolerance
        )
        guard let profile = sweep.profiles.first else {
            throw FeatureEvaluationError.invalidGraph("Sweep features require at least one profile.")
        }
        guard let pathCurve = context.sketchCurves[sweep.path.featureID]?.onlyElement else {
            throw FeatureEvaluationError.unsupportedOperation("Sweep evaluation currently requires one path curve.")
        }
        guard let profileValue = context.profiles[profile.featureID]?[profile.profileIndex] else {
            throw FeatureEvaluationError.missingProfile(profile.featureID, profile.profileIndex)
        }
        let sectionTransform = SweepSectionTransform(
            twistAngle: optionValues.twistAngle,
            endScale: optionValues.endScale
        )
        if sweep.options.booleanOperation != .newBody,
           sweep.options.resultKind != .solid {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep boolean target operations require solid sweep output."
            )
        }
        let guideCurves = try sweep.guides.map { guide in
            guard let guideCurve = context.sketchCurves[guide.featureID]?.onlyElement else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep evaluation currently requires one curve per guide."
                )
            }
            return guideCurve
        }
        let sectionConstraintSolver: SweepSectionConstraintSolver?
        if guideCurves.isEmpty {
            sectionConstraintSolver = nil
        } else {
            sectionConstraintSolver = try SweepSectionConstraintSolver(
                method: sweep.options.guideMethod,
                guideCurves: guideCurves,
                distanceFraction: optionValues.distanceFraction,
                tolerance: context.tolerance
            )
        }
        let sampler = makePathSampler(context.tolerance)
        let frames = try sampler.frames(
            for: pathCurve,
            distanceFraction: optionValues.distanceFraction,
            preferredNormal: normal(for: profileValue.plane, tolerance: context.tolerance)
        )
        let toolResult: EvaluationResult
        let straightPath = try sampler.straightPath(from: frames)
        try SweepEvaluationCapabilities().validate(
            sweep.options,
            isStraightPath: straightPath != nil
        )
        guard let straightPath else {
            toolResult = try SweepCurvedPathSolidBuilder(tolerance: context.tolerance).build(
                profile: profileValue,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                resultKind: sweep.options.resultKind,
                featureID: feature.id,
                context: context
            )
            return try applyBooleanIfNeeded(
                sweep,
                featureID: feature.id,
                toolResult: toolResult,
                context: context
            )
        }

        guard sectionTransform.isIdentity(tolerance: context.tolerance),
              sectionConstraintSolver == nil else {
            toolResult = try SweepCurvedPathSolidBuilder(tolerance: context.tolerance).build(
                profile: profileValue,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                resultKind: sweep.options.resultKind,
                featureID: feature.id,
                context: context
            )
            return try applyBooleanIfNeeded(
                sweep,
                featureID: feature.id,
                toolResult: toolResult,
                context: context
            )
        }

        guard straightPath.distance > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(straightPath.distance)
        }

        if sweep.options.resultKind == .sheet {
            toolResult = try extrudeEvaluator.evaluateSheet(
                from: profileValue,
                featureID: feature.id,
                direction: .vector(straightPath.direction),
                distance: straightPath.distance,
                context: context
            )
            return try applyBooleanIfNeeded(
                sweep,
                featureID: feature.id,
                toolResult: toolResult,
                context: context
            )
        }

        let extrudeFeature = FeatureNode(
            id: feature.id,
            name: feature.name,
            operation: .extrude(ExtrudeFeature(
                profile: profile,
                distance: .constant(.length(straightPath.distance, unit: .meter)),
                direction: .vector(straightPath.direction),
                operation: .newBody
            )),
            inputs: feature.inputs,
            outputs: feature.outputs,
            isSuppressed: feature.isSuppressed
        )
        toolResult = try extrudeEvaluator.evaluate(feature: extrudeFeature, context: context)
        return try applyBooleanIfNeeded(
            sweep,
            featureID: feature.id,
            toolResult: toolResult,
            context: context
        )
    }

    private func supportedSweepOptionValues(
        _ sweep: SweepFeature,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> (twistAngle: Double, endScale: Double, distanceFraction: Double) {
        guard sweep.profiles.count == 1 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep evaluation currently supports exactly one profile."
            )
        }
        let twistAngle = try resolvedAngle(
            sweep.options.twistAngle,
            operation: "sweep.twistAngle",
            parameters: parameters
        )
        guard twistAngle.isFinite else {
            throw FeatureEvaluationError.invalidGraph("Sweep twist angle must be finite.")
        }

        let endScale = try resolvedScalar(
            sweep.options.endScale,
            operation: "sweep.endScale",
            parameters: parameters
        )
        guard endScale.isFinite,
              endScale > tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep end-scale collapses the profile before producing valid topology."
            )
        }

        let distanceFraction = try resolvedScalar(
            sweep.options.distanceFraction,
            operation: "sweep.distanceFraction",
            parameters: parameters
        )
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
        return (
            twistAngle: twistAngle,
            endScale: endScale,
            distanceFraction: distanceFraction
        )
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: quantity.kind)
        }
        return quantity.value
    }

    private func resolvedScalar(
        _ expression: CADExpression,
        operation: String,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard quantity.kind == .scalar else {
            throw UnitError.expectedQuantity(operation: operation, expected: .scalar, actual: quantity.kind)
        }
        return quantity.value
    }

    private func normal(for plane: SketchPlane, tolerance: ModelingTolerance) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }

    private func applyBooleanIfNeeded(
        _ sweep: SweepFeature,
        featureID: FeatureID,
        toolResult: EvaluationResult,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard sweep.options.booleanOperation != .newBody else {
            return toolResult
        }
        let toolBodyID = try bodyID(for: featureID, in: toolResult.generatedNames)
        let targetBodyIDs = try sweep.targets.map { target in
            try bodyID(for: target.featureID, in: context.generatedNames)
        }
        return try booleanEvaluator.evaluate(
            operation: sweep.options.booleanOperation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: sweep.options.keepTools,
            featureID: featureID,
            model: toolResult.brep,
            generatedNames: context.generatedNames,
            toolGeneratedNames: toolResult.generatedNames,
            tolerance: context.tolerance
        )
    }

    private func bodyID(
        for featureID: FeatureID,
        in generatedNames: [PersistentName: TopologyReference]
    ) throws -> BodyID {
        let name = PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])
        guard let reference = generatedNames[name] else {
            throw FeatureEvaluationError.missingInput("Sweep boolean target body could not be resolved.")
        }
        guard case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.invalidGraph("Sweep boolean target persistent name is not a body.")
        }
        return bodyID
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
