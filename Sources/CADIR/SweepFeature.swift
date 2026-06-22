import CADCore

public struct SweepFeature: Codable, Hashable, Sendable {
    public var profiles: [ProfileReference]
    public var path: SweepPathReference
    public var guides: [SweepGuideReference]
    public var targets: [SweepTargetReference]
    public var options: SweepOptions

    public init(
        profiles: [ProfileReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions()
    ) {
        self.profiles = profiles
        self.path = path
        self.guides = guides
        self.targets = targets
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case profiles
        case path
        case guides
        case targets
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([ProfileReference].self, forKey: .profiles)
        path = try container.decode(SweepPathReference.self, forKey: .path)
        guides = try container.decodeIfPresent([SweepGuideReference].self, forKey: .guides) ?? []
        targets = try container.decodeIfPresent([SweepTargetReference].self, forKey: .targets) ?? []
        options = try container.decodeIfPresent(SweepOptions.self, forKey: .options) ?? SweepOptions()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(path, forKey: .path)
        try container.encode(guides, forKey: .guides)
        try container.encode(targets, forKey: .targets)
        try container.encode(options, forKey: .options)
    }

    public func validate() throws {
        guard profiles.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep features require at least one profile.")
        }
        let profileFeatureIDs = profiles.map(\.featureID)
        guard Set(profileFeatureIDs).count == profileFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Sweep profile references must be unique.")
        }
        try profiles.forEach { try $0.validate() }
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
        guard profileFeatureIDs.contains(path.featureID) == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep path must be distinct from every profile.")
        }
        let reservedCurveFeatureIDs = Set(profileFeatureIDs + [path.featureID])
        guard guideFeatureIDs.allSatisfy({ reservedCurveFeatureIDs.contains($0) == false }) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guides must be distinct from profiles and path.")
        }
        let reservedSourceFeatureIDs = reservedCurveFeatureIDs.union(guideFeatureIDs)
        guard targetFeatureIDs.allSatisfy({ reservedSourceFeatureIDs.contains($0) == false }) else {
            throw FeatureEvaluationError.invalidGraph("Sweep targets must be distinct from profiles, path, and guides.")
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

public struct SweepPathReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public struct SweepGuideReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}
}

public struct SweepTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
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
