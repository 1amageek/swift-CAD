import CADCore

public struct LoftFeature: Codable, Hashable, Sendable {
    public var sections: [LoftSectionReference]
    public var options: LoftOptions

    public init(
        sections: [LoftSectionReference],
        options: LoftOptions = LoftOptions()
    ) {
        self.sections = sections
        self.options = options
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

public struct LoftSectionReference: Codable, Hashable, Sendable {
    public var profile: ProfileReference
    public var startSampleIndex: Int?

    public init(
        profile: ProfileReference,
        startSampleIndex: Int? = nil
    ) {
        self.profile = profile
        self.startSampleIndex = startSampleIndex
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
    }
}

public struct LoftOptions: Codable, Hashable, Sendable {
    public var resultKind: LoftResultKind
    public var sectionMatching: LoftSectionMatching
    public var closesSectionLoop: Bool

    private enum CodingKeys: String, CodingKey {
        case resultKind
        case sectionMatching
        case closesSectionLoop
    }

    public init(
        resultKind: LoftResultKind = .solid,
        sectionMatching: LoftSectionMatching = .byBoundaryProgress,
        closesSectionLoop: Bool = false
    ) {
        self.resultKind = resultKind
        self.sectionMatching = sectionMatching
        self.closesSectionLoop = closesSectionLoop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultKind = try container.decode(LoftResultKind.self, forKey: .resultKind)
        sectionMatching = try container.decode(LoftSectionMatching.self, forKey: .sectionMatching)
        closesSectionLoop = try container.decodeIfPresent(Bool.self, forKey: .closesSectionLoop) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resultKind, forKey: .resultKind)
        try container.encode(sectionMatching, forKey: .sectionMatching)
        try container.encode(closesSectionLoop, forKey: .closesSectionLoop)
    }

    public func validate() throws {}
}

public enum LoftResultKind: String, Codable, Hashable, Sendable {
    case solid
    case sheet
}

public enum LoftSectionMatching: String, Codable, Hashable, Sendable {
    case byBoundaryProgress
}
