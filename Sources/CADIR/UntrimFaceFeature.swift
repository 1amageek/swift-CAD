import CADCore
import CADGeometry
import CADTopology

/// A sheet of a face's surface as it was before the face was trimmed, beside the body, which
/// stays as it is. In each parameter direction the sheet spans the surface's own bounded domain;
/// where the surface is unbounded or periodic it spans the face's extent, the whole period when
/// the face goes all the way around. A native cone generator extends to its exact apex; an
/// extent crossing the apex produces separate finite faces and sheet shells for both nappes.
/// With `keepsEdges` the face's own boundary is imprinted on
/// the sheet, so the trimmed region stays a face of its own.
public struct UntrimFaceFeature: Hashable, Sendable {
    public var target: PatternTargetReference
    public var face: StableSubshapeReference
    public var keepsEdges: Bool

    public init(target: PatternTargetReference, face: StableSubshapeReference, keepsEdges: Bool) {
        self.target = target
        self.face = face
        self.keepsEdges = keepsEdges
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try face.validate(using: &execution)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target, face, keepsEdges
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .keepsEdges], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        keepsEdges = try container.decode(Bool.self, forKey: .keepsEdges)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(keepsEdges, forKey: .keepsEdges)
    }
#endif
}

#if !hasFeature(Embedded)
extension UntrimFaceFeature: Codable {}
#endif
