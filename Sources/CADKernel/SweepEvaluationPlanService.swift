import CADCore
import CADIR

public struct SweepEvaluationPlanResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case supported
        case unsupported
    }

    public var status: Status
    public var sectionCount: Int
    public var pathSegmentCount: Int
    public var guideCount: Int
    public var targetCount: Int
    public var pathShape: SweepEvaluationCapabilities.PathShape
    public var sectionState: SweepEvaluationCapabilities.SectionState
    public var evaluationKind: SweepEvaluationCapabilities.EvaluationKind?
    public var outputTopologyKind: SweepEvaluationCapabilities.OutputTopologyKind?
    public var booleanSupportKind: SweepEvaluationCapabilities.BooleanSupportKind?
    public var guideStrategies: [SweepEvaluationCapabilities.GuideStrategy]
    public var unsupportedCode: SweepEvaluationCapabilities.UnsupportedCode?
    public var message: String
    public var checks: [SweepEvaluationPreflightCheck]

    public init(
        status: Status,
        sectionCount: Int,
        pathSegmentCount: Int,
        guideCount: Int,
        targetCount: Int,
        pathShape: SweepEvaluationCapabilities.PathShape,
        sectionState: SweepEvaluationCapabilities.SectionState,
        evaluationKind: SweepEvaluationCapabilities.EvaluationKind?,
        outputTopologyKind: SweepEvaluationCapabilities.OutputTopologyKind?,
        booleanSupportKind: SweepEvaluationCapabilities.BooleanSupportKind?,
        guideStrategies: [SweepEvaluationCapabilities.GuideStrategy],
        unsupportedCode: SweepEvaluationCapabilities.UnsupportedCode?,
        message: String,
        checks: [SweepEvaluationPreflightCheck]
    ) {
        self.status = status
        self.sectionCount = sectionCount
        self.pathSegmentCount = pathSegmentCount
        self.guideCount = guideCount
        self.targetCount = targetCount
        self.pathShape = pathShape
        self.sectionState = sectionState
        self.evaluationKind = evaluationKind
        self.outputTopologyKind = outputTopologyKind
        self.booleanSupportKind = booleanSupportKind
        self.guideStrategies = guideStrategies
        self.unsupportedCode = unsupportedCode
        self.message = message
        self.checks = checks
    }
}

public struct SweepEvaluationPreflightCheck: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case requestContract
        case optionValues
        case sourceGeometry
        case pathChain
        case guideConstraints
        case booleanTargets
        case capabilityDecision
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case passed
        case unsupported
    }

    public var kind: Kind
    public var status: Status
    public var message: String

    public init(kind: Kind, status: Status, message: String) {
        self.kind = kind
        self.status = status
        self.message = message
    }
}

public struct SweepEvaluationPlanService: Sendable {
    private let resolver: any ParameterResolving
    private let optionValueResolver: SweepOptionValueResolver
    private let profileExtractor: any SketchProfileExtracting
    private let curveExtractor: any SketchCurveExtracting
    private let documentEvaluator: DocumentEvaluator
    private let makePathSampler: @Sendable (ModelingTolerance) -> any SweepPathSampling

    public init(
        resolver: any ParameterResolving = ParameterResolver(),
        profileExtractor: (any SketchProfileExtracting)? = nil,
        curveExtractor: (any SketchCurveExtracting)? = nil,
        documentEvaluator: DocumentEvaluator? = nil,
        pathSamplerFactory: @escaping @Sendable (ModelingTolerance) -> any SweepPathSampling = {
            SweepPathSampler(tolerance: $0)
        }
    ) {
        self.resolver = resolver
        self.optionValueResolver = SweepOptionValueResolver(resolver: resolver)
        self.profileExtractor = profileExtractor ?? SketchProfileExtractor(resolver: resolver)
        self.curveExtractor = curveExtractor ?? SketchCurveExtractor(resolver: resolver)
        self.documentEvaluator = documentEvaluator ?? DocumentEvaluator(parameterResolver: resolver)
        self.makePathSampler = pathSamplerFactory
    }

