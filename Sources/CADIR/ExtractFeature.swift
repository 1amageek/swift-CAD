import CADCore
import CADTopology

/// Copies part of a body as a body of its own, leaving the source as it is: one component of a
/// body made of several (a slice's pieces), or chosen faces as a sheet.
public struct ExtractFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var selection: ExtractSelection

    public init(target: PatternTargetReference, selection: ExtractSelection) {
        self.target = target
        self.selection = selection
    }

    public func validate() throws {
        try target.validate()
        try selection.validate()
    }

    /// The output the extraction publishes from its source's: a component keeps the source's
    /// kind, faces are a sheet.
    public func resultPort(sourcePort: FeaturePort) throws -> FeaturePort {
        guard sourcePort == .body || sourcePort == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Extract needs a solid or sheet source.")
        }
        switch selection {
        case .component: return sourcePort
        case .faces: return .sheet
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target, selection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .selection], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        selection = try container.decode(ExtractSelection.self, forKey: .selection)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(selection, forKey: .selection)
    }
}

/// What an extraction copies.
public enum ExtractSelection: Hashable, Sendable {
    /// Component `index` of a body that has exactly `count` components, in the order of each
    /// component's smallest face identity; a source whose count changed is refused.
    case component(index: Int, count: Int)
    /// These faces of the body, as a sheet.
    case faces([StableSubshapeReference])

    public func validate() throws {
        switch self {
        case let .component(index, count):
            guard count >= 1, (0..<count).contains(index) else {
                throw FeatureEvaluationError.invalidGraph("Extract component index must lie within its component count.")
            }
        case let .faces(faces):
            guard faces.isEmpty == false else {
                throw FeatureEvaluationError.invalidGraph("Extract faces requires at least one face.")
            }
            var seen = Set<StableSubshapeReference>()
            for face in faces {
                try face.validate()
                guard seen.insert(face).inserted else {
                    throw FeatureEvaluationError.invalidGraph("Extract faces must be unique.")
                }
            }
        }
    }
}

extension ExtractSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, index, count, faces
    }

    private enum Kind: String, Codable {
        case component, faces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .component:
            try container.validateOnlyExpectedKeys([.kind, .index, .count], in: decoder)
            self = .component(index: try container.decode(Int.self, forKey: .index), count: try container.decode(Int.self, forKey: .count))
        case .faces:
            try container.validateOnlyExpectedKeys([.kind, .faces], in: decoder)
            self = .faces(try container.decode([StableSubshapeReference].self, forKey: .faces))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .component(index, count):
            try container.encode(Kind.component, forKey: .kind)
            try container.encode(index, forKey: .index)
            try container.encode(count, forKey: .count)
        case let .faces(faces):
            try container.encode(Kind.faces, forKey: .kind)
            try container.encode(faces, forKey: .faces)
        }
    }
}
