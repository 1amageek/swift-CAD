import CADCore

public struct SweepFeature: Codable, Hashable, Sendable {
    public var sections: [SweepSectionReference]
    public var path: SweepPathReference
    public var guides: [SweepGuideReference]
    public var targets: [SweepTargetReference]
    public var options: SweepOptions

    public init(
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions()
    ) {
        self.sections = sections
        self.path = path
        self.guides = guides
        self.targets = targets
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case path
        case guides
        case targets
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .sections,
            .path,
            .guides,
            .targets,
            .options,
        ], in: decoder)
        sections = try container.decode([SweepSectionReference].self, forKey: .sections)
        path = try container.decode(SweepPathReference.self, forKey: .path)
        guides = try container.decode([SweepGuideReference].self, forKey: .guides)
        targets = try container.decode([SweepTargetReference].self, forKey: .targets)
        options = try container.decode(SweepOptions.self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
        try container.encode(path, forKey: .path)
        try container.encode(guides, forKey: .guides)
        try container.encode(targets, forKey: .targets)
        try container.encode(options, forKey: .options)
    }

    public func validate() throws {
        guard sections.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep features require at least one section.")
        }
        guard sections.count == 1 else {
            throw FeatureEvaluationError.invalidGraph("Sweep features currently require exactly one section.")
        }
        let sectionFeatureIDs = sections.map(\.featureID)
        guard Set(sectionFeatureIDs).count == sectionFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Sweep section references must be unique.")
        }
        try sections.forEach { try $0.validate() }
        try path.validate()
        let guideFeatureIDs = guides.map(\.featureID)
        guard Set(guideFeatureIDs).count == guideFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide references must be unique.")
        }
        try guides.forEach { try $0.validate() }
        let targetFeatureIDs = targets.map(\.featureID)
        guard Set(targetFeatureIDs).count == targetFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Sweep target references must be unique.")
        }
        try targets.forEach { try $0.validate() }
        guard sectionFeatureIDs.contains(path.featureID) == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep path must be distinct from every section.")
        }
        let reservedCurveFeatureIDs = Set(sectionFeatureIDs + [path.featureID])
        guard guideFeatureIDs.allSatisfy({ reservedCurveFeatureIDs.contains($0) == false }) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guides must be distinct from sections and path.")
        }
        let reservedSourceFeatureIDs = reservedCurveFeatureIDs.union(guideFeatureIDs)
        guard targetFeatureIDs.allSatisfy({ reservedSourceFeatureIDs.contains($0) == false }) else {
            throw FeatureEvaluationError.invalidGraph("Sweep targets must be distinct from sections, path, and guides.")
        }
        if options.resultKind == .solid {
            guard sections.allSatisfy(\.isProfile) else {
                throw FeatureEvaluationError.invalidGraph("Solid sweep sections must reference closed profiles.")
            }
        }
        switch options.booleanOperation {
        case .newBody:
            guard targets.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("New-body sweeps must not declare target bodies.")
            }
            guard options.keepTools == false else {
                throw FeatureEvaluationError.invalidGraph("Sweep keep-tools is only valid with boolean target operations.")
            }
        case .union, .difference, .intersect, .slice:
            guard targets.isEmpty == false else {
                throw FeatureEvaluationError.invalidGraph("Sweep boolean operations require at least one target body.")
            }
        }
        try options.validate()
    }
}

public enum SweepSectionReference: Codable, Hashable, Sendable {
    case profile(ProfileReference)
    case curve(SweepCurveSectionReference)

    public var featureID: FeatureID {
        switch self {
        case .profile(let profile):
            return profile.featureID
        case .curve(let curve):
            return curve.featureID
        }
    }

    public var profile: ProfileReference? {
        guard case .profile(let profile) = self else {
            return nil
        }
        return profile
    }

    public var isProfile: Bool {
        profile != nil
    }

    public var inputRole: FeaturePort {
        switch self {
        case .profile:
            return .profile
        case .curve:
            return .curve
        }
    }

    public func validate() throws {
        switch self {
        case .profile(let profile):
            try profile.validate()
        case .curve(let curve):
            try curve.validate()
        }
    }

