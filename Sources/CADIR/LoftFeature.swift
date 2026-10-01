import CADCore

public struct LoftFeature: Codable, Hashable, Sendable {
    public var sections: [LoftSectionReference]
    public var guides: [LoftGuideReference]
    public var options: LoftOptions
    /// A vertex the loft ends at after its one section (Loft from a vertex).
    public var apex: LoftApex?

    public init(
        sections: [LoftSectionReference],
        guides: [LoftGuideReference] = [],
        options: LoftOptions = LoftOptions(),
        apex: LoftApex? = nil
    ) {
        self.sections = sections
        self.guides = guides
        self.options = options
        self.apex = apex
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case guides
        case options
        case apex
    }

    /// The features the loft consumes, each once: its sections' sources, continuity bodies,
    /// guides and the apex's body.
    public var inputs: [FeatureInput] {
        var seen = Set<FeatureInput>()
        return (sections.flatMap(\.inputs) + guides.map { FeatureInput(featureID: $0.featureID, role: .guide) }
                + (apex.map { [FeatureInput(featureID: $0.source, role: $0.bodyRole)] } ?? []))
            .filter { seen.insert($0).inserted }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.sections, .guides, .options, .apex], in: decoder)
        sections = try container.decode([LoftSectionReference].self, forKey: .sections)
        guides = try container.decode([LoftGuideReference].self, forKey: .guides)
        options = try container.decode(LoftOptions.self, forKey: .options)
        apex = try container.decodeIfPresent(LoftApex.self, forKey: .apex)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
        try container.encode(guides, forKey: .guides)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(apex, forKey: .apex)
    }

    public func validate() throws {
        if let apex {
            try apex.vertex.validate()
            guard sections.count == 1, guides.isEmpty, sections[0].continuity == nil, options.closesSectionLoop == false else {
                throw FeatureEvaluationError.invalidGraph("A Loft to a vertex takes one section, no guides and no continuity.")
            }
            try sections[0].validate()
            guard options.resultKind == .sheet || sections[0].section.isClosedRegion else {
                throw FeatureEvaluationError.invalidGraph("Curve Loft sections require Sheet output.")
            }
            try options.validate()
            return
        }
        guard sections.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Loft features require at least two profile sections.")
        }
        guard !options.closesSectionLoop || sections.allSatisfy({ $0.continuity == nil }) else {
            throw FeatureEvaluationError.invalidGraph("A closed Loft has no end sections to be continuous at.")
        }
        for section in sections {
            try section.validate()
        }
        guard options.resultKind == .sheet || sections.allSatisfy({ $0.section.isClosedRegion }) else {
            throw FeatureEvaluationError.invalidGraph("Curve Loft sections require Sheet output.")
        }
        let uniqueSections = Set(sections)
        guard uniqueSections.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft profile sections must be unique.")
        }
        let uniqueFeatureIDs = Set(sections.map(\.featureID))
        guard uniqueFeatureIDs.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft profile section features must be unique.")
        }
        guard sections.dropFirst().dropLast().allSatisfy({ $0.continuity == nil }) else {
            throw FeatureEvaluationError.invalidGraph("Loft continuity belongs to the first or last section.")
        }
        let guideFeatureIDs = guides.map(\.featureID)
        guard Set(guideFeatureIDs).count == guideFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Loft guide references must be unique.")
        }
        guard guideFeatureIDs.allSatisfy({ uniqueFeatureIDs.contains($0) == false }) else {
            throw FeatureEvaluationError.invalidGraph("Loft guides must be distinct from profile sections.")
        }
        for guide in guides {
            try guide.validate()
        }
        try options.validate()
        if options.closesSectionLoop {
            guard options.resultKind == .sheet else {
                throw FeatureEvaluationError.invalidGraph("Closed Loft section loops must use sheet output.")
            }
            guard sections.count >= 3 else {
                throw FeatureEvaluationError.invalidGraph("Closed Loft section loops require at least three profile sections.")
            }
        }
    }
}

