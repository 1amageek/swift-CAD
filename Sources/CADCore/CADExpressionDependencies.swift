public extension CADExpression {
    var referencedParameterIDs: Set<ParameterID> {
        switch self {
        case .constant, .variable:
            return []
        case let .reference(parameterID):
            return [parameterID]
        case let .add(left, right),
             let .subtract(left, right),
             let .multiply(left, right),
             let .divide(left, right),
             let .hypot(left, right):
            return left.referencedParameterIDs.union(right.referencedParameterIDs)
        case let .bezierNaturalExtension(coordinates, length, _):
            return coordinates.reduce(length.referencedParameterIDs) { $0.union($1.referencedParameterIDs) }
        case let .sin(argument),
             let .cos(argument),
             let .tan(argument):
            return argument.referencedParameterIDs
        }
    }
}
