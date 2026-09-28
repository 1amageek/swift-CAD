public indirect enum CADExpression: Codable, Sendable, Hashable {
    case constant(Quantity)
    case reference(ParameterID)
    case variable(String, QuantityKind)
    case add(CADExpression, CADExpression)
    case subtract(CADExpression, CADExpression)
    case multiply(CADExpression, CADExpression)
    case divide(CADExpression, CADExpression)
    case hypot(CADExpression, CADExpression)
    case bezierNaturalExtension(coordinates: [CADExpression], length: CADExpression, coordinateIndex: Int)
    /// One coordinate of Extend Curve's Arc, Soft or Reflective shape, evaluated from the curve's
    /// own Bezier control points (`BezierShapedExtension`).
    case bezierShapedExtension(shape: BezierExtensionShape, coordinates: [CADExpression], length: CADExpression, coordinateIndex: Int)
    case sin(CADExpression)
    case cos(CADExpression)
    case tan(CADExpression)

    private enum CodingKeys: String, CodingKey {
        case kind
        case quantity
        case parameterID
        case name
        case quantityKind
        case left
        case right
        case argument
        case coordinates, length, coordinateIndex
        case shape
    }

    private enum Kind: String, Codable {
        case constant
        case reference
        case variable
        case add
        case subtract
        case multiply
        case divide
        case hypot
        case bezierNaturalExtension
        case bezierShapedExtension
        case sin
        case cos
        case tan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .constant:
            try container.validateOnlyExpectedKeys([.kind, .quantity], in: decoder)
            self = .constant(try container.decode(Quantity.self, forKey: .quantity))
        case .reference:
            try container.validateOnlyExpectedKeys([.kind, .parameterID], in: decoder)
            self = .reference(try container.decode(ParameterID.self, forKey: .parameterID))
        case .variable:
            try container.validateOnlyExpectedKeys([.kind, .name, .quantityKind], in: decoder)
            self = .variable(
                try container.decode(String.self, forKey: .name),
                try container.decode(QuantityKind.self, forKey: .quantityKind)
            )
        case .add:
            try container.validateOnlyExpectedKeys([.kind, .left, .right], in: decoder)
            self = .add(
                try container.decode(CADExpression.self, forKey: .left),
                try container.decode(CADExpression.self, forKey: .right)
            )
        case .subtract:
            try container.validateOnlyExpectedKeys([.kind, .left, .right], in: decoder)
            self = .subtract(
                try container.decode(CADExpression.self, forKey: .left),
                try container.decode(CADExpression.self, forKey: .right)
            )
        case .multiply:
            try container.validateOnlyExpectedKeys([.kind, .left, .right], in: decoder)
            self = .multiply(
                try container.decode(CADExpression.self, forKey: .left),
                try container.decode(CADExpression.self, forKey: .right)
            )
        case .divide:
            try container.validateOnlyExpectedKeys([.kind, .left, .right], in: decoder)
            self = .divide(
                try container.decode(CADExpression.self, forKey: .left),
                try container.decode(CADExpression.self, forKey: .right)
            )
        case .hypot:
            try container.validateOnlyExpectedKeys([.kind, .left, .right], in: decoder)
            self = .hypot(
                try container.decode(CADExpression.self, forKey: .left),
                try container.decode(CADExpression.self, forKey: .right)
            )
        case .bezierNaturalExtension:
            try container.validateOnlyExpectedKeys([.kind, .coordinates, .length, .coordinateIndex], in: decoder)
            let coordinates = try container.decode([CADExpression].self, forKey: .coordinates)
            let index = try container.decode(Int.self, forKey: .coordinateIndex)
            try NaturalBezierContinuation.validateCoordinateForm(count: coordinates.count, index: index)
            self = .bezierNaturalExtension(coordinates: coordinates,
                length: try container.decode(CADExpression.self, forKey: .length), coordinateIndex: index)
        case .bezierShapedExtension:
            try container.validateOnlyExpectedKeys([.kind, .shape, .coordinates, .length, .coordinateIndex], in: decoder)
            let shape = try container.decode(BezierExtensionShape.self, forKey: .shape)
            let coordinates = try container.decode([CADExpression].self, forKey: .coordinates)
            let index = try container.decode(Int.self, forKey: .coordinateIndex)
            try BezierShapedExtension.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
            self = .bezierShapedExtension(shape: shape, coordinates: coordinates,
                length: try container.decode(CADExpression.self, forKey: .length), coordinateIndex: index)
        case .sin:
            try container.validateOnlyExpectedKeys([.kind, .argument], in: decoder)
            self = .sin(try container.decode(CADExpression.self, forKey: .argument))
        case .cos:
            try container.validateOnlyExpectedKeys([.kind, .argument], in: decoder)
            self = .cos(try container.decode(CADExpression.self, forKey: .argument))
        case .tan:
            try container.validateOnlyExpectedKeys([.kind, .argument], in: decoder)
            self = .tan(try container.decode(CADExpression.self, forKey: .argument))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .constant(quantity):
            try container.encode(Kind.constant, forKey: .kind)
            try container.encode(quantity, forKey: .quantity)
        case let .reference(parameterID):
            try container.encode(Kind.reference, forKey: .kind)
            try container.encode(parameterID, forKey: .parameterID)
        case let .variable(name, quantityKind):
            try container.encode(Kind.variable, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(quantityKind, forKey: .quantityKind)
        case let .add(left, right):
            try encodeBinary(.add, left, right, into: &container)
        case let .subtract(left, right):
            try encodeBinary(.subtract, left, right, into: &container)
        case let .multiply(left, right):
            try encodeBinary(.multiply, left, right, into: &container)
        case let .divide(left, right):
            try encodeBinary(.divide, left, right, into: &container)
        case let .hypot(left, right):
            try encodeBinary(.hypot, left, right, into: &container)
        case let .bezierNaturalExtension(coordinates, length, index):
            try NaturalBezierContinuation.validateCoordinateForm(count: coordinates.count, index: index)
            try container.encode(Kind.bezierNaturalExtension, forKey: .kind)
            try container.encode(coordinates, forKey: .coordinates)
            try container.encode(length, forKey: .length)
            try container.encode(index, forKey: .coordinateIndex)
        case let .bezierShapedExtension(shape, coordinates, length, index):
            try BezierShapedExtension.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
            try container.encode(Kind.bezierShapedExtension, forKey: .kind)
            try container.encode(shape, forKey: .shape)
            try container.encode(coordinates, forKey: .coordinates)
            try container.encode(length, forKey: .length)
            try container.encode(index, forKey: .coordinateIndex)
        case let .sin(argument):
            try encodeUnary(.sin, argument, into: &container)
        case let .cos(argument):
            try encodeUnary(.cos, argument, into: &container)
        case let .tan(argument):
            try encodeUnary(.tan, argument, into: &container)
        }
    }

    private func encodeBinary(
        _ kind: Kind,
        _ left: CADExpression,
        _ right: CADExpression,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
    }

    private func encodeUnary(
        _ kind: Kind,
        _ argument: CADExpression,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(argument, forKey: .argument)
    }

    public func validateLiteralQuantities() throws {
        switch self {
        case let .constant(quantity):
            try quantity.validate()
        case .reference, .variable:
            return
        case let .add(left, right),
             let .subtract(left, right),
             let .multiply(left, right),
             let .divide(left, right),
             let .hypot(left, right):
            try left.validateLiteralQuantities()
            try right.validateLiteralQuantities()
        case let .bezierNaturalExtension(coordinates, length, index):
            try NaturalBezierContinuation.validateCoordinateForm(count: coordinates.count, index: index)
            for coordinate in coordinates { try coordinate.validateLiteralQuantities() }
            try length.validateLiteralQuantities()
        case let .bezierShapedExtension(shape, coordinates, length, index):
            try BezierShapedExtension.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
            for coordinate in coordinates { try coordinate.validateLiteralQuantities() }
            try length.validateLiteralQuantities()
        case let .sin(argument),
             let .cos(argument),
             let .tan(argument):
            try argument.validateLiteralQuantities()
        }
    }
}