public struct LoftGuideReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    private enum CodingKeys: String, CodingKey {
        case featureID
    }

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
    }

    public func validate() throws {}
}

public struct LoftSectionReference: Codable, Hashable, Sendable {
    public var section: SectionReference
    public var profileDirection: LoftProfileDirection
    public var startSampleIndex: Int?
    public var smoothTangentScale: Double?
    public var smoothTangentMode: LoftSectionSmoothTangentMode
    /// Tangent or curvature continuity with the face beside the body edge an end curve section
    /// runs along; nil for position (G0) only.
    public var continuity: SurfaceEdgeContinuity?

    private enum CodingKeys: String, CodingKey {
        case section
        case profileDirection
        case startSampleIndex
        case smoothTangentScale
        case smoothTangentMode
        case continuity
    }

    public init(
        profile: ProfileReference,
        profileDirection: LoftProfileDirection = .automatic,
        startSampleIndex: Int? = nil,
        smoothTangentScale: Double? = nil,
        smoothTangentMode: LoftSectionSmoothTangentMode = .automatic
    ) {
        self.init(section: .profile(profile), profileDirection: profileDirection, startSampleIndex: startSampleIndex,
            smoothTangentScale: smoothTangentScale, smoothTangentMode: smoothTangentMode)
    }

    public init(
        section: SectionReference,
        profileDirection: LoftProfileDirection = .automatic,
        startSampleIndex: Int? = nil,
        smoothTangentScale: Double? = nil,
        smoothTangentMode: LoftSectionSmoothTangentMode = .automatic,
        continuity: SurfaceEdgeContinuity? = nil
    ) {
        self.section = section
        self.profileDirection = profileDirection
        self.startSampleIndex = startSampleIndex
        self.smoothTangentScale = smoothTangentScale
        self.smoothTangentMode = smoothTangentMode
        self.continuity = continuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .section,
            .profileDirection,
            .startSampleIndex,
            .smoothTangentScale,
            .smoothTangentMode,
            .continuity,
        ], in: decoder)
        section = try container.decode(SectionReference.self, forKey: .section)
        profileDirection = try container.decode(LoftProfileDirection.self, forKey: .profileDirection)
        startSampleIndex = try container.decodeIfPresent(Int.self, forKey: .startSampleIndex)
        smoothTangentScale = try container.decodeIfPresent(Double.self, forKey: .smoothTangentScale)
        smoothTangentMode = try container.decode(LoftSectionSmoothTangentMode.self, forKey: .smoothTangentMode)
        continuity = try container.decodeIfPresent(SurfaceEdgeContinuity.self, forKey: .continuity)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(profileDirection, forKey: .profileDirection)
        try container.encodeIfPresent(startSampleIndex, forKey: .startSampleIndex)
        try container.encodeIfPresent(smoothTangentScale, forKey: .smoothTangentScale)
        try container.encode(smoothTangentMode, forKey: .smoothTangentMode)
        try container.encodeIfPresent(continuity, forKey: .continuity)
    }

    public var featureID: FeatureID {
        section.featureID
    }

    /// The features the section consumes: its source and, with continuity, the edge's body.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: featureID, role: section.inputRole)]
            + (continuity.map { [FeatureInput(featureID: $0.source, role: $0.bodyRole)] } ?? [])
    }

    public func validate() throws {
        try section.validate()
        guard section.isClosedRegion || profileDirection == .automatic else {
            throw FeatureEvaluationError.invalidGraph("Curve Loft traversal belongs to its curve reference, not profileDirection.")
        }
        if let startSampleIndex {
            guard startSampleIndex >= 0 else {
                throw FeatureEvaluationError.invalidGraph("Loft section start sample indexes must be zero or greater.")
            }
        }
        if let smoothTangentScale {
            guard smoothTangentScale.isFinite,
                  smoothTangentScale > 0.0 else {
                throw FeatureEvaluationError.invalidGraph(
                    "Loft section smooth tangent scale must be finite and greater than zero."
                )
            }
        }
        if let continuity {
            try continuity.validate()
            guard case .curve = section else {
                throw FeatureEvaluationError.invalidGraph("Loft continuity belongs to a curve section along a body edge.")
            }
        }
    }
}

