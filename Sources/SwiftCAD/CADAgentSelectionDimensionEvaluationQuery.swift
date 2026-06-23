import CADCore

public struct CADAgentSelectionDimensionEvaluationQuery: Codable, Sendable, Hashable {
    public var dimensionID: SelectionDimensionID?

    private enum CodingKeys: String, CodingKey {
        case dimensionID
    }

    public init(dimensionID: SelectionDimensionID? = nil) {
        self.dimensionID = dimensionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.dimensionID], in: decoder)
        dimensionID = try container.decodeIfPresent(SelectionDimensionID.self, forKey: .dimensionID)
    }
}
