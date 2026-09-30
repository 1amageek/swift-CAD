import CADCore
import CADTopology

/// Separates a body into sheets in its place: each chosen face (every face, when every face is
/// chosen) becomes a shell of its own, and the faces left keep together as one shell per piece
/// that still hangs together. The result is one sheet body whose shells are those pieces; the
/// source body is consumed.
public struct UnjoinFacesFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var selection: UnjoinFacesSelection

    public init(target: PatternTargetReference, selection: UnjoinFacesSelection) {
        self.target = target
        self.selection = selection
    }

    public func validate() throws {
        try target.validate()
        try selection.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case target, selection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .selection], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        selection = try container.decode(UnjoinFacesSelection.self, forKey: .selection)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(selection, forKey: .selection)
    }
}

/// Which faces an unjoin separates.
public enum UnjoinFacesSelection: Hashable, Sendable {
    /// Every face of the body, each a sheet of its own.
    case everyFace
    /// These faces, each a sheet of its own; the rest stay joined where they still meet.
    case faces([StableSubshapeReference])

    public func validate() throws {
        guard case let .faces(faces) = self else { return }
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces requires at least one face.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try face.validate()
            guard seen.insert(face).inserted else {
                throw FeatureEvaluationError.invalidGraph("Unjoin faces must be unique.")
            }
        }
    }
}

extension UnjoinFacesSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, faces
    }

    private enum Kind: String, Codable {
        case everyFace, faces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .everyFace:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .everyFace
        case .faces:
            try container.validateOnlyExpectedKeys([.kind, .faces], in: decoder)
            self = .faces(try container.decode([StableSubshapeReference].self, forKey: .faces))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .everyFace:
            try container.encode(Kind.everyFace, forKey: .kind)
        case let .faces(faces):
            try container.encode(Kind.faces, forKey: .kind)
            try container.encode(faces, forKey: .faces)
        }
    }
}
