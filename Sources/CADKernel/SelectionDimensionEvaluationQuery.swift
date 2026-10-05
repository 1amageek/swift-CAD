import CADCore

public struct SelectionDimensionEvaluationQuery: Sendable, Hashable {
    public var dimensionID: SelectionDimensionID?

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case dimensionID
    }
    #endif

    public init(dimensionID: SelectionDimensionID? = nil) {
        self.dimensionID = dimensionID
    }

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.dimensionID], in: decoder)
        dimensionID = try container.decodeIfPresent(
            SelectionDimensionID.self,
            forKey: .dimensionID
        )
    }
    #endif
}

#if !hasFeature(Embedded)
extension SelectionDimensionEvaluationQuery: Codable {}
#endif
