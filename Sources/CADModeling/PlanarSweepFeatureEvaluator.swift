import Foundation
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
        try sweep.validate()
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
        let section = try ResolvedModelingSection.resolve(sectionReference, context: context, featureID: feature.id)
        let preferredStartPlane = try ExactSweepSectionPlane(
            try section.plane(),
            tolerance: context.tolerance
        ).plane
        let chain = try EvaluatedCurveChainBuilder(tolerance: context.tolerance).connectedSegments(
            from: pathCurves,
            operationName: "Sweep path",
            preferredStartPlane: preferredStartPlane
        )
        // A path of straight arms with corners, open or closed, sweeps with mitred corners.
        if chain.segments.allSatisfy({ $0.curve.exactCurve != nil }) {
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance).pathSpans(
                from: chain.segments, allowsClosed: chain.isClosed
            )
            if MitredPolylineSweepBuilder.applies(sweep.options, pathSpans: spans, tolerance: context.tolerance) {
                let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: context.tolerance)
                let loops: [[ExactBSplineCurveSpan]]
                let closedSection: Bool
                switch section {
                case .profile(let profile, _):
                    loops = try spanBuilder.profileLoopSpans(from: profile)
                    closedSection = true
                case .curve(let curve):
                    loops = [try spanBuilder.sectionSpans(from: curve)]
                    closedSection = curve.isClosed
                }
                let mitred = try MitredPolylineSweepBuilder(tolerance: context.tolerance).request(
                    sectionLoops: loops, sectionIsClosed: closedSection, profilePlane: try section.plane(),
                    pathSpans: spans, pathIsClosed: chain.isClosed, options: sweep.options, values: optionValues,
                    featureID: feature.id
                )
                let tool = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
                    .buildMitred(mitred)
                return try applyBooleanIfNeeded(sweep, featureID: feature.id, toolResult: tool, context: context)
            }
        }
        guard chain.isClosed == false else {
            throw SketchError.unsupportedEntity("Sweep path requires an open curve chain.")
        }
        let pathSegments = chain.segments
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
        // A path-normal sweep along a curved path moves the section with the path's frame,
        // within the requested positional allowance.
        // Only an exact path has the spans the curved plan moves along; others keep their routes.
        let curvedPathSpans = pathSegments.allSatisfy({ $0.curve.exactCurve != nil })
            ? try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance).pathSpans(
                from: pathSegments, endingAt: optionValues.distanceFraction < 1 ? frames.last?.origin : nil
            )
            : []
        if curvedPathSpans.isEmpty == false, CertifiedCurvedPathSweepPlan.applies(
            sweep.options, pathSpans: curvedPathSpans,
            exactCircularSolid: exactCircularPath != nil && sweep.options.resultKind == .solid,
            tolerance: context.tolerance
        ) {
            let plan = try CertifiedCurvedPathSweepPlan(
                section: section, pathSpans: curvedPathSpans, sweep: sweep, values: optionValues,
                featureID: feature.id, tolerance: context.tolerance
            )
            let tool = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
                .buildCertifiedCurvedPath(plan, resultKind: sweep.options.resultKind)
            return try applyBooleanIfNeeded(sweep, featureID: feature.id, toolResult: tool, context: context)
        }
        if sweep.options.guideMethod == .chord, let guide = guideCurves.onlyElement {
            return try chordGuideSweep(sweep, feature: feature, section: section, pathSegments: pathSegments,
                                       frames: frames, guide: guide, values: optionValues, context: context)
        }
        if CertifiedTwistSweepPlan.requested(sweep.options) {
            let plan = try CertifiedTwistSweepPlan(section: section, pathSegments: pathSegments,
                sweep: sweep, values: optionValues, tolerance: context.tolerance)
            return try simplifiedIfRequested(sweep, featureID: feature.id, toolResult:
                ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
                    .buildCertifiedTwist(plan, resultKind: sweep.options.resultKind), context: context)
        }
        let toolResult: EvaluationResult
        let straightPathCandidate = try sampler.straightPath(from: frames)
        let baseSectionState = sectionTransform.state(
            tolerance: context.tolerance
        )
        var pointGuideEndTransform: ExactSectionTransform2D?
        let sectionState: SweepEvaluationCapabilities.SectionState
        if (1...2).contains(guideCurves.count),
           sweep.options.guideMethod == .point,
           baseSectionState == .identity,
           straightPathCandidate != nil,
           let pathStart = frames.first?.origin,
           let pathEnd = frames.last?.origin {
            pointGuideEndTransform = try exactPointGuideTransform(
                section: section,
                pathStart: pathStart,
                pathEnd: pathEnd,
                guides: guideCurves,
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
            guard case let .profile(profile, region) = section else {
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
                section: region,
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
            case .exactStraightExtrude, .exactCircularPathRevolve, .certifiedStraightTwist, .certifiedCurvedPathNormal,
                 .exactMitredPolylineSweep:
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
                section: try section.regionSection(),
                distance: .constant(.length(straightPath.distance, unit: .meter)),
                direction: .vector(straightPath.direction),
                operation: .newBody,
                resultKind: .solid
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

    private func buildExactLinearSectionSweep(
        section: ResolvedModelingSection,
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
        section: ResolvedModelingSection,
        pathStart: Point3D,
        pathEnd: Point3D,
        guides: [EvaluatedCurve],
        distanceFraction: Double,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> ExactSectionTransform2D {
        try ExactPointGuideSectionTransformResolver(tolerance: tolerance).resolve(
            section: section, pathStart: pathStart, pathEnd: pathEnd, guides: guides,
            distanceFraction: distanceFraction, featureID: featureID
        )
    }

    /// A Chord guide turns the section about a straight path so the direction from the path to the
    /// guide is kept, without scaling: with the point guide's end similarity `T` (the guide's end
    /// offset over its start offset, as complex numbers in the section's plane) the turn at a
    /// fraction `t` of the path is θ(t) = arg(1 + t(T − 1)). The certified twist sweeps a linear
    /// interpolation of θ at N nodes; |θ″| ≤ 2|T − 1|² / d³, d the least |1 + t(T − 1)|, bounds that
    /// interpolation's error by R·|θ″|/(8N²) for the section's reach R, kept within half the
    /// allowance, the twist's own approximation within the other half.
    private func chordGuideSweep(
        _ sweep: SweepFeature, feature: FeatureNode, section: ResolvedModelingSection,
        pathSegments: [EvaluatedCurvePathSegment], frames: [SweepPathFrame], guide: EvaluatedCurve,
        values: SweepOptionValues, context: EvaluationContext
    ) throws -> EvaluationResult {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
        }
        guard let allowance = values.approximationTolerance, allowance > 0 else {
            throw failure(.invalidInput, "A Chord-guided sweep needs a positional approximation allowance.")
        }
        guard values.twistAngle == 0, sweep.options.twistLaw == nil, values.endScale == 1 else {
            throw failure(.unsupportedCapability, "A Chord-guided sweep takes no twist or scale of its own.")
        }
        guard let start = frames.first?.origin, let end = frames.last?.origin else {
            throw failure(.invalidInput, "A Chord-guided sweep has no path.")
        }
        let transform = try exactPointGuideTransform(section: section, pathStart: start, pathEnd: end, guides: [guide],
            distanceFraction: values.distanceFraction, featureID: feature.id, tolerance: tolerance)
        // T as a complex number: the similarity's rotation-scale.
        let (re, im) = (transform.m11 - 1, transform.m21)
        let reach2 = re * re + im * im
        let nearest = reach2 > 0 ? min(1, max(0, -re / reach2)) : 0
        let least = hypot(1 + nearest * re, nearest * im)
        guard least > tolerance.relative else {
            throw failure(.sweepGuideTransformCollapse, "A Chord guide passes through the path's axis.")
        }
        let axis = try (end - start).normalized(tolerance: tolerance.distance)
        // The section's reach about the path: its control points bound every point of it.
        let sectionPoints: [Point3D]
        switch section {
        case .profile(let profile, _):
            sectionPoints = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).profileLoopSpans(from: profile)
                .flatMap { $0.flatMap(\.curve.controlPoints) }
        case .curve(let curve):
            sectionPoints = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: curve).flatMap(\.curve.controlPoints)
        }
        let radius = sectionPoints.reduce(0.0) { result, point in
            let offset = point - start
            return max(result, (offset - axis * offset.dot(axis)).length)
        } * 1.01
        let curvature = 2 * reach2 / (least * least * least)
        let nodeCount = max(1, Int((radius * curvature / (4 * allowance)).squareRoot().rounded(.up)))
        guard nodeCount <= 4096 else {
            throw failure(.resourceLimitExceeded, "A Chord guide turns too sharply for its allowance.")
        }
        var positions: [Double] = []
        var angles: [Double] = []
        for k in 0...nodeCount {
            let t = Double(k) / Double(nodeCount)
            var angle: Double = atan2(t * im, 1 + t * re)
            if let last = angles.last {
                let turns: Double = ((last - angle) / (2 * Double.pi)).rounded()
                angle += turns * 2 * Double.pi
            }
            positions.append(t)
            angles.append(angle)
        }
        var turned = values
        turned.approximationTolerance = allowance / 2
        turned.twistPositions = positions
        turned.twistAngles = angles
        turned.twistAngle = angles[angles.count - 1]
        var unguided = sweep
        unguided.guides = []
        unguided.options.guideMethod = .point
        let plan = try CertifiedTwistSweepPlan(section: section, pathSegments: pathSegments, sweep: unguided,
                                               values: turned, tolerance: tolerance)
        let tool = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
            .buildCertifiedTwist(plan, resultKind: sweep.options.resultKind)
        return try applyBooleanIfNeeded(sweep, featureID: feature.id, toolResult: tool, context: context)
    }

    /// The swept body with its flat faces made trimmed planes when the sweep simplifies.
    private func simplifiedIfRequested(
        _ sweep: SweepFeature,
        featureID: FeatureID,
        toolResult: EvaluationResult,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard sweep.options.simplify else { return toolResult }
        return try PlanarFaceSimplifier(tolerance: context.tolerance)
            .simplified(toolResult, bodyID: try bodyID(for: featureID, in: toolResult.subshapes))
    }

    private func applyBooleanIfNeeded(
        _ sweep: SweepFeature,
        featureID: FeatureID,
        toolResult unsimplified: EvaluationResult,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let toolResult = try simplifiedIfRequested(sweep, featureID: featureID, toolResult: unsimplified, context: context)
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

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
