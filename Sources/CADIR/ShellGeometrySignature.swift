import CADCore
import CADTopology

public struct ShellGeometrySignature: Codable, Hashable, Sendable {
    public let orientation: Orientation
    public let faces: [FaceGeometrySignature]

    public init(orientation: Orientation, faces: [FaceGeometrySignature]) {
        self.orientation = orientation
        self.faces = faces
    }

    public func validate() throws {
        guard faces.isEmpty == false else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Shell geometry signature requires at least one face."
            )
        }
        for face in faces {
            try face.validate()
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case orientation
        case faces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(Set(CodingKeys.allCases), in: decoder)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        faces = try container.decode([FaceGeometrySignature].self, forKey: .faces)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(faces, forKey: .faces)
    }
}
