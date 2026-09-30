import CADCore
import CADIR
import CADModeling

public struct SweepEvaluationPlanService: Sendable {
    private let resolver: any ParameterResolving
    private let optionValueResolver: SweepOptionValueResolver
    private let profileExtractor: (any SketchProfileExtracting)?
    private let curveExtractor: (any SketchCurveExtracting)?
    private let documentEvaluator: (any ExactDocumentEvaluating)?
    private let makePathSampler: @Sendable (ModelingTolerance) -> any SweepPathSampling

    public init(
        resolver: any ParameterResolving = ParameterResolver(),
        profileExtractor: (any SketchProfileExtracting)? = nil,
        curveExtractor: (any SketchCurveExtracting)? = nil,
        documentEvaluator: (any ExactDocumentEvaluating)? = nil,
        pathSamplerFactory: @escaping @Sendable (ModelingTolerance) -> any SweepPathSampling = {
            SweepPathSampler(tolerance: $0)
        }
    ) {
        self.resolver = resolver
        self.optionValueResolver = SweepOptionValueResolver(resolver: resolver)
        self.profileExtractor = profileExtractor
        self.curveExtractor = curveExtractor
        self.documentEvaluator = documentEvaluator
        self.makePathSampler = pathSamplerFactory
    }

    /// Resolves the oriented source path used by sweep construction without evaluating again.
    public func orderedPathSegments(
        for sweep: SweepFeature,
        document: CADDocument,
        evaluatedDocument: EvaluatedDocument,
        tolerance: ModelingTolerance
    ) throws -> [EvaluatedCurvePathSegment] {
        try tolerance.validate()
        try sweep.validate()
        guard let reference = sweep.sections.first else {
            throw FeatureEvaluationError.missingInput("Sweep path ordering requires a section.")
        }
        let parameters = try resolver.resolve(document.parameters)
        let section = try resolvedSection(reference, document: document, parameters: parameters,
            evaluatedDocument: evaluatedDocument, tolerance: tolerance)
        let pathCurves = try curves(for: sweep.path.featureID, document: document, parameters: parameters,
            evaluatedDocument: evaluatedDocument, tolerance: tolerance)
        let plane = try ExactSweepSectionPlane(section.plane(), tolerance: tolerance).plane
        return try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
            from: pathCurves, operationName: "Sweep path", preferredStartPlane: plane
        )
    }

    public func plan(
        document: CADDocument,
        sections: [SectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions(),
        tolerance: ModelingTolerance
    ) throws -> SweepEvaluationPlanResult {
        try tolerance.validate()
        try document.validate(tolerance: tolerance)

        let sweep = SweepFeature(
            sections: sections,
            path: path,
            guides: guides,
            targets: targets,
            options: options
        )
        try sweep.validate()

        var checks: [SweepEvaluationPreflightCheck] = [
            SweepEvaluationPreflightCheck(
                kind: .requestContract,
                status: .passed,
                message: "Sweep request references and option contract are valid."
            )
        ]

        let parameters = try resolver.resolve(document.parameters)
        let optionValues = try optionValueResolver.values(
            for: sweep,
            parameters: parameters,
            tolerance: tolerance
        )
        checks.append(SweepEvaluationPreflightCheck(
            kind: .optionValues,
            status: .passed,
            message: "Sweep option expressions resolve to finite twist, scale, and distance values."
        ))

        let requiredEvaluationFeatureIDs = try requiredEvaluationFeatureIDs(
            sections: sections,
            path: path,
            guides: guides,
            targets: targets,
            document: document
        )
        let evaluatedDocument = try requiredEvaluationFeatureIDs.isEmpty
            ? nil
            : evaluatedDocument(
                for: requiredEvaluationFeatureIDs,
                in: document,
                tolerance: tolerance
            )
        let section = try resolvedSection(
            sections[0],
            document: document,
            parameters: parameters,
            evaluatedDocument: evaluatedDocument,
            tolerance: tolerance
        )
        let pathCurves = try curves(
            for: path.featureID,
            document: document,
            parameters: parameters,
            evaluatedDocument: evaluatedDocument,
            tolerance: tolerance
        )
        let guideCurves = try guides.map { guide in
            let curves = try curves(
                for: guide.featureID,
                document: document,
                parameters: parameters,
                evaluatedDocument: evaluatedDocument,
                tolerance: tolerance
            )
            guard curves.count == 1,
                  let curve = curves.first else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Sweep evaluation currently requires one curve per guide."
                )
            }
            return curve
        }
        checks.append(SweepEvaluationPreflightCheck(
            kind: .sourceGeometry,
            status: .passed,
            message: "Sweep section, path, and guide source geometry resolved."
        ))

        if pathCurves.count > 1, options.cornerStyle == .round {
            return unsupportedResult(
                sectionCount: sections.count,
                pathSegmentCount: pathCurves.count,
                guideCount: guides.count,
                targetCount: targets.count,
                pathShape: .curved,
                sectionState: guideCurves.isEmpty ? .identity : .guided,
                unsupportedCase: SweepEvaluationCapabilities.UnsupportedCase(code: .sweepRoundCornerUnavailable),
                checks: checks + [
                    SweepEvaluationPreflightCheck(
                        kind: .pathChain,
                        status: .unsupported,
                        message: SweepEvaluationCapabilities.UnsupportedCase(
                            code: .sweepRoundCornerUnavailable
                        ).message
                    )
                ]
            )
        }

        let preferredStartPlane = try ExactSweepSectionPlane(
            try section.plane(),
            tolerance: tolerance
        ).plane
        let pathSegments = try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
            from: pathCurves,
            operationName: "Sweep path",
            preferredStartPlane: preferredStartPlane
        )
        // A curved path-normal sweep is admitted by building its certified plan.
        let curvedFrames = try makePathSampler(tolerance).frames(
            for: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            preferredNormal: normal(for: try section.plane(), tolerance: tolerance)
        )
        let curvedPathSpans = pathSegments.allSatisfy({ $0.curve.exactCurve != nil })
            ? try ExactBSplineCurveSpanBuilder(tolerance: tolerance).pathSpans(
                from: pathSegments, endingAt: optionValues.distanceFraction < 1 ? curvedFrames.last?.origin : nil
            )
            : []
        let circularSolid = try ExactCircularSweepPath(
            segments: pathSegments, distanceFraction: optionValues.distanceFraction, tolerance: tolerance
        ) != nil && options.resultKind == .solid
        if curvedPathSpans.isEmpty == false, CertifiedCurvedPathSweepPlan.applies(options, pathSpans: curvedPathSpans, exactCircularSolid: circularSolid, tolerance: tolerance) {
            let sectionState: SweepEvaluationCapabilities.SectionState = guideCurves.isEmpty ? .identity : .guided
            do {
                let certified = try CertifiedCurvedPathSweepPlan(section: section, pathSpans: curvedPathSpans,
                    sweep: sweep, values: optionValues, featureID: nil, tolerance: tolerance)
                let geometry = SweepEvaluationCapabilities.Geometry(pathShape: .curved, sectionState: sectionState,
                    guideConstraintCount: guides.count, tolerance: tolerance, certifiedCurvedPathAvailable: true)
                let supported = try SweepEvaluationCapabilities().supportedPlan(options, geometry: geometry, tolerance: tolerance)
                return SweepEvaluationPlanResult(status: .supported, sectionCount: sections.count,
                    pathSegmentCount: pathSegments.count, guideCount: guides.count, targetCount: targets.count,
                    pathShape: geometry.pathShape, sectionState: sectionState, evaluationKind: supported.kind,
                    outputTopologyKind: supported.outputTopologyKind, booleanSupportKind: supported.booleanSupportKind,
                    unsupportedCode: nil,
                    message: "Curved path-normal positional error <= \(certified.positionErrorUpperBound) meters.",
                    checks: checks + [SweepEvaluationPreflightCheck(kind: .capabilityDecision,
                        status: .passed, message: supported.message)])
            } catch let error as KernelError {
                return unsupportedResult(sectionCount: sections.count, pathSegmentCount: pathSegments.count,
                    guideCount: guides.count, targetCount: targets.count, pathShape: .curved, sectionState: sectionState,
                    unsupportedCase: SweepEvaluationCapabilities.UnsupportedCase(code: error.code, message: error.message),
                    checks: checks + [SweepEvaluationPreflightCheck(kind: .capabilityDecision,
                        status: .unsupported, message: error.message)])
            }
        }
        if CertifiedTwistSweepPlan.requested(options) {
            do {
                guard case let .profile(profile, _) = section else {
                    throw CertifiedTwistSweepPlan.failure("Certified twist initially requires a closed profile section.", tolerance)
                }
                let certified = try CertifiedTwistSweepPlan(profile: profile, pathSegments: pathSegments,
                    sweep: sweep, values: optionValues, tolerance: tolerance)
                let geometry = SweepEvaluationCapabilities.Geometry(pathShape: .straight(profileNormalComponent: 1),
                    sectionState: .twisted, guideConstraintCount: guides.count, tolerance: tolerance,
                    certifiedTwistAvailable: true)
                let supported = try SweepEvaluationCapabilities().supportedPlan(options, geometry: geometry, tolerance: tolerance)
                return SweepEvaluationPlanResult(status: .supported, sectionCount: sections.count,
                    pathSegmentCount: pathSegments.count, guideCount: guides.count, targetCount: targets.count,
                    pathShape: geometry.pathShape, sectionState: .twisted, evaluationKind: supported.kind,
                    outputTopologyKind: supported.outputTopologyKind, booleanSupportKind: supported.booleanSupportKind,
                    unsupportedCode: nil,
                    message: "Certified twist positional error <= \(certified.positionErrorUpperBound) meters.",
                    checks: checks + [SweepEvaluationPreflightCheck(kind: .capabilityDecision,
                        status: .passed, message: supported.message)])
            } catch let error as KernelError {
                return unsupportedResult(sectionCount: sections.count, pathSegmentCount: pathSegments.count,
                    guideCount: guides.count, targetCount: targets.count, pathShape: .curved, sectionState: .twisted,
                    unsupportedCase: SweepEvaluationCapabilities.UnsupportedCase(code: error.code, message: error.message),
                    checks: checks + [SweepEvaluationPreflightCheck(kind: .capabilityDecision,
                        status: .unsupported, message: error.message)])
            }
        }
        let exactCircularPath = try ExactCircularSweepPath(
            segments: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            tolerance: tolerance
        )
        checks.append(SweepEvaluationPreflightCheck(
            kind: .pathChain,
            status: .passed,
            message: "Sweep path resolves to a connected open curve chain."
        ))

        if targets.isEmpty == false {
            _ = try resolvedTargetBodyIDs(
                targets,
                evaluatedDocument: evaluatedDocument,
                tolerance: tolerance
            )
        }
        checks.append(SweepEvaluationPreflightCheck(
            kind: .booleanTargets,
            status: .passed,
            message: targets.isEmpty
                ? "Sweep uses new-body output without target bodies."
                : "Sweep target body references resolve to generated body topology."
        ))

        checks.append(SweepEvaluationPreflightCheck(
            kind: .guideConstraints,
            status: .passed,
            message: guideCurves.isEmpty
                ? "Sweep has no guide constraints."
                : "Sweep guide curves resolve to finite guide constraint paths."
        ))

        let sampler = makePathSampler(tolerance)
        let frames = try sampler.frames(
            for: pathSegments,
            distanceFraction: optionValues.distanceFraction,
            preferredNormal: normal(for: try section.plane(), tolerance: tolerance)
        )
        let straightPath = try sampler.straightPath(from: frames)
        let sectionTransform = SweepSectionTransform(
            twistAngle: optionValues.twistAngle,
            endScale: optionValues.endScale
        )
        let pathShape: SweepEvaluationCapabilities.PathShape
        if let straightPath {
            pathShape = .straight(
                profileNormalComponent: try profileNormalComponent(
                    of: straightPath.direction,
                    for: try section.plane(),
                    tolerance: tolerance
                )
            )
        } else if exactCircularPath != nil {
            pathShape = .circularArc
        } else {
            pathShape = .curved
        }
        let baseSectionState = sectionTransform.state(
            tolerance: tolerance
        )
        let sectionState: SweepEvaluationCapabilities.SectionState
        if guideCurves.count == 1,
           options.guideMethod == .point,
           baseSectionState == .identity,
           straightPath != nil,
           let pathStart = frames.first?.origin,
           let pathEnd = frames.last?.origin,
           let guide = guideCurves.first {
            do {
                _ = try exactPointGuideTransform(
                    section: section,
                    pathStart: pathStart,
                    pathEnd: pathEnd,
                    guide: guide,
                    distanceFraction: optionValues.distanceFraction,
                    tolerance: tolerance
                )
                sectionState = .pointGuide
            } catch let error as KernelError {
                let unsupportedCase = SweepEvaluationCapabilities.UnsupportedCase(
                    code: error.code,
                    message: error.message
                )
                return unsupportedResult(
                    sectionCount: sections.count,
                    pathSegmentCount: pathSegments.count,
                    guideCount: guideCurves.count,
                    targetCount: targets.count,
                    pathShape: pathShape,
                    sectionState: .guided,
                    unsupportedCase: unsupportedCase,
                    checks: checks + [
                        SweepEvaluationPreflightCheck(
                            kind: .capabilityDecision,
                            status: .unsupported,
                            message: unsupportedCase.message
                        )
                    ]
                )
            }
        } else if guideCurves.isEmpty == false {
            sectionState = .guided
        } else {
            sectionState = baseSectionState
        }

        if let exactCircularPath,
           options.alignment == .normal {
            do {
                try exactCircularPath.validateNormalSection(
                    plane: try section.plane(),
                    tolerance: tolerance
                )
            } catch let error as KernelError {
                let unsupportedCase = SweepEvaluationCapabilities.UnsupportedCase(
                    code: error.code,
                    message: error.message
                )
                return unsupportedResult(
                    sectionCount: sections.count,
                    pathSegmentCount: pathSegments.count,
                    guideCount: guideCurves.count,
                    targetCount: targets.count,
                    pathShape: pathShape,
                    sectionState: sectionState,
                    unsupportedCase: unsupportedCase,
                    checks: checks + [
                        SweepEvaluationPreflightCheck(
                            kind: .capabilityDecision,
                            status: .unsupported,
                            message: unsupportedCase.message
                        )
                    ]
                )
            }
        }

        let capabilities = SweepEvaluationCapabilities()
        let decision = try capabilities.decision(
            for: options,
            geometry: SweepEvaluationCapabilities.Geometry(
                pathShape: pathShape,
                sectionState: sectionState,
                guideConstraintCount: guideCurves.count,
                tolerance: tolerance
            )
        )
        switch decision {
        case .supported(let plan):
            let finalChecks = checks + [
                SweepEvaluationPreflightCheck(
                    kind: .capabilityDecision,
                    status: .passed,
                    message: plan.message
                )
            ]
            return SweepEvaluationPlanResult(
                status: .supported,
                sectionCount: sections.count,
                pathSegmentCount: pathSegments.count,
                guideCount: guideCurves.count,
                targetCount: targets.count,
                pathShape: pathShape,
                sectionState: sectionState,
                evaluationKind: plan.kind,
                outputTopologyKind: plan.outputTopologyKind,
                booleanSupportKind: plan.booleanSupportKind,
                unsupportedCode: nil,
                message: plan.message,
                checks: finalChecks
            )
        case .unsupported(let unsupportedCase):
            return unsupportedResult(
                sectionCount: sections.count,
                pathSegmentCount: pathSegments.count,
                guideCount: guideCurves.count,
                targetCount: targets.count,
                pathShape: pathShape,
                sectionState: sectionState,
                unsupportedCase: unsupportedCase,
                checks: checks + [
                    SweepEvaluationPreflightCheck(
                        kind: .capabilityDecision,
                        status: .unsupported,
                        message: unsupportedCase.message
                    )
                ]
            )
        }
    }

    private func unsupportedResult(
        sectionCount: Int,
        pathSegmentCount: Int,
        guideCount: Int,
        targetCount: Int,
        pathShape: SweepEvaluationCapabilities.PathShape,
        sectionState: SweepEvaluationCapabilities.SectionState,
        unsupportedCase: SweepEvaluationCapabilities.UnsupportedCase,
        checks: [SweepEvaluationPreflightCheck]
    ) -> SweepEvaluationPlanResult {
        SweepEvaluationPlanResult(
            status: .unsupported,
            sectionCount: sectionCount,
            pathSegmentCount: pathSegmentCount,
            guideCount: guideCount,
            targetCount: targetCount,
            pathShape: pathShape,
            sectionState: sectionState,
            evaluationKind: nil,
            outputTopologyKind: nil,
            booleanSupportKind: nil,
            unsupportedCode: unsupportedCase.code,
            message: unsupportedCase.message,
            checks: checks
        )
    }

    private func profiles(
        for featureID: FeatureID,
        document: CADDocument,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> [Profile] {
        guard let feature = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.missingInput("Sweep profile source feature could not be resolved.")
        }
        guard case .sketch(let sketch) = feature.operation else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Sweep profile sections currently require source sketch profiles."
            )
        }
        let extractor = profileExtractor ?? SketchProfileExtractor(
            resolver: resolver,
            tolerance: tolerance
        )
        return try extractor.extractProfiles(
            from: sketch,
            sourceFeatureID: featureID,
            parameters: parameters
        )
    }

    private func curves(
        for featureID: FeatureID,
        document: CADDocument,
        parameters: ResolvedParameterTable,
        evaluatedDocument: EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> [EvaluatedCurve] {
        guard let feature = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.missingInput("Sweep curve source feature could not be resolved.")
        }
        if case .sketch(let sketch) = feature.operation {
            let extractor = curveExtractor ?? SketchCurveExtractor(
                resolver: resolver,
                tolerance: tolerance
            )
            return try extractor.extractCurves(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: parameters
            )
        }
        guard let evaluated = evaluatedDocument else {
            throw FeatureEvaluationError.invalidGraph(
                "Sweep planning did not evaluate the requested generated curve source."
            )
        }
        guard let curves = evaluated.curves[featureID],
              curves.isEmpty == false else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Sweep curve source feature did not produce evaluated curves."
            )
        }
        return curves
    }

    private func resolvedSection(
        _ section: SectionReference,
        document: CADDocument,
        parameters: ResolvedParameterTable,
        evaluatedDocument: EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> ResolvedModelingSection {
        switch section {
        case .face(let reference):
            // A planar face is read from the evaluated body it lies on.
            guard let evaluated = evaluatedDocument else {
                throw FeatureEvaluationError.invalidGraph("Sweep planning did not evaluate the body a face section lies on.")
            }
            let context = EvaluationContext(parameters: parameters, brep: evaluated.brep, profiles: [:],
                subshapes: evaluated.subshapes, lineage: evaluated.lineage, tolerance: tolerance)
            return .profile(
                try FaceSectionProfileResolver().profile(for: reference, context: context, featureID: reference.featureID),
                section
            )
        case .profile(let profileReference):
            let sourceProfiles = try profiles(
                for: profileReference.featureID,
                document: document,
                parameters: parameters,
                tolerance: tolerance
            )
            return .profile(
                try ResolvedModelingSection.resolveProfile(profileReference, from: sourceProfiles),
                section
            )
        case .curve(let curveReference):
            let sourceCurves = try curves(
                for: curveReference.featureID,
                document: document,
                parameters: parameters,
                evaluatedDocument: evaluatedDocument,
                tolerance: tolerance
            )
            let curve = try ResolvedModelingSection.resolveCurve(
                curveReference,
                from: sourceCurves,
                tolerance: tolerance
            )
            return .curve(curve)
        }
    }

    private func evaluatedDocument(
        for featureIDs: Set<FeatureID>,
        in document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedDocument {
        let evaluator = documentEvaluator ?? DocumentEvaluator(
            parameterResolver: resolver,
            tolerance: tolerance
        )
        guard evaluator.evaluationTolerance == tolerance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sweep planning tolerance must match the injected document evaluator."
            )
        }
        let evaluated = try evaluator.evaluateExact(try evaluationSubdocument(
            from: document,
            including: featureIDs
        ))
        try evaluated.validateCurveOutputs(tolerance: tolerance)
        return evaluated
    }

    private func requiredEvaluationFeatureIDs(
        sections: [SectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference],
        targets: [SweepTargetReference],
        document: CADDocument
    ) throws -> Set<FeatureID> {
        var required = Set(targets.map(\.featureID))
        var curveSourceIDs = [path.featureID]
        curveSourceIDs.append(contentsOf: guides.map(\.featureID))
        for section in sections {
            if case .curve(let reference) = section {
                curveSourceIDs.append(reference.featureID)
            }
        }
        for featureID in curveSourceIDs {
            guard let feature = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.missingInput(
                    "Sweep geometry source feature could not be resolved."
                )
            }
            if case .sketch = feature.operation {
                continue
            }
            required.insert(featureID)
        }
        return required
    }

    private func evaluationSubdocument(
        from document: CADDocument,
        including requestedFeatureIDs: Set<FeatureID>
    ) throws -> CADDocument {
        var includedFeatureIDs = requestedFeatureIDs
        var pendingFeatureIDs = Array(requestedFeatureIDs)
        while let featureID = pendingFeatureIDs.popLast() {
            guard let feature = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.missingInput(
                    "Sweep evaluation source feature could not be resolved."
                )
            }
            for input in feature.inputs where includedFeatureIDs.insert(input.featureID).inserted {
                pendingFeatureIDs.append(input.featureID)
            }
        }

        var subdocument = document
        let order = document.designGraph.order.filter(includedFeatureIDs.contains)
        let nodes = Dictionary(uniqueKeysWithValues: try order.map { featureID in
            guard let feature = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Sweep evaluation subgraph order references a missing feature."
                )
            }
            return (featureID, feature)
        })
        let dependencies = document.designGraph.dependencies.filter { dependency in
            includedFeatureIDs.contains(dependency.source)
                && includedFeatureIDs.contains(dependency.target)
        }
        subdocument.designGraph = DesignGraph(
            nodes: nodes,
            order: order,
            dependencies: dependencies,
            revision: document.designGraph.revision
        )
        return subdocument
    }

    private func resolvedTargetBodyIDs(
        _ targets: [SweepTargetReference],
        evaluatedDocument: EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> [BodyID] {
        guard let evaluated = evaluatedDocument else {
            throw FeatureEvaluationError.invalidGraph(
                "Sweep planning did not evaluate the requested target bodies."
            )
        }
        return try targets.map { target in
            let subshapeID = SubshapeID(
                featureID: target.featureID,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0
            )
            guard let reference = evaluated.subshapes[subshapeID] else {
                throw FeatureEvaluationError.missingInput("Sweep target body could not be resolved.")
            }
            guard case let .body(bodyID) = reference else {
                throw FeatureEvaluationError.invalidGraph("Sweep target subshape is not a body.")
            }
            return bodyID
        }
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
        guide: EvaluatedCurve,
        distanceFraction: Double,
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
                featureID: nil
            )
        case .curve(let curve):
            return try resolver.resolve(
                section: curve,
                pathStart: pathStart,
                pathEnd: pathEnd,
                guide: guide,
                distanceFraction: distanceFraction,
                featureID: nil
            )
        }
    }

}
