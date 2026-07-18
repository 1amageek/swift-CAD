import CADCore

public enum FeatureEvaluationState: Codable, Sendable, Hashable {
    case unevaluated
    case evaluated
    case suppressed
    case blocked(upstreamFeatureID: FeatureID)
    case failed(FeatureFailure)

    private enum CodingKeys: String, CodingKey {
        case kind
        case failure
        case upstreamFeatureID
    }

    private enum Kind: String, Codable {
        case unevaluated
        case evaluated
        case suppressed
        case blocked
        case failed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .unevaluated:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .unevaluated
        case .evaluated:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .evaluated
        case .suppressed:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .suppressed
        case .blocked:
            try container.validateOnlyExpectedKeys([.kind, .upstreamFeatureID], in: decoder)
            self = .blocked(upstreamFeatureID: try container.decode(FeatureID.self, forKey: .upstreamFeatureID))
        case .failed:
            try container.validateOnlyExpectedKeys([.kind, .failure], in: decoder)
            self = .failed(try container.decode(FeatureFailure.self, forKey: .failure))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unevaluated:
            try container.encode(Kind.unevaluated, forKey: .kind)
        case .evaluated:
            try container.encode(Kind.evaluated, forKey: .kind)
        case .suppressed:
            try container.encode(Kind.suppressed, forKey: .kind)
        case let .blocked(upstreamFeatureID):
            try container.encode(Kind.blocked, forKey: .kind)
            try container.encode(upstreamFeatureID, forKey: .upstreamFeatureID)
        case let .failed(failure):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(failure, forKey: .failure)
        }
    }
}

public struct FeatureFailure: Codable, Sendable, Hashable {
    public var featureID: FeatureID
    public var message: String
    public var invalidatedFeatureIDs: [FeatureID]

    public init(featureID: FeatureID, message: String, invalidatedFeatureIDs: [FeatureID]) {
        self.featureID = featureID
        self.message = message
        self.invalidatedFeatureIDs = invalidatedFeatureIDs
    }

    public func validate() throws {
        guard !message.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Feature failure message must not be empty.")
        }
        guard !invalidatedFeatureIDs.contains(featureID) else {
            throw FeatureEvaluationError.invalidGraph("Feature failure invalidation list must not contain the failing feature.")
        }
        guard Set(invalidatedFeatureIDs).count == invalidatedFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Feature failure invalidation list contains duplicates.")
        }
    }
}

public extension DesignGraph {
    func invalidatedFeatureIDs(
        after featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [FeatureID] {
        try validate(tolerance: tolerance)
        return try invalidatedFeatureIDsInValidatedGraph(after: featureID)
    }
}

package extension DesignGraph {
    func invalidatedFeatureIDsInValidatedGraph(after featureID: FeatureID) throws -> [FeatureID] {
        guard nodes[featureID] != nil else {
            throw FeatureEvaluationError.invalidGraph("Cannot invalidate from a missing feature.")
        }
        var adjacency: [FeatureID: [FeatureID]] = [:]
        adjacency.reserveCapacity(nodes.count)
        for dependency in dependencies {
            adjacency[dependency.source, default: []].append(dependency.target)
        }
        var visited = Set<FeatureID>()
        visited.reserveCapacity(nodes.count)
        var pending = adjacency[featureID, default: []]
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            pending.append(contentsOf: adjacency[current, default: []])
        }
        return order.filter { visited.contains($0) }
    }
}
