import CADCore

public struct LoftFeature: Codable, Hashable, Sendable {
    public var sections: [LoftSectionReference]
    public var guides: [LoftGuideReference]
    public var options: LoftOptions

    public init(
        sections: [LoftSectionReference],
        guides: [LoftGuideReference] = [],
        options: LoftOptions = LoftOptions()
    ) {
        self.sections = sections
        self.guides = guides
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case guides
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decode([LoftSectionReference].self, forKey: .sections)
        guides = try container.decodeIfPresent([LoftGuideReference].self, forKey: .guides) ?? []
        options = try container.decode(LoftOptions.self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
        try container.encode(guides, forKey: .guides)
        try container.encode(options, forKey: .options)
    }

    public func validate() throws {
        guard sections.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Loft features require at least two profile sections.")
        }
        for section in sections {
            try section.validate()
        }
        let uniqueSections = Set(sections)
        guard uniqueSections.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft profile sections must be unique.")
        }
        let uniqueFeatureIDs = Set(sections.map(\.featureID))
        guard uniqueFeatureIDs.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft profile section features must be unique.")
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

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public struct LoftSectionReference: Codable, Hashable, Sendable {
    public var profile: ProfileReference
    public var startSampleIndex: Int?
    public var smoothTangentScale: Double?
    public var smoothTangentMode: LoftSectionSmoothTangentMode

    private enum CodingKeys: String, CodingKey {
        case profile
        case startSampleIndex
        case smoothTangentScale
        case smoothTangentMode
    }

    public init(
        profile: ProfileReference,
        startSampleIndex: Int? = nil,
        smoothTangentScale: Double? = nil,
        smoothTangentMode: LoftSectionSmoothTangentMode = .automatic
    ) {
        self.profile = profile
        self.startSampleIndex = startSampleIndex
        self.smoothTangentScale = smoothTangentScale
        self.smoothTangentMode = smoothTangentMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(ProfileReference.self, forKey: .profile)
        startSampleIndex = try container.decodeIfPresent(Int.self, forKey: .startSampleIndex)
        smoothTangentScale = try container.decodeIfPresent(Double.self, forKey: .smoothTangentScale)
        smoothTangentMode =
            try container.decodeIfPresent(LoftSectionSmoothTangentMode.self, forKey: .smoothTangentMode) ?? .automatic
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encodeIfPresent(startSampleIndex, forKey: .startSampleIndex)
        try container.encodeIfPresent(smoothTangentScale, forKey: .smoothTangentScale)
        try container.encode(smoothTangentMode, forKey: .smoothTangentMode)
    }

    public var featureID: FeatureID {
        profile.featureID
    }

    public func validate() throws {
        try profile.validate()
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

    private enum CodingKeys: String, CodingKey {
        case resultKind
        case sectionMatching
        case closesSectionLoop
        case surfaceMode
        case smoothTangentScale
    }

    public init(
        resultKind: LoftResultKind = .solid,
        sectionMatching: LoftSectionMatching = .byBoundaryProgress,
        closesSectionLoop: Bool = false,
        surfaceMode: LoftSurfaceMode = .ruled,
        smoothTangentScale: Double = 1.0
    ) {
        self.resultKind = resultKind
        self.sectionMatching = sectionMatching
        self.closesSectionLoop = closesSectionLoop
        self.surfaceMode = surfaceMode
        self.smoothTangentScale = smoothTangentScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultKind = try container.decode(LoftResultKind.self, forKey: .resultKind)
        sectionMatching = try container.decode(LoftSectionMatching.self, forKey: .sectionMatching)
        closesSectionLoop = try container.decodeIfPresent(Bool.self, forKey: .closesSectionLoop) ?? false
        surfaceMode = try container.decodeIfPresent(LoftSurfaceMode.self, forKey: .surfaceMode) ?? .ruled
        smoothTangentScale = try container.decodeIfPresent(Double.self, forKey: .smoothTangentScale) ?? 1.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resultKind, forKey: .resultKind)
        try container.encode(sectionMatching, forKey: .sectionMatching)
        try container.encode(closesSectionLoop, forKey: .closesSectionLoop)
        try container.encode(surfaceMode, forKey: .surfaceMode)
        try container.encode(smoothTangentScale, forKey: .smoothTangentScale)
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
