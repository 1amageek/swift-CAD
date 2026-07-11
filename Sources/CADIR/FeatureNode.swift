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
}

public struct FeatureInput: Codable, Sendable, Hashable {
    public var featureID: FeatureID
    public var role: FeaturePort

    public init(featureID: FeatureID, role: FeaturePort) {
        self.featureID = featureID
        self.role = role
    }
}

public struct FeatureOutput: Codable, Sendable, Hashable {
    public var role: FeaturePort
    public var persistentName: PersistentName?

    public init(role: FeaturePort, persistentName: PersistentName? = nil) {
        self.role = role
        self.persistentName = persistentName
    }
}
