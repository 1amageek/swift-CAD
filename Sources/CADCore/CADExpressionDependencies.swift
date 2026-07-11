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
             let .divide(left, right):
            return left.referencedParameterIDs.union(right.referencedParameterIDs)
        case let .sin(argument),
             let .cos(argument),
             let .tan(argument):
            return argument.referencedParameterIDs
        }
    }
}
