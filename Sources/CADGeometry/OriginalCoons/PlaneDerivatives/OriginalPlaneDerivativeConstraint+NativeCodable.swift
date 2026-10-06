#if !hasFeature(Embedded)
import CADCore

extension OriginalPlaneDerivativeConstraint: Codable {
    private enum CodingKeys: String, CodingKey { case surface, order }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.surface,.order],in:decoder)
        try self.init(surface:c.decode(Surface3D.self,forKey:.surface),
            order:c.decode(OriginalPlaneDerivativeOrder.self,forKey:.order))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(surface,forKey:.surface); try c.encode(order,forKey:.order)
    }
}
extension OriginalPlaneDerivativeOrder: Codable {}
#endif
