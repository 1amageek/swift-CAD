import CADCore

public enum FeaturePort: String, Codable, Sendable, Hashable {
    case profile
    case curve
    case path
    case guide
    case target
    case body
    case sheet
}

public struct FeatureNode: Codable, Sendable, Hashable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case operation
        case inputs
        case outputs
        case isSuppressed
    }

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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(operation, forKey: .operation)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(isSuppressed, forKey: .isSuppressed)
    }
}

public struct FeatureInput: Codable, Sendable, Hashable {
    public var featureID: FeatureID
    public var role: FeaturePort

    public init(featureID: FeatureID, role: FeaturePort) {
        self.featureID = featureID
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case featureID
        case role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .role], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        role = try container.decode(FeaturePort.self, forKey: .role)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encode(role, forKey: .role)
    }
}

public struct FeatureOutput: Codable, Sendable, Hashable {
    public var role: FeaturePort
    public var persistentName: PersistentName?

    public init(role: FeaturePort, persistentName: PersistentName? = nil) {
        self.role = role
        self.persistentName = persistentName
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case persistentName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.role, .persistentName], in: decoder)
        role = try container.decode(FeaturePort.self, forKey: .role)
        persistentName = try container.decodeIfPresent(PersistentName.self, forKey: .persistentName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(persistentName, forKey: .persistentName)
    }
}
