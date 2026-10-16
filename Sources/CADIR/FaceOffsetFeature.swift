import CADCore
import CADGeometry
import CADTopology

/// Push Face: faces of one body pushed a distance along their outward side, the faces around them
/// re-solved to meet them. With an adjacent angle, each planar face beside a pushed planar face
/// also tilts about the edge they shared by that angle, a positive angle leaning it out from the
/// pushed face.
public struct FaceOffsetFeature: Hashable, Sendable {
    public let target: FaceOffsetTargetReference
    public let faces: [StableSubshapeReference]
    public let distance: CADExpression
    public let adjacentAngle: CADExpression?
    public let grow: FaceEditGrow

    public init(
        target: FaceOffsetTargetReference,
        faces: [StableSubshapeReference],
        distance: CADExpression,
        adjacentAngle: CADExpression? = nil,
        grow: FaceEditGrow = .moving
    ) {
        self.target = target
        self.faces = faces
        self.distance = distance
        self.adjacentAngle = adjacentAngle
        self.grow = grow
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Push Face requires at least one face.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try execution.consumeWork(1)
            try face.validate(using: &execution)
            try face.chargeStructuralComparison(using: &execution)
            guard (try OriginalParameterQueryStorage.insert(face, in: &seen, using: &execution)) else {
                throw FeatureEvaluationError.invalidGraph("Push Face faces must be unique.")
            }
        }
        try distance.validateDocumentLiteralQuantities(using: &execution)
        try adjacentAngle?.validateDocumentLiteralQuantities(using: &execution)

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case faces
        case distance
        case adjacentAngle
        case grow
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces, .distance, .adjacentAngle, .grow], in: decoder)
        target = try container.decode(FaceOffsetTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        adjacentAngle = try container.decodeIfPresent(CADExpression.self, forKey: .adjacentAngle)
        grow = try container.decode(FaceEditGrow.self, forKey: .grow)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(distance, forKey: .distance)
        try container.encodeIfPresent(adjacentAngle, forKey: .adjacentAngle)
        try container.encode(grow, forKey: .grow)
    }
#endif
}

#if !hasFeature(Embedded)
extension FaceOffsetFeature: Codable {}
#endif