    private enum Kind: String, Codable {
        case profile
        case curve
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case featureID
        case profileIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.kind, .featureID, .profileIndex], in: decoder)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let featureID = try container.decode(FeatureID.self, forKey: .featureID)
        switch kind {
        case .profile:
            let profileIndex = try container.decode(Int.self, forKey: .profileIndex)
            self = .profile(ProfileReference(featureID: featureID, profileIndex: profileIndex))
        case .curve:
            if container.contains(.profileIndex) {
                throw DecodingError.dataCorruptedError(
                    forKey: .profileIndex,
                    in: container,
                    debugDescription: "Sweep curve sections must not contain a profile index."
                )
            }
            self = .curve(SweepCurveSectionReference(featureID: featureID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile(let profile):
            try container.encode(Kind.profile, forKey: .kind)
            try container.encode(profile.featureID, forKey: .featureID)
            try container.encode(profile.profileIndex, forKey: .profileIndex)
        case .curve(let curve):
            try container.encode(Kind.curve, forKey: .kind)
            try container.encode(curve.featureID, forKey: .featureID)
        }
    }
}

public struct SweepCurveSectionReference: Codable, Hashable, Sendable {
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

public struct SweepPathReference: Codable, Hashable, Sendable {
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

public struct SweepGuideReference: Codable, Hashable, Sendable {
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

public struct SweepTargetReference: Codable, Hashable, Sendable {
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

public struct SweepOptions: Codable, Hashable, Sendable {
    public var twistAngle: CADExpression
    public var endScale: CADExpression
    public var alignment: SweepAlignment
    public var distanceFraction: CADExpression
    public var cornerStyle: SweepCornerStyle
    public var guideMethod: SweepGuideMethod
    public var booleanOperation: SweepBooleanOperation
    public var keepTools: Bool
    public var simplify: Bool
    public var resultKind: SweepResultKind

    private enum CodingKeys: String, CodingKey {
        case twistAngle
        case endScale
        case alignment
        case distanceFraction
        case cornerStyle
        case guideMethod
        case booleanOperation
        case keepTools
        case simplify
        case resultKind
    }

    public init(
        twistAngle: CADExpression = .constant(.angle(0.0, unit: .degree)),
        endScale: CADExpression = .constant(.scalar(1.0)),
        alignment: SweepAlignment = .normal,
        distanceFraction: CADExpression = .constant(.scalar(1.0)),
        cornerStyle: SweepCornerStyle = .mitre,
        guideMethod: SweepGuideMethod = .point,
        booleanOperation: SweepBooleanOperation = .newBody,
        keepTools: Bool = false,
        simplify: Bool = false,
        resultKind: SweepResultKind = .solid
    ) {
        self.twistAngle = twistAngle
        self.endScale = endScale
        self.alignment = alignment
        self.distanceFraction = distanceFraction
        self.cornerStyle = cornerStyle
        self.guideMethod = guideMethod
        self.booleanOperation = booleanOperation
        self.keepTools = keepTools
        self.simplify = simplify
        self.resultKind = resultKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .twistAngle,
            .endScale,
            .alignment,
            .distanceFraction,
            .cornerStyle,
            .guideMethod,
            .booleanOperation,
            .keepTools,
            .simplify,
            .resultKind,
        ], in: decoder)
        twistAngle = try container.decode(CADExpression.self, forKey: .twistAngle)
        endScale = try container.decode(CADExpression.self, forKey: .endScale)
        alignment = try container.decode(SweepAlignment.self, forKey: .alignment)
        distanceFraction = try container.decode(CADExpression.self, forKey: .distanceFraction)
        cornerStyle = try container.decode(SweepCornerStyle.self, forKey: .cornerStyle)
        guideMethod = try container.decode(SweepGuideMethod.self, forKey: .guideMethod)
        booleanOperation = try container.decode(SweepBooleanOperation.self, forKey: .booleanOperation)
        keepTools = try container.decode(Bool.self, forKey: .keepTools)
        simplify = try container.decode(Bool.self, forKey: .simplify)
        resultKind = try container.decode(SweepResultKind.self, forKey: .resultKind)
    }

    public func validate() throws {
        try twistAngle.validateLiteralQuantities()
        try endScale.validateLiteralQuantities()
        try distanceFraction.validateLiteralQuantities()
    }
}

public enum SweepAlignment: String, Codable, Hashable, Sendable {
    case parallel
    case normal
}

public enum SweepCornerStyle: String, Codable, Hashable, Sendable {
    case mitre
    case round
}

public enum SweepGuideMethod: String, Codable, Hashable, Sendable {
    case point
    case chord
    case curve
}

public enum SweepBooleanOperation: String, Codable, Hashable, Sendable {
    case newBody
    case union
    case difference
    case intersect
    case slice
}

public enum SweepResultKind: String, Codable, Hashable, Sendable {
    case solid
    case sheet
}