    public func plan(
        document: CADDocument,
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions(),
        tolerance: ModelingTolerance = .standard
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

        var evaluatedDocument: EvaluatedDocument?
        let section = try resolvedSection(
            sections[0],
            document: document,
            parameters: parameters,
            evaluatedDocument: &evaluatedDocument,
            tolerance: tolerance
        )
        let pathCurves = try curves(
            for: path.featureID,
            document: document,
            parameters: parameters,
            evaluatedDocument: &evaluatedDocument,
            tolerance: tolerance
        )
        let guideCurves = try guides.map { guide in
            let curves = try curves(
                for: guide.featureID,
                document: document,
                parameters: parameters,
                evaluatedDocument: &evaluatedDocument,
                tolerance: tolerance
            )
            guard curves.count == 1,
                  let curve = curves.first else {
                throw FeatureEvaluationError.unsupportedOperation(
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
                unsupportedCase: SweepEvaluationCapabilities.UnsupportedCase(code: .roundCornerMultiCurvePath),
                checks: checks + [
                    SweepEvaluationPreflightCheck(
                        kind: .pathChain,
                        status: .unsupported,
                        message: SweepEvaluationCapabilities.UnsupportedCase(
                            code: .roundCornerMultiCurvePath
                        ).message
                    )
                ]
            )
        }

        let pathSegments = try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
            from: pathCurves,
            operationName: "Sweep path"
        )
        checks.append(SweepEvaluationPreflightCheck(
            kind: .pathChain,
            status: .passed,
            message: "Sweep path resolves to a connected open curve chain."
        ))

        if targets.isEmpty == false {
            _ = try resolvedTargetBodyIDs(
                targets,
                document: document,
                evaluatedDocument: &evaluatedDocument
            )
        }
        checks.append(SweepEvaluationPreflightCheck(
            kind: .booleanTargets,
            status: .passed,
            message: targets.isEmpty
                ? "Sweep uses new-body output without target bodies."
                : "Sweep target body references resolve to generated body topology."
        ))

        let sectionConstraintSolver: SweepSectionConstraintSolver?
        if guideCurves.isEmpty {
            sectionConstraintSolver = nil
        } else {
            sectionConstraintSolver = try SweepSectionConstraintSolver(
                method: options.guideMethod,
                guideCurves: guideCurves,
                distanceFraction: optionValues.distanceFraction,
                tolerance: tolerance
            )
        }
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
            preferredNormal: normal(for: section.plane, tolerance: tolerance)
        )
        let straightPath = try sampler.straightPath(from: frames)
        let sectionTransform = SweepSectionTransform(
            twistAngle: optionValues.twistAngle,
            endScale: optionValues.endScale
        )
        let sectionState: SweepEvaluationCapabilities.SectionState
        if sectionConstraintSolver != nil {
            sectionState = .guided
        } else if sectionTransform.isIdentity(tolerance: tolerance) {
            sectionState = .identity
        } else {
            sectionState = .transformed
        }

