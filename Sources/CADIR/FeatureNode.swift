import CADCore

public enum FeaturePort: String, Sendable, Hashable {
    case profile
    case curve
    case path
    case guide
    case target
    case body
    case sheet
}

public struct FeatureNode: Sendable, Hashable {
    public var id: FeatureID
    public var name: String?
    public var operation: FeatureOperation
    public var inputs: [FeatureInput]
    public var outputs: [FeatureOutput]
    public var isSuppressed: Bool

    public init(
        id: FeatureID = FeatureID(),
        name: String? = nil,
        operation: FeatureOperation,
        inputs: [FeatureInput] = [],
        outputs: [FeatureOutput] = [],
        isSuppressed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.operation = operation
        self.inputs = inputs
        self.outputs = outputs
        self.isSuppressed = isSuppressed
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case operation
        case inputs
        case outputs
        case isSuppressed
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .name, .operation, .inputs, .outputs, .isSuppressed], in: decoder)
        id = try container.decode(FeatureID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        operation = try container.decode(FeatureOperation.self, forKey: .operation)
        inputs = try container.decode([FeatureInput].self, forKey: .inputs)
        outputs = try container.decode([FeatureOutput].self, forKey: .outputs)
        isSuppressed = try container.decode(Bool.self, forKey: .isSuppressed)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(operation, forKey: .operation)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(isSuppressed, forKey: .isSuppressed)
    }
#endif
}

public struct FeatureInput: Sendable, Hashable {
    public var featureID: FeatureID
    public var role: FeaturePort

    public init(featureID: FeatureID, role: FeaturePort) {
        self.featureID = featureID
        self.role = role
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case featureID
        case role
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .role], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        role = try container.decode(FeaturePort.self, forKey: .role)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encode(role, forKey: .role)
    }
#endif
}

public struct FeatureOutput: Sendable, Hashable {
    public var role: FeaturePort

    public init(role: FeaturePort) {
        self.role = role
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case role
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.role], in: decoder)
        role = try container.decode(FeaturePort.self, forKey: .role)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
    }
#endif
}

extension FeatureNode {
    /// The solid (`body`) or sheet output this feature declares, if it declares exactly one.
    public var bodyOrSheetOutput: FeaturePort? {
        let ports = Set(outputs.map { $0.role }).intersection([.body, .sheet])
        return ports.count == 1 ? ports.first : nil
    }
}

#if !hasFeature(Embedded)
extension FeaturePort: Codable {}
extension FeatureNode: Codable {}
extension FeatureInput: Codable {}
extension FeatureOutput: Codable {}
#endif
