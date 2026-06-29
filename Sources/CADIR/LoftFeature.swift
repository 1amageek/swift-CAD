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
    }
}

public struct LoftSectionReference: Codable, Hashable, Sendable {
    public var profile: ProfileReference

    public init(profile: ProfileReference) {
        self.profile = profile
    }

    public var featureID: FeatureID {
        profile.featureID
    }

    public func validate() throws {
        try profile.validate()
    }
}

public struct LoftOptions: Codable, Hashable, Sendable {
    public var resultKind: LoftResultKind
    public var sectionMatching: LoftSectionMatching

    public init(
        resultKind: LoftResultKind = .solid,
        sectionMatching: LoftSectionMatching = .byIndex
    ) {
        self.resultKind = resultKind
        self.sectionMatching = sectionMatching
    }

    public func validate() throws {}
}

public enum LoftResultKind: String, Codable, Hashable, Sendable {
    case solid
    case sheet
}

public enum LoftSectionMatching: String, Codable, Hashable, Sendable {
    case byIndex
}
