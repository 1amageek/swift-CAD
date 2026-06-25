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
        let capabilities = SweepEvaluationCapabilities()
        try capabilities.validateStaticOptions(sweep.options)
        let optionValues = try supportedSweepOptionValues(
            sweep,
            parameters: context.parameters,
            tolerance: context.tolerance
        )
        guard let sectionReference = sweep.sections.first else {
            throw FeatureEvaluationError.invalidGraph("Sweep features require at least one section.")
        }
        guard let pathCurves = context.curves[sweep.path.featureID] else {
            throw FeatureEvaluationError.unsupportedOperation("Sweep evaluation requires a path curve feature.")
        }
        if pathCurves.count > 1, sweep.options.cornerStyle == .round {
            throw FeatureEvaluationError.unsupportedOperation(
                "Round sweep corner style requires curved corner-transition topology for multi-curve paths."
            )
        }
        let pathSegments = try EvaluatedCurveChainBuilder(tolerance: context.tolerance).openSegments(
            from: pathCurves,
            operationName: "Sweep path"
        )
        let section = try resolvedSection(sectionReference, context: context)
        let sectionTransform = SweepSectionTransform(
            twistAngle: optionValues.twistAngle,
            endScale: optionValues.endScale
        )
        let guideCurves = try sweep.guides.map { guide in
            guard let guideCurve = context.curves[guide.featureID]?.onlyElement else {
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
            for: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            preferredNormal: normal(for: section.plane, tolerance: context.tolerance)
        )
        let toolResult: EvaluationResult
        let straightPathCandidate = try sampler.straightPath(from: frames)
        let sectionState: SweepEvaluationCapabilities.SectionState
        if sectionConstraintSolver != nil {
            sectionState = .guided
        } else if sectionTransform.isIdentity(tolerance: context.tolerance) {
            sectionState = .identity
        } else {
            sectionState = .transformed
        }
        let capabilityGeometry: SweepEvaluationCapabilities.Geometry
        if let straightPath = straightPathCandidate {
            capabilityGeometry = SweepEvaluationCapabilities.Geometry(
                pathShape: .straight(
                    profileNormalComponent: try profileNormalComponent(
                        of: straightPath.direction,
                        for: section.plane,
                        tolerance: context.tolerance
                    )
                ),
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
            geometry: capabilityGeometry
        )
        guard let straightPath = straightPathCandidate else {
            if supportedPlan.kind == .profilePlaneParallelSweep {
                toolResult = try buildProfilePlaneParallelSweep(
                    section: section,
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
            toolResult = try buildPathNormalSweep(
                section: section,
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

        guard supportedPlan.kind == .exactStraightExtrude else {
            if supportedPlan.kind == .profilePlaneParallelSweep {
                toolResult = try buildProfilePlaneParallelSweep(
                    section: section,
                    frames: frames,
                    sectionTransform: sectionTransform,
                    sectionConstraintSolver: sectionConstraintSolver,
                    resultKind: sweep.options.resultKind,
                    featureID: feature.id,
                    context: context
                )
            } else {
                toolResult = try buildPathNormalSweep(
                    section: section,
                    frames: frames,
                    sectionTransform: sectionTransform,
                    sectionConstraintSolver: sectionConstraintSolver,
                    resultKind: sweep.options.resultKind,
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
                toolResult = try buildPathNormalSweep(
                    section: section,
                    frames: frames,
                    sectionTransform: sectionTransform,
                    sectionConstraintSolver: sectionConstraintSolver,
                    resultKind: sweep.options.resultKind,
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

    private func supportedSweepOptionValues(
        _ sweep: SweepFeature,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> (twistAngle: Double, endScale: Double, distanceFraction: Double) {
        guard sweep.sections.count == 1 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep evaluation currently supports exactly one section."
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
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep curve section currently requires one curve from the section feature."
                )
            }
            guard curve.plane != nil else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep curve section requires source curve plane metadata."
                )
            }
            return .curve(curve)
        }
    }

    private func buildPathNormalSweep(
        section: ResolvedSweepSection,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform,
        sectionConstraintSolver: SweepSectionConstraintSolver?,
        resultKind: SweepResultKind,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let builder = SweepCurvedPathSolidBuilder(tolerance: context.tolerance)
        switch section {
        case .profile(let profile, _):
            return try builder.build(
                profile: profile,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                resultKind: resultKind,
                featureID: featureID,
                context: context
            )
        case .curve(let curve):
            guard resultKind == .sheet else {
                throw FeatureEvaluationError.invalidGraph("Curve-section sweeps can only produce sheet output.")
            }
            return try builder.buildSheet(
                curve: curve,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                featureID: featureID,
                context: context
            )
        }
    }

    private func buildProfilePlaneParallelSweep(
        section: ResolvedSweepSection,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform,
        sectionConstraintSolver: SweepSectionConstraintSolver?,
        resultKind: SweepResultKind,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let builder = SweepCurvedPathSolidBuilder(tolerance: context.tolerance)
        switch section {
        case .profile(let profile, _):
            return try builder.buildProfilePlaneParallel(
                profile: profile,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                resultKind: resultKind,
                featureID: featureID,
                context: context
            )
        case .curve(let curve):
            guard resultKind == .sheet else {
                throw FeatureEvaluationError.invalidGraph("Curve-section sweeps can only produce sheet output.")
            }
            return try builder.buildProfilePlaneParallelSheet(
                curve: curve,
                frames: frames,
                sectionTransform: sectionTransform,
                sectionConstraintSolver: sectionConstraintSolver,
                featureID: featureID,
                context: context
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

private enum ResolvedSweepSection {
    case profile(Profile, ProfileReference)
    case curve(EvaluatedCurve)

    var plane: SketchPlane {
        switch self {
        case .profile(let profile, _):
            return profile.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                preconditionFailure("Resolved sweep curve sections must carry plane metadata.")
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
