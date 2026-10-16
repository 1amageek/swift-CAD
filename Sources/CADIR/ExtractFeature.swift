import CADCore
import CADGeometry
import CADTopology

/// Copies part of a body as a body of its own, leaving the source as it is: one component of a
/// body made of several (a slice's pieces), chosen faces as a sheet, or chosen faces that close
/// as a solid.
public struct ExtractFeature: Hashable, Sendable {
    public var target: PatternTargetReference
    public var selection: ExtractSelection

    public init(target: PatternTargetReference, selection: ExtractSelection) {
        self.target = target
        self.selection = selection
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try selection.validate(using: &execution)

        try execution.checkpoint()
    }

    /// The output the extraction publishes from its source's: a component keeps the source's
    /// kind, faces are a sheet, and faces that close are a solid of a solid source.
    public func resultPort(sourcePort: FeaturePort) throws -> FeaturePort {
        guard sourcePort == .body || sourcePort == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Extract needs a solid or sheet source.")
        }
        switch selection {
        case .component: return sourcePort
        case .faces: return .sheet
        case .solidFaces:
            guard sourcePort == .body else {
                throw FeatureEvaluationError.invalidGraph("Faces close into a solid only on a solid source.")
            }
            return .body
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target, selection
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .selection], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        selection = try container.decode(ExtractSelection.self, forKey: .selection)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(selection, forKey: .selection)
    }
#endif
}

/// What an extraction copies.
public enum ExtractSelection: Hashable, Sendable {
    /// Component `index` of a body that has exactly `count` components, in the order of each
    /// component's smallest face identity; a source whose count changed is refused.
    case component(index: Int, count: Int)
    /// These faces of the body, as a sheet.
    case faces([StableSubshapeReference])
    /// These faces of a solid body, every face of each shell they lie on, as a solid: a chosen
    /// outer shell keeps the chosen voids inside it, and a void chosen without its outer shell is
    /// a solid of the cavity's shape.
    case solidFaces([StableSubshapeReference])

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .component(index, count):
            guard count >= 1, (0..<count).contains(index) else {
                throw FeatureEvaluationError.invalidGraph("Extract component index must lie within its component count.")
            }
        case let .faces(faces), let .solidFaces(faces):
            guard faces.isEmpty == false else {
                throw FeatureEvaluationError.invalidGraph("Extract faces requires at least one face.")
            }
            var seen = Set<StableSubshapeReference>()
            for face in faces {
                try execution.consumeWork(1)
                try face.validate(using: &execution)
                try face.chargeStructuralComparison(using: &execution)
                guard (try OriginalParameterQueryStorage.insert(face, in: &seen, using: &execution)) else {
                    throw FeatureEvaluationError.invalidGraph("Extract faces must be unique.")
                }
            }
        }

        try execution.checkpoint()
    }
}

#if !hasFeature(Embedded)
extension ExtractSelection: Codable {
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind, index, count, faces
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case component, faces, solidFaces
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .component:
            try container.validateOnlyExpectedKeys([.kind, .index, .count], in: decoder)
            self = .component(index: try container.decode(Int.self, forKey: .index), count: try container.decode(Int.self, forKey: .count))
        case .faces:
            try container.validateOnlyExpectedKeys([.kind, .faces], in: decoder)
            self = .faces(try container.decode([StableSubshapeReference].self, forKey: .faces))
        case .solidFaces:
            try container.validateOnlyExpectedKeys([.kind, .faces], in: decoder)
            self = .solidFaces(try container.decode([StableSubshapeReference].self, forKey: .faces))
        }
    }
#endif

#if !hasFeature(Embedded)
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
        case let .solidFaces(faces):
            try container.encode(Kind.solidFaces, forKey: .kind)
            try container.encode(faces, forKey: .faces)
        }
    }
#endif
}
#endif

#if !hasFeature(Embedded)
#if !hasFeature(Embedded)
extension ExtractFeature: Codable {}
#endif
#endif
