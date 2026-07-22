import CADCore
import CADGeometry
import CADTopology

public struct LoopGeometrySignature: Codable, Hashable, Sendable {
    public let role: LoopRole
    public let coedges: [CoedgeGeometrySignature]

    public init(role: LoopRole, coedges: [CoedgeGeometrySignature]) {
        self.role = role
        self.coedges = coedges
    }

    public func validate(on surface: Surface3D) throws {
        guard coedges.isEmpty == false else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Loop geometry signature requires at least one coedge."
            )
        }
        for coedge in coedges {
            try coedge.validate(on: surface)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case coedges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        role = try container.decode(LoopRole.self, forKey: .role)
        coedges = try container.decode([CoedgeGeometrySignature].self, forKey: .coedges)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(coedges, forKey: .coedges)
    }
}
