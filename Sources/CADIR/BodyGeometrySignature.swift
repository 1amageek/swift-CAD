import CADCore
import CADTopology

public struct BodyGeometrySignature: Codable, Hashable, Sendable {
    public let kind: BodyKind
    public let shells: [ShellGeometrySignature]

    public init(kind: BodyKind, shells: [ShellGeometrySignature]) {
        self.kind = kind
        self.shells = shells
    }

    public func validate() throws {
        guard shells.isEmpty == false else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Body geometry signature requires at least one shell."
            )
        }
        for shell in shells {
            try shell.validate()
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case shells
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        kind = try container.decode(BodyKind.self, forKey: .kind)
        shells = try container.decode([ShellGeometrySignature].self, forKey: .shells)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(shells, forKey: .shells)
    }
}
