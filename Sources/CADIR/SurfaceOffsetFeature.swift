import CADCore
import CADGeometry

public struct SurfaceOffsetFeature: Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let distance: CADExpression

    public init(
        target: SurfaceOperationTargetReference,
        distance: CADExpression
    ) {
        self.target = target
        self.distance = distance
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate(using: &execution)
        try distance.validateDocumentLiteralQuantities(using: &execution)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case distance
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .distance], in: decoder)
        target = try container.decode(SurfaceOperationTargetReference.self, forKey: .target)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(distance, forKey: .distance)
    }
#endif
}

#if !hasFeature(Embedded)
extension SurfaceOffsetFeature: Codable {}
#endif
