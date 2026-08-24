import CADCore
import CADIR

public struct PlanarSweepFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let optionValueResolver: SweepOptionValueResolver
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let revolveEvaluator: PlanarRevolveFeatureEvaluator
    private let booleanApplicator: (any SweepBooleanApplying)?
    private let makePathSampler: @Sendable (ModelingTolerance) -> any SweepPathSampling
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        extrudeEvaluator: PlanarExtrudeFeatureEvaluator? = nil,
        revolveEvaluator: PlanarRevolveFeatureEvaluator? = nil,
        booleanApplicator: (any SweepBooleanApplying)? = nil,
        pathSamplerFactory: @escaping @Sendable (ModelingTolerance) -> any SweepPathSampling = {
            SweepPathSampler(tolerance: $0)
        }
    ) {
        self.resolver = resolver
        self.optionValueResolver = SweepOptionValueResolver(resolver: resolver)
        self.extrudeEvaluator = extrudeEvaluator ?? PlanarExtrudeFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.revolveEvaluator = revolveEvaluator ?? PlanarRevolveFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.booleanApplicator = booleanApplicator
        self.makePathSampler = pathSamplerFactory
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .sweep(sweep) = feature.operation else {
            throw FeatureEvaluationError.invalidGraph(
                "PlanarSweepFeatureEvaluator received a non-sweep feature."
            )
        }
        let capabilities = SweepEvaluationCapabilities()
        try capabilities.validateStaticOptions(
            sweep.options,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let optionValues = try optionValueResolver.values(
            for: sweep,
            parameters: context.parameters,
            tolerance: context.tolerance
        )
        guard let sectionReference = sweep.sections.first else {
            throw FeatureEvaluationError.invalidGraph("Sweep features require at least one section.")
        }
        guard let pathCurves = context.curves[sweep.path.featureID] else {
            throw FeatureEvaluationError.missingInput(
                "Sweep evaluation requires a path curve feature."
            )
        }
        if pathCurves.count > 1, sweep.options.cornerStyle == .round {
            throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                "Round sweep corner style requires curved corner-transition topology for multi-curve paths."
            )
        }
        let section = try resolvedSection(sectionReference, context: context)
        let preferredStartPlane = try ExactSweepSectionPlane(
            try section.plane(),
            tolerance: context.tolerance
        ).plane
        let pathSegments = try EvaluatedCurveChainBuilder(tolerance: context.tolerance).openSegments(
            from: pathCurves,
            operationName: "Sweep path",
            preferredStartPlane: preferredStartPlane
        )
        let exactCircularPath = try ExactCircularSweepPath(
            segments: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            tolerance: context.tolerance
        )
        let sectionTransform = SweepSectionTransform(
            twistAngle: optionValues.twistAngle,
            endScale: optionValues.endScale
        )
        let guideCurves = try sweep.guides.map { guide in
            guard let guideCurve = context.curves[guide.featureID]?.onlyElement else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                    "Sweep evaluation currently requires one curve per guide."
                )
            }
            return guideCurve
        }
        let sampler = makePathSampler(context.tolerance)
        let frames = try sampler.frames(
            for: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            preferredNormal: normal(for: try section.plane(), tolerance: context.tolerance)
        )
        let toolResult: EvaluationResult
        let straightPathCandidate = try sampler.straightPath(from: frames)
        let baseSectionState = sectionTransform.state(
            tolerance: context.tolerance
        )
        var pointGuideEndTransform: ExactSectionTransform2D?
        let sectionState: SweepEvaluationCapabilities.SectionState
        if guideCurves.count == 1,
           sweep.options.guideMethod == .point,
           baseSectionState == .identity,
           straightPathCandidate != nil,
           let pathStart = frames.first?.origin,
           let pathEnd = frames.last?.origin,
           let guide = guideCurves.first {
            pointGuideEndTransform = try exactPointGuideTransform(
                section: section,
                pathStart: pathStart,
                pathEnd: pathEnd,
                guide: guide,
                distanceFraction: optionValues.distanceFraction,
                featureID: feature.id,
                tolerance: context.tolerance
            )
            sectionState = .pointGuide
        } else if guideCurves.isEmpty == false {
            sectionState = .guided
        } else {
            sectionState = baseSectionState
        }
        let capabilityGeometry: SweepEvaluationCapabilities.Geometry
        if let straightPath = straightPathCandidate {
            capabilityGeometry = SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(
                    profileNormalComponent: try profileNormalComponent(
                        of: straightPath.direction,
                        for: try section.plane(),
                        tolerance: context.tolerance
                    )
                ),
                sectionState: sectionState,
                guideConstraintCount: guideCurves.count,
                tolerance: context.tolerance
            )
        } else if exactCircularPath != nil {
            capabilityGeometry = SweepEvaluationCapabilities.Geometry(
                pathShape: .circularArc,
                sectionState: sectionState,
                guideConstraintCount: guideCurves.count,
                tolerance: context.tolerance
            )
        } else {
            capabilityGeometry = SweepEvaluationCapabilities.Geometry(
                pathShape: .curved,
                sectionState: sectionState,
                guideConstraintCount: guideCurves.count,
                tolerance: context.tolerance
            )
        }
        let supportedPlan = try capabilities.supportedPlan(
            sweep.options,
            geometry: capabilityGeometry,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        if supportedPlan.kind == .exactCircularPathRevolve {
            guard let exactCircularPath else {
                throw KernelError(
                    phase: .evaluation,
                    code: .sweepPathNormalUnavailable,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "Sweep capability planning selected exact circular evaluation without circular path geometry."
                )
            }
            guard case let .profile(profile, profileReference) = section else {
                throw KernelError(
                    phase: .evaluation,
                    code: .sweepPathNormalUnavailable,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "Exact circular path-normal Sweep requires a closed profile section."
                )
            }
            toolResult = try ExactCircularPathNormalSweepBuilder(
                featureID: feature.id,
                context: context,
                revolveEvaluator: revolveEvaluator
            ).build(
                profile: profile,
                profileReference: profileReference,
                path: exactCircularPath
            )
            return try applyBooleanIfNeeded(
                sweep,
                featureID: feature.id,
                toolResult: toolResult,
                context: context
            )
        }
        guard let straightPath = straightPathCandidate else {
            guard supportedPlan.kind == .exactTranslationalSweep,
                  let pathEndPoint = frames.last?.origin else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "Sweep capability planning did not produce an exact curved-path evaluator."
                )
            }
            toolResult = try buildExactLinearSectionSweep(
                section: section,
                pathSegments: pathSegments,
                pathEndPoint: pathEndPoint,
                resultKind: sweep.options.resultKind,
                endTransform: .identity,
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

        guard supportedPlan.kind == .exactStraightExtrude else {
            guard supportedPlan.kind == .exactTranslationalSweep
                    || supportedPlan.kind == .exactLinearScaleSweep
                    || supportedPlan.kind == .exactPointGuideSweep,
                  let pathEndPoint = frames.last?.origin else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "Sweep capability planning did not produce an exact straight-path evaluator."
                )
            }
            let endTransform: ExactSectionTransform2D
            switch supportedPlan.kind {
            case .exactLinearScaleSweep:
                endTransform = .uniformScale(optionValues.endScale)
            case .exactPointGuideSweep:
                guard let pointGuideEndTransform else {
                    throw KernelError(
                        phase: .evaluation,
                        code: .sweepGuideConstraintUnavailable,
                        featureID: feature.id,
                        tolerance: context.tolerance,
                        message: "Sweep planning selected exact point-guide evaluation without a resolved guide transform."
                    )
                }
                endTransform = pointGuideEndTransform
            case .exactTranslationalSweep:
                endTransform = .identity
            case .exactStraightExtrude, .exactCircularPathRevolve:
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "Sweep planning selected an incompatible linear-section evaluation kind."
                )
            }
            toolResult = try buildExactLinearSectionSweep(
                section: section,
                pathSegments: pathSegments,
                pathEndPoint: pathEndPoint,
                resultKind: sweep.options.resultKind,
                endTransform: endTransform,
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
            switch section {
            case .profile(let profile, _):
                toolResult = try extrudeEvaluator.evaluateSheet(
                    from: profile,
                    featureID: feature.id,
                    direction: .vector(straightPath.direction),
                    distance: straightPath.distance,
                    context: context
                )
            case .curve:
                guard let pathEndPoint = frames.last?.origin else {
                    throw FeatureEvaluationError.emptyResult(
                        "Exact straight sweep has no terminal path frame."
                    )
                }
                toolResult = try buildExactLinearSectionSweep(
                    section: section,
                    pathSegments: pathSegments,
                    pathEndPoint: pathEndPoint,
                    resultKind: sweep.options.resultKind,
                    endTransform: .identity,
                    featureID: feature.id,
                    context: context
                )
            }
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
                profile: try section.profileReference(),
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

    private func resolvedSection(
        _ section: SweepSectionReference,
        context: EvaluationContext
    ) throws -> ResolvedSweepSection {
        switch section {
        case .profile(let profileReference):
            guard let profile = context.profiles[profileReference.featureID]?[profileReference.profileIndex] else {
                throw FeatureEvaluationError.missingProfile(
                    profileReference.featureID,
                    profileReference.profileIndex
                )
            }
            return .profile(profile, profileReference)
        case .curve(let curveReference):
            guard let curve = context.curves[curveReference.featureID]?.onlyElement else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                    "Sweep curve section currently requires one curve from the section feature."
                )
            }
            guard curve.plane != nil else {
                throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                    "Sweep curve section requires source curve plane metadata."
                )
            }
            return .curve(curve)
        }
    }

    private func buildExactLinearSectionSweep(
        section: ResolvedSweepSection,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D,
        resultKind: SweepResultKind,
        endTransform: ExactSectionTransform2D,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let builder = ExactLinearSectionSweepBodyBuilder(
            featureID: featureID,
            context: context,
            sewer: sewer
        )
        switch section {
        case .profile(let profile, _):
            return try builder.build(
                profile: profile,
                pathSegments: pathSegments,
                pathEndPoint: pathEndPoint,
                resultKind: resultKind,
                endTransform: endTransform
            )
        case .curve(let curve):
            guard resultKind == .sheet else {
                throw FeatureEvaluationError.invalidGraph("Curve-section sweeps can only produce sheet output.")
            }
            return try builder.buildSheet(
                section: curve,
                pathSegments: pathSegments,
                pathEndPoint: pathEndPoint,
                endTransform: endTransform
            )
        }
    }

    private func profileNormalComponent(
        of direction: Vector3D,
        for plane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let profileNormal = try normal(for: plane, tolerance: tolerance)
        return abs(direction.dot(profileNormal))
    }

    private func exactPointGuideTransform(
        section: ResolvedSweepSection,
        pathStart: Point3D,
        pathEnd: Point3D,
        guide: EvaluatedCurve,
        distanceFraction: Double,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> ExactSectionTransform2D {
        let resolver = ExactPointGuideSectionTransformResolver(
            tolerance: tolerance
        )
        switch section {
        case .profile(let profile, _):
            return try resolver.resolve(
                profile: profile,
                pathStart: pathStart,
                pathEnd: pathEnd,
                guide: guide,
                distanceFraction: distanceFraction,
                featureID: featureID
            )
        case .curve(let curve):
            return try resolver.resolve(
                section: curve,
                pathStart: pathStart,
                pathEnd: pathEnd,
                guide: guide,
                distanceFraction: distanceFraction,
                featureID: featureID
            )
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
        guard let booleanApplicator else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Sweep Boolean evaluation requires a SweepBooleanApplying implementation."
            )
        }
        let toolBodyID = try bodyID(for: featureID, in: toolResult.subshapes)
        let targetBodyIDs = try sweep.targets.map { target in
            try context.bodyID(generatedBy: target.featureID)
        }
        return try booleanApplicator.apply(
            operation: sweep.options.booleanOperation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: sweep.options.keepTools,
            featureID: featureID,
            toolResult: toolResult,
            targetSubshapes: context.subshapes.entries,
            inputLineage: context.lineage,
            tolerance: context.tolerance
        )
    }

    private func bodyID(
        for featureID: FeatureID,
        in subshapes: [SubshapeID: TopologyReference]
    ) throws -> BodyID {
        let subshapeID = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        guard let reference = subshapes[subshapeID] else {
            throw FeatureEvaluationError.missingInput("Sweep boolean target body could not be resolved.")
        }
        guard case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.invalidGraph("Sweep boolean target subshape is not a body.")
        }
        return bodyID
    }
}

private enum ResolvedSweepSection {
    case profile(Profile, ProfileReference)
    case curve(EvaluatedCurve)

    func plane() throws -> SketchPlane {
        switch self {
        case .profile(let profile, _):
            return profile.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                throw FeatureEvaluationError.invalidGraph(
                    "Resolved sweep curve sections must carry plane metadata."
                )
            }
            return plane
        }
    }

    func profileReference() throws -> ProfileReference {
        switch self {
        case .profile(_, let profileReference):
            return profileReference
        case .curve:
            throw FeatureEvaluationError.invalidGraph("Curve-section sweeps cannot be evaluated as solid extrusions.")
        }
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
