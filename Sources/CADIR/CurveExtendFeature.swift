import CADCore

public struct CurveExtendFeature: Codable, Hashable, Sendable {
    public let source: CurveOutputReference
    public let end: CurveExtensionEnd
    public let distance: CADExpression

    public init(
        source: CurveOutputReference,
        end: CurveExtensionEnd,
        distance: CADExpression
    ) {
        self.source = source
        self.end = end
        self.distance = distance
    }

    public func validate() throws {
        try source.validate()
        try distance.validateLiteralQuantities()
    }
}
