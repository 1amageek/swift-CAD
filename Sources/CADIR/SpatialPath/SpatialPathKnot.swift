import CADCore
import CADGeometry

public enum SpatialPathKnotTag {}
public typealias SpatialPathKnotID = TaggedID<SpatialPathKnotTag>

public struct SpatialPathKnot: Hashable, Sendable, Identifiable {
    public enum Mode: String, Sendable {
        case corner, smooth, symmetric
    }

    public var id: SpatialPathKnotID
    public var position: Point3D
    public var incoming: Vector3D
    public var outgoing: Vector3D
    public var mode: Mode

    public init(
        id: SpatialPathKnotID = SpatialPathKnotID(), position: Point3D,
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, position, incoming, outgoing, mode }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.id, .position, .incoming, .outgoing, .mode], in: decoder)
        self.init(
            id: try values.decode(SpatialPathKnotID.self, forKey: .id),
            position: try values.decode(Point3D.self, forKey: .position),
            incoming: try values.decode(Vector3D.self, forKey: .incoming),
            outgoing: try values.decode(Vector3D.self, forKey: .outgoing),
            mode: try values.decode(Mode.self, forKey: .mode)
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(position, forKey: .position)
        try values.encode(incoming, forKey: .incoming)
        try values.encode(outgoing, forKey: .outgoing)
        try values.encode(mode, forKey: .mode)
    }
#endif
}

#if !hasFeature(Embedded)
extension SpatialPathKnot: Codable {}
extension SpatialPathKnot.Mode: Codable {}
#endif
