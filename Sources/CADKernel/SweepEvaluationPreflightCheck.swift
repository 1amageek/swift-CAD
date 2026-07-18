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