public enum LoftSectionSmoothTangentMode: String, Codable, Hashable, Sendable {
    case automatic
    case zero
}

public struct LoftOptions: Codable, Hashable, Sendable {
    public var resultKind: LoftResultKind
    public var sectionMatching: LoftSectionMatching
    public var closesSectionLoop: Bool
    public var surfaceMode: LoftSurfaceMode
    public var smoothTangentScale: Double
    /// Whether the loft's flat faces are trimmed planes rather than flat B-spline patches.
    public var simplify: Bool

    private enum CodingKeys: String, CodingKey {
        case resultKind
        case sectionMatching
        case closesSectionLoop
        case surfaceMode
        case smoothTangentScale
        case simplify
    }

    public init(
        resultKind: LoftResultKind = .solid,
        sectionMatching: LoftSectionMatching = .byBoundaryProgress,
        closesSectionLoop: Bool = false,
        surfaceMode: LoftSurfaceMode = .ruled,
        smoothTangentScale: Double = 1.0,
        simplify: Bool = false
    ) {
        self.resultKind = resultKind
        self.sectionMatching = sectionMatching
        self.closesSectionLoop = closesSectionLoop
        self.surfaceMode = surfaceMode
        self.smoothTangentScale = smoothTangentScale
        self.simplify = simplify
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .resultKind,
            .sectionMatching,
            .closesSectionLoop,
            .surfaceMode,
            .smoothTangentScale,
            .simplify,
        ], in: decoder)
        resultKind = try container.decode(LoftResultKind.self, forKey: .resultKind)
        sectionMatching = try container.decode(LoftSectionMatching.self, forKey: .sectionMatching)
        closesSectionLoop = try container.decode(Bool.self, forKey: .closesSectionLoop)
        surfaceMode = try container.decode(LoftSurfaceMode.self, forKey: .surfaceMode)
        smoothTangentScale = try container.decode(Double.self, forKey: .smoothTangentScale)
        simplify = try container.decodeIfPresent(Bool.self, forKey: .simplify) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resultKind, forKey: .resultKind)
        try container.encode(sectionMatching, forKey: .sectionMatching)
        try container.encode(closesSectionLoop, forKey: .closesSectionLoop)
        try container.encode(surfaceMode, forKey: .surfaceMode)
        try container.encode(smoothTangentScale, forKey: .smoothTangentScale)
        if simplify { try container.encode(simplify, forKey: .simplify) }
    }

    public func validate() throws {
        guard smoothTangentScale.isFinite,
              smoothTangentScale > 0.0 else {
            throw FeatureEvaluationError.invalidGraph("Loft smooth tangent scale must be finite and greater than zero.")
        }
    }
}

public enum LoftResultKind: String, Codable, Hashable, Sendable {
    case solid
    case sheet
}

public enum LoftSectionMatching: String, Codable, Hashable, Sendable {
    case byBoundaryProgress
}

public enum LoftSurfaceMode: String, Codable, Hashable, Sendable {
    case ruled
    case smooth
}

/// The vertex of a body (or sheet) a Loft ends at.
public struct LoftApex: Codable, Hashable, Sendable {
    public var source: FeatureID
    public var bodyRole: FeaturePort
    public var vertex: StableSubshapeReference

    public init(source: FeatureID, bodyRole: FeaturePort = .body, vertex: StableSubshapeReference) {
        self.source = source
        self.bodyRole = bodyRole
        self.vertex = vertex
    }
}