        let pathShape: SweepEvaluationCapabilities.PathShape
        if let straightPath {
            pathShape = .straight(
                profileNormalComponent: try profileNormalComponent(
                    of: straightPath.direction,
                    for: section.plane,
                    tolerance: tolerance
                )
            )
        } else {
            pathShape = .curved
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
                guideStrategies: plan.guideStrategies,
                unsupportedCode: nil,
                message: plan.message,
                checks: checks + [
                    SweepEvaluationPreflightCheck(
                        kind: .capabilityDecision,
                        status: .passed,
                        message: plan.message
                    )
                ]
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
            guideStrategies: [],
            unsupportedCode: unsupportedCase.code,
            message: unsupportedCase.message,
            checks: checks
        )
    }

    private func profiles(
        for featureID: FeatureID,
        document: CADDocument,
        parameters: ResolvedParameterTable
    ) throws -> [Profile] {
        guard let feature = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.missingInput("Sweep profile source feature could not be resolved.")
        }
        guard case .sketch(let sketch) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep profile sections currently require source sketch profiles."
            )
        }
        return try profileExtractor.extractProfiles(
            from: sketch,
            sourceFeatureID: featureID,
            parameters: parameters
        )
    }

    private func curves(
        for featureID: FeatureID,
        document: CADDocument,
        parameters: ResolvedParameterTable,
        evaluatedDocument: inout EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> [EvaluatedCurve] {
        guard let feature = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.missingInput("Sweep curve source feature could not be resolved.")
        }
        if case .sketch(let sketch) = feature.operation {
            return try curveExtractor.extractCurves(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: parameters
            )
        }
        let evaluated = try evaluatedDocumentForGeneratedSources(
            document: document,
            evaluatedDocument: &evaluatedDocument,
            tolerance: tolerance
        )
        guard let curves = evaluated.curves[featureID],
              curves.isEmpty == false else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep curve source feature did not produce evaluated curves."
            )
        }
        return curves
    }

    private func resolvedSection(
        _ section: SweepSectionReference,
        document: CADDocument,
        parameters: ResolvedParameterTable,
        evaluatedDocument: inout EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> SweepEvaluationResolvedSection {
        switch section {
        case .profile(let profileReference):
            let sourceProfiles = try profiles(
                for: profileReference.featureID,
                document: document,
                parameters: parameters
            )
            guard sourceProfiles.indices.contains(profileReference.profileIndex) else {
                throw FeatureEvaluationError.missingProfile(
                    profileReference.featureID,
                    profileReference.profileIndex
                )
            }
            return .profile(sourceProfiles[profileReference.profileIndex])
        case .curve(let curveReference):
            let sourceCurves = try curves(
                for: curveReference.featureID,
                document: document,
                parameters: parameters,
                evaluatedDocument: &evaluatedDocument,
                tolerance: tolerance
            )
            guard sourceCurves.count == 1,
                  let curve = sourceCurves.first else {
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

    private func evaluatedDocumentForGeneratedSources(
        document: CADDocument,
        evaluatedDocument: inout EvaluatedDocument?,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedDocument {
        if let evaluatedDocument {
            return evaluatedDocument
        }
        let evaluated = try documentEvaluator.evaluate(document)
        try evaluated.validateCurveOutputs(tolerance: tolerance)
        evaluatedDocument = evaluated
        return evaluated
    }

    private func resolvedTargetBodyIDs(
        _ targets: [SweepTargetReference],
        document: CADDocument,
        evaluatedDocument: inout EvaluatedDocument?
    ) throws -> [BodyID] {
        let evaluated: EvaluatedDocument
        if let current = evaluatedDocument {
            evaluated = current
        } else {
            evaluated = try documentEvaluator.evaluate(document)
            evaluatedDocument = evaluated
        }
        return try targets.map { target in
            let name = PersistentName(components: [
                .feature(target.featureID),
                .generated(GeneratedSubshapeRole.body.rawValue),
            ])
            guard let reference = evaluated.generatedNames[name] else {
                throw FeatureEvaluationError.missingInput("Sweep target body could not be resolved.")
            }
            guard case let .body(bodyID) = reference else {
                throw FeatureEvaluationError.invalidGraph("Sweep target persistent name is not a body.")
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
}

private enum SweepEvaluationResolvedSection {
    case profile(Profile)
    case curve(EvaluatedCurve)

    var plane: SketchPlane {
        switch self {
        case .profile(let profile):
            return profile.plane
        case .curve(let curve):
            guard let plane = curve.plane else {
                preconditionFailure("Resolved sweep curve sections must carry plane metadata.")
            }
            return plane
        }
    }
}
