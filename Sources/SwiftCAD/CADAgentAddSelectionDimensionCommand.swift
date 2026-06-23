import CADCore
import CADIR

public struct CADAgentAddSelectionDimensionCommand: Codable, Sendable, Hashable {
    public var dimensionID: SelectionDimensionID?
    public var name: String?
    public var kind: SelectionDimensionKind
    public var first: SelectionReference
    public var second: SelectionReference
    public var target: CADExpression

    private enum CodingKeys: String, CodingKey {
        case dimensionID
        case name
        case kind
        case first
        case second
        case target
    }

    public init(
        dimensionID: SelectionDimensionID? = nil,
        name: String? = nil,
        kind: SelectionDimensionKind,
        first: SelectionReference,
        second: SelectionReference,
        target: CADExpression
    ) {
        self.dimensionID = dimensionID
        self.name = name
        self.kind = kind
        self.first = first
        self.second = second
        self.target = target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .dimensionID,
            .name,
            .kind,
            .first,
            .second,
            .target,
        ], in: decoder)
        dimensionID = try container.decodeIfPresent(SelectionDimensionID.self, forKey: .dimensionID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        kind = try container.decode(SelectionDimensionKind.self, forKey: .kind)
        first = try container.decode(SelectionReference.self, forKey: .first)
        second = try container.decode(SelectionReference.self, forKey: .second)
        target = try container.decode(CADExpression.self, forKey: .target)
    }

    public func selectionDimension() -> SelectionDimension {
        SelectionDimension(
            id: dimensionID ?? SelectionDimensionID(),
            name: name,
            kind: kind,
            first: first,
            second: second,
            target: target
        )
    }
}
