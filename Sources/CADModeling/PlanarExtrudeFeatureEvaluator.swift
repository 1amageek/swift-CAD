import Foundation
import CADCore
import CADGeometry
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing
    private let booleanApplicator: (any SweepBooleanApplying)?
    private let targetRelocator: (any ExactBodyPatternRebuilding)?

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: (any SweepBooleanApplying)? = nil
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = nil
    }

    /// An evaluator that also moves placed Boolean targets into the extrusion's frame with
    /// `targetRelocator`, as a Boolean moves its placed operands.
    package init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        booleanApplicator: any SweepBooleanApplying,
        targetRelocator: any ExactBodyPatternRebuilding
    ) {
        self.resolver = resolver
        self.sewer = sewer
        self.booleanApplicator = booleanApplicator
        self.targetRelocator = targetRelocator
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
        try extrude.validate()
        let range = try extrude.resolvedAxialRange(tolerance: context.tolerance) {
            try resolver.evaluate($0, parameters: context.parameters, variables: [:])
        }
        let span = range.upperBound - range.lowerBound
        var draftTangent = 0.0
        if let draftAngle = extrude.draftAngle {
            let quantity = try resolver.evaluate(draftAngle, parameters: context.parameters, variables: [:])
            guard quantity.kind == .angle, quantity.value.isFinite, abs(quantity.value) < Double.pi / 2 - context.tolerance.angle else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                                  message: "An extrusion's draft is an angle under 90 degrees.")
            }
            draftTangent = abs(quantity.value) > context.tolerance.angle ? tan(quantity.value) : 0
        }
        // A placed Boolean target moves into the extrusion's frame first, as a staged body, the
        // way a Boolean moves its placed operands; the tool is built beside it.
        var stages = FeatureEvaluationStages(context)
        var targetBodyIDs: [BodyID] = []
        if extrude.operation != .newBody {
            for (ordinal, target) in extrude.targets.enumerated() {
                let bodyID = try context.bodyID(generatedBy: target.featureID)
                guard let placement = target.placement else {
                    targetBodyIDs.append(bodyID)
                    continue
                }
                guard let targetRelocator else {
                    throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: feature.id,
                                      tolerance: context.tolerance, message: "This evaluator cannot move a placed extrusion target.")
                }
                try placement.validate(tolerance: context.tolerance)
                let stageID = featureEvaluationStageID(featureID: feature.id, domain: .booleanOperandPlacement, ordinal: UInt64(ordinal))
                let staged = stages.context
                let moved = try FeatureEvaluationBoundary.evaluate(featureID: feature.id, tolerance: context.tolerance) {
                    try targetRelocator.relocate(
                        featureID: stageID, sourceBodyID: bodyID, transform: placement,
                        stablePrefix: "extrude:placedTarget", context: staged
                    )
                }
                stages.apply(moved)
                targetBodyIDs.append(try stages.publishedBody(of: moved, featureID: feature.id, what: "Moving an extrusion target"))
            }
        }
        let context = stages.context
        var result: EvaluationResult
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
                includesCaps: extrude.resultKind == .solid,
                draftTangent: draftTangent
            )
        case .curve(let reference):
            guard draftTangent == 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a curve extrusion is refused a draft.
                // Production path: PlanarExtrudeFeatureEvaluator for every curve extrude with a
                // draft angle. Complete only when a drafted curve sheet leans by the angle, verified
                // by its wall normals.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, featureID: feature.id,
                                  tolerance: context.tolerance, message: "A drafted extrusion drafts a closed section.")
            }
            let curve = try ResolvedModelingSection.resolveCurve(
                reference, from: context.curves[reference.featureID], tolerance: context.tolerance
            )
            result = try evaluateCurveSheet(
                curve, featureID: feature.id, direction: extrude.direction,
                distance: span, startOffset: range.lowerBound, context: context
            )
        }
        if extrude.operation != .newBody {
            guard let booleanApplicator,
                  let operation = SweepBooleanOperation(rawValue: extrude.operation.rawValue) else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance,
                    message: "Extrusion Boolean evaluation requires a Boolean applicator.")
            }
            let toolReference = SubshapeID(featureID: feature.id,
                role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)
            guard case let .body(toolID) = result.subshapes[toolReference] else {
                throw FeatureEvaluationError.missingInput("Extrusion tool body was not generated.")
            }
            result = try booleanApplicator.apply(operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolID, keepTools: extrude.keepTools, featureID: feature.id,
                toolResult: result, targetSubshapes: context.subshapes.entries,
                inputLineage: context.lineage, tolerance: context.tolerance)
            if stages.isEmpty == false {
                result = try stages.publish(result, featureID: feature.id)
            }
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
