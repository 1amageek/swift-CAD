import CADCore
import CADTopology

public struct ShellFeature: Codable, Hashable, Sendable {
    public let target: ShellTargetReference
    public let removedFaces: [StableSubshapeReference]
    public let thickness: CADExpression

    public init(
        target: ShellTargetReference,
        removedFaces: [StableSubshapeReference],
        thickness: CADExpression
    ) {
        self.target = target
        self.removedFaces = removedFaces
        self.thickness = thickness
    }

    public func validate() throws {
        try target.validate()
        guard removedFaces.isEmpty == false,
              Set(removedFaces).count == removedFaces.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Shell requires unique removed face selections."
            )
        }
        for face in removedFaces {
            try face.validate()
            guard case .face = face.geometrySignature else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: face.subshapeID,
                    tolerance: nil,
                    message: "Shell removal selections must be faces."
                )
            }
        }
        try thickness.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case removedFaces
        case thickness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .removedFaces, .thickness], in: decoder)
        target = try container.decode(ShellTargetReference.self, forKey: .target)
        removedFaces = try container.decode([StableSubshapeReference].self, forKey: .removedFaces)
        thickness = try container.decode(CADExpression.self, forKey: .thickness)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(removedFaces, forKey: .removedFaces)
        try container.encode(thickness, forKey: .thickness)
    }
}
