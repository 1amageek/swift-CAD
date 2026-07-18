import Foundation
import CADCore

public struct SelectionDimension: Codable, Sendable, Hashable {
    public var id: SelectionDimensionID
    public var name: String?
    public var kind: SelectionDimensionKind
    public var first: SelectionReference
    public var second: SelectionReference
    public var target: CADExpression

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case first
        case second
        case target
    }

    public init(
        id: SelectionDimensionID = SelectionDimensionID(),
        name: String? = nil,
        kind: SelectionDimensionKind,
        first: SelectionReference,
        second: SelectionReference,
        target: CADExpression
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.first = first
        self.second = second
        self.target = target
    }

    public func validate(
        parameters: ParameterTable = ParameterTable(),
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try first.validate()
        try second.validate()
        let quantity = try parameters.resolvedValue(for: target)
        guard quantity.kind == kind.quantityKind else {
            throw UnitError.expectedQuantity(
                operation: "selection.dimension.target",
                expected: kind.quantityKind,
                actual: quantity.kind
            )
        }
        switch kind {
        case .distance:
            guard quantity.value >= 0.0 else {
                throw GeometryError.invalidDistance(quantity.value)
            }
        case .angle:
            guard quantity.value >= 0.0,
                  quantity.value <= Double.pi + tolerance.angle else {
                throw GeometryError.invalidAngle(quantity.value)
            }
        }
    }
}
