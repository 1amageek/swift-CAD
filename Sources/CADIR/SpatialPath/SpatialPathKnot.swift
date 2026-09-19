import Foundation
import CADCore

public struct SpatialPathKnot: Codable, Hashable, Sendable, Identifiable {
    public enum Mode: String, Codable, Sendable {
        case corner, smooth, symmetric
    }

    public var id: UUID
    public var position: Point3D
    public var incoming: Vector3D
    public var outgoing: Vector3D
    public var mode: Mode

    public init(
        id: UUID = UUID(), position: Point3D,
        incoming: Vector3D = .zero, outgoing: Vector3D = .zero,
        mode: Mode = .corner
    ) {
        self.id = id
        self.position = position
        self.incoming = incoming
        self.outgoing = outgoing
        self.mode = mode
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try position.validate()
        try incoming.validate()
        try outgoing.validate()
        try (position + incoming).validate()
        try (position + outgoing).validate()
        guard incoming.length.isFinite, outgoing.length.isFinite else {
            throw FeatureEvaluationError.invalidGraph("Spatial path tangent length must be finite.")
        }
        switch mode {
        case .corner:
            break
        case .symmetric:
            guard (incoming + outgoing).length <= tolerance.distance else {
                throw FeatureEvaluationError.invalidGraph("Symmetric path tangents must be opposite and equal.")
            }
        case .smooth:
            if incoming.length <= tolerance.distance, outgoing.length <= tolerance.distance { return }
            let first = try incoming.normalized(tolerance: tolerance.distance)
            let second = try outgoing.normalized(tolerance: tolerance.distance)
            guard (first + second).length <= max(tolerance.angle, 32 * Double.ulpOfOne) else {
                throw FeatureEvaluationError.invalidGraph("Smooth path tangents must be opposite and collinear.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case id, position, incoming, outgoing, mode }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.id, .position, .incoming, .outgoing, .mode], in: decoder)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            position: try values.decode(Point3D.self, forKey: .position),
            incoming: try values.decode(Vector3D.self, forKey: .incoming),
            outgoing: try values.decode(Vector3D.self, forKey: .outgoing),
            mode: try values.decode(Mode.self, forKey: .mode)
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(position, forKey: .position)
        try values.encode(incoming, forKey: .incoming)
        try values.encode(outgoing, forKey: .outgoing)
        try values.encode(mode, forKey: .mode)
    }
}
