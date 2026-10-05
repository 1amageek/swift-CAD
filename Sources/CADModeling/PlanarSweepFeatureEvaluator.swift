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
        // A path with corners, open or closed, sweeps with mitred or round corners.
        if chain.segments.allSatisfy({ $0.curve.exactCurve != nil }) {
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance).pathSpans(
                from: chain.segments, allowsClosed: chain.isClosed
            )
            if try MitredPolylineSweepBuilder.applies(sweep.options, pathSpans: spans, tolerance: context.tolerance) {
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
                    pathSpans: spans, pathIsClosed: chain.isClosed, sweep: sweep, values: optionValues,
                    featureID: feature.id
                )
                let tool = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
                    .buildMitred(mitred)
                return try applyBooleanIfNeeded(sweep, featureID: feature.id, toolResult: tool, context: context)
            }
        }
        // A smooth closed path, the section moved round it with the path's frame and closing on
        // itself.
        if chain.isClosed, chain.segments.allSatisfy({ $0.curve.exactCurve != nil }), sweep.options.alignment == .normal,
           optionValues.distanceFraction == 1 {
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance).pathSpans(from: chain.segments, allowsClosed: true)
            let plan = try CertifiedCurvedPathSweepPlan.closed(
                section: section, pathSpans: spans, sweep: sweep, values: optionValues, featureID: feature.id, tolerance: context.tolerance
            )
            let tool = try ExactLinearSectionSweepBodyBuilder(featureID: feature.id, context: context, sewer: sewer)
                .buildCertifiedCurvedPath(plan, resultKind: sweep.options.resultKind)
            return try applyBooleanIfNeeded(sweep, featureID: feature.id, toolResult: tool, context: context)
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
            // One guide steers the section along the curved path by its method; two Point guides
            // deform it between them.
            let spanned = try guideCurves.prefix(2).map {
                try ExactBSplineCurveSpanBuilder(tolerance: context.tolerance).sectionSpans(from: $0).map(\.curve)
            }
            let plan = try CertifiedCurvedPathSweepPlan(
                section: section, pathSpans: curvedPathSpans, sweep: sweep, values: optionValues,
                guide: guideCurves.count <= 2 ? spanned.first : nil, secondGuide: guideCurves.count == 2 ? spanned.last : nil,
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
        if sweep.options.guideMethod == .curve, let guide = guideCurves.onlyElement {
            return try curveGuideSweep(sweep, feature: feature, section: section, pathSegments: pathSegments,
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

    /// A Curve guide (Plasticity's Curve method) turns the section about a straight path, unscaled,
    /// so it touches both: the path at its fixed point of the section, the guide wherever on the
    /// section that is. At the fraction t of the path the guide crosses the station's plane at the
    /// offset g(t) from the path; the section's point q(t) as far from the path as that, continued
    /// from the guide's start on the section, is turned onto it: θ(t) = arg g(t) − arg q(t). The
    /// certified twist sweeps a linear interpolation of θ on nodes refined until it keeps within a
    /// quarter of the allowance at the section's radius, the twist's own approximation within half.
    private func curveGuideSweep(
        _ sweep: SweepFeature, feature: FeatureNode, section: ResolvedModelingSection,
        pathSegments: [EvaluatedCurvePathSegment], frames: [SweepPathFrame], guide: EvaluatedCurve,
        values: SweepOptionValues, context: EvaluationContext
    ) throws -> EvaluationResult {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
        }
        guard let allowance = values.approximationTolerance, allowance > 0 else {
            throw failure(.invalidInput, "A Curve-guided sweep needs a positional approximation allowance.")
        }
        guard values.twistAngle == 0, sweep.options.twistLaw == nil, values.endScale == 1 else {
            throw failure(.unsupportedCapability, "A Curve-guided sweep takes no twist or scale of its own.")
        }
        guard let start = frames.first?.origin, let end = frames.last?.origin else {
            throw failure(.invalidInput, "A Curve-guided sweep has no path.")
        }
        let axis = try (end - start).normalized(tolerance: tolerance.distance)
        let length = (end - start).length
        // The guide runs monotonically along the path from the section's plane past the path's
        // end, so each station's plane crosses it once: its control points advance along the
        // axis (a B-spline lies in its control points' hull, so the curve advances with them).
        let guideSpans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: guide).map(\.curve)
        func advance(_ point: Point3D) -> Double { (point - start).dot(axis) }
        let guidePoints = guideSpans.flatMap(\.controlPoints)
        guard let firstGuidePoint = guidePoints.first, let lastGuidePoint = guidePoints.last else {
            throw failure(.invalidInput, "A Curve-guided sweep has no guide.")
        }
        let direction: Double = advance(lastGuidePoint) >= advance(firstGuidePoint) ? 1 : -1
        let advances = guidePoints.map { advance($0) * direction }
        guard zip(advances, advances.dropFirst()).allSatisfy({ $1 >= $0 - tolerance.distance }) else {
            throw failure(.sweepGuideConstraintUnavailable, "A Curve guide must advance along the path without turning back.")
        }
        let contact = direction > 0 ? firstGuidePoint : lastGuidePoint
        guard abs(advance(contact)) <= tolerance.distance, max(advance(firstGuidePoint), advance(lastGuidePoint)) >= length - tolerance.distance else {
            throw failure(.sweepGuideContactUnavailable, "A Curve guide must run from the section's plane to the path's end.")
        }
        // The guide's offset from the path at the fraction t of the path: where the station's
        // plane crosses it, by bisection on the span whose ends bracket the station.
        func guideOffset(at t: Double) throws -> Vector3D {
            let station = t * length
            for span in guideSpans {
                guard case let .closed(lower, upper) = span.domain else { continue }
                let curve = Curve3D.bSpline(span)
                let (a, b) = (advance(try curve.point(at: lower, tolerance: tolerance)), advance(try curve.point(at: upper, tolerance: tolerance)))
                guard min(a, b) - tolerance.distance <= station, station <= max(a, b) + tolerance.distance else { continue }
                var (low, high) = a <= b ? (lower, upper) : (upper, lower)
                for _ in 0..<64 {
                    let middle = 0.5 * (low + high)
                    if advance(try curve.point(at: middle, tolerance: tolerance)) < station { low = middle } else { high = middle }
                }
                let point = try curve.point(at: 0.5 * (low + high), tolerance: tolerance)
                return point - (start + axis * station)
            }
            throw failure(.sweepGuideContactUnavailable, "A Curve guide does not reach a station of the path.")
        }
        let g0 = contact - start
        let e1 = try g0.normalized(tolerance: tolerance.distance)
        let e2 = axis.cross(e1)
        let spans: [BSplineCurve3D]
        switch section {
        case .profile(let profile, _):
            spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).profileLoopSpans(from: profile).flatMap { $0.map(\.curve) }
        case .curve(let curve):
            spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: curve).map(\.curve)
        }
        // The path touches the section: its start lies on the section's boundary.
        func distance(from point: Point3D, to span: BSplineCurve3D) throws -> Double {
            guard case let .closed(lower, upper) = span.domain else { return .infinity }
            let curve = Curve3D.bSpline(span)
            func at(_ s: Double) throws -> Double { (try curve.point(at: s, tolerance: tolerance) - point).length }
            var best = (s: lower, d: try at(lower))
            for k in 1...64 {
                let s = lower + (upper - lower) * Double(k) / 64
                let d = try at(s)
                if d < best.d { best = (s, d) }
            }
            var (a, b) = (max(lower, best.s - (upper - lower) / 64), min(upper, best.s + (upper - lower) / 64))
            let ratio = (5.0.squareRoot() - 1) / 2
            for _ in 0..<80 {
                let (c, d) = (b - ratio * (b - a), a + ratio * (b - a))
                if try at(c) < at(d) { b = d } else { a = c }
            }
            return min(best.d, try at(0.5 * (a + b)))
        }
        let touches = try spans.contains { try distance(from: start, to: $0) <= tolerance.distance }
        guard touches else {
            throw failure(.invalidInput, "A Curve guide's path must touch the section, which turns about that point.")
        }
        let radius = spans.flatMap(\.controlPoints).reduce(0.0) { max($0, ($1 - start).length) } * 1.01
        guard try spans.contains(where: { try distance(from: contact, to: $0) <= tolerance.distance }) else {
            throw failure(.invalidInput, "A Curve guide must start on the section's boundary.")
        }
        // The section's points as far from the path as `distance`, nearest `previous`: sign changes
        // of |C(s) − start| − distance between 64 samples per span, with each sampled minimum
        // refined by golden section first, so two roots closing in on a minimum (where the
        // section's boundary turns tangent to the circle) are both bracketed.
        func reaching(_ distance: Double, near previous: Point3D) throws -> Point3D? {
            var best: Point3D?
            let ratio = (5.0.squareRoot() - 1) / 2
            for span in spans {
                guard case let .closed(lower, upper) = span.domain else { continue }
                let curve = Curve3D.bSpline(span)
                func f(_ s: Double) throws -> Double { (try curve.point(at: s, tolerance: tolerance) - start).length - distance }
                var samples = try (0...64).map { k -> (s: Double, f: Double) in
                    let s = lower + (upper - lower) * Double(k) / 64
                    return (s, try f(s))
                }
                var refined: [(s: Double, f: Double)] = [samples[0]]
                for k in 1..<samples.count {
                    if k + 1 < samples.count, samples[k].f <= samples[k - 1].f, samples[k].f <= samples[k + 1].f, samples[k].f > 0 {
                        var (a, b) = (samples[k - 1].s, samples[k + 1].s)
                        for _ in 0..<80 {
                            let (c, d) = (b - ratio * (b - a), a + ratio * (b - a))
                            if try f(c) < f(d) { b = d } else { a = c }
                        }
                        let middle = 0.5 * (a + b)
                        let value = try f(middle)
                        if value < samples[k].f {
                            if middle < samples[k].s { refined.append((middle, value)); refined.append(samples[k]) }
                            else { refined.append(samples[k]); refined.append((middle, value)) }
                            continue
                        }
                    }
                    refined.append(samples[k])
                }
                samples = refined
                for k in 1..<samples.count {
                    let (a, b) = (samples[k - 1], samples[k])
                    var root: Double?
                    if a.f == 0 {
                        root = a.s
                    } else if a.f * b.f < 0 {
                        var (low, high, flow) = (a.s, b.s, a.f)
                        for _ in 0..<60 {
                            let middle = 0.5 * (low + high), fm = try f(middle)
                            if (fm < 0) == (flow < 0) { low = middle; flow = fm } else { high = middle }
                        }
                        root = 0.5 * (low + high)
                    }
                    guard let root else { continue }
                    let point = try curve.point(at: root, tolerance: tolerance)
                    if best.map({ (point - previous).length < ($0 - previous).length }) ?? true { best = point }
                }
                if let last = samples.last, last.f == 0 {
                    let point = try curve.point(at: last.s, tolerance: tolerance)
                    if best.map({ (point - previous).length < ($0 - previous).length }) ?? true { best = point }
                }
            }
            return best
        }
        // θ at t, with q continued from `previous` and θ unwrapped toward `reference`.
        func turn(at t: Double, previous: Point3D, reference: Double) throws -> (angle: Double, contact: Point3D) {
            let g = try guideOffset(at: t)
            guard let q = try reaching(g.length, near: previous) else {
                throw failure(.sweepGuideContactUnavailable, "A Curve guide runs farther from the path than the section reaches.")
            }
            let offset = q - start
            var angle = atan2(g.dot(e2), g.dot(e1)) - atan2(offset.dot(e2), offset.dot(e1))
            angle += ((reference - angle) / (2 * Double.pi)).rounded() * 2 * Double.pi
            return (angle, q)
        }
        // Nodes refined where the linear interpolation of θ, checked at seven interior points
        // (each continued from the interval's start), strays by more than a quarter of the
        // allowance at the section's radius: the contact slides as √t where the guide starts at
        // the foot of the path's perpendicular, so the nodes crowd there instead of everywhere.
        // At the start the guide touches the section at its own start, θ = 0.
        var nodes: [(t: Double, angle: Double, contact: Point3D)] = [(0, 0, contact)]
        var pending: [Double] = [1]
        while let upper = pending.last {
            let lower = nodes[nodes.count - 1]
            var inner: [(angle: Double, contact: Point3D)] = []
            var previous = lower.contact, reference = lower.angle
            for k in 1...8 {
                let step = try turn(at: lower.t + (upper - lower.t) * Double(k) / 8, previous: previous, reference: reference)
                (previous, reference) = (step.contact, step.angle)
                inner.append(step)
            }
            let end = inner[7]
            var deviation = 0.0
            for k in 1...7 {
                let fraction = Double(k) / 8
                deviation = max(deviation, abs(inner[k - 1].angle - (lower.angle + (end.angle - lower.angle) * fraction)))
            }
            if radius * deviation <= allowance / 4 || upper - lower.t <= 0x1p-40 {
                guard radius * deviation <= allowance / 4 else {
                    throw failure(.sweepGuideContactUnavailable,
                                  "A Curve guide's contact jumps across the section: the guide comes nearer the path than the side it touches.")
                }
                nodes.append((upper, end.angle, end.contact))
                pending.removeLast()
            } else {
                pending.append(0.5 * (lower.t + upper))
            }
            guard nodes.count <= 1024 else {
                throw failure(.resourceLimitExceeded, "A Curve guide turns too sharply for its allowance.")
            }
        }
        var turned = values
        turned.approximationTolerance = allowance / 2
        turned.twistPositions = nodes.map(\.t)
        turned.twistAngles = nodes.map(\.angle)
        turned.twistAngle = nodes[nodes.count - 1].angle
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
