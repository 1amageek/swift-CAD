import Foundation
import CADCore
import CADIR

public struct ParameterResolver: ParameterResolving {
    public init() {}

    public func resolve(_ table: ParameterTable) throws -> ResolvedParameterTable {
        try table.validate()

        var names: [String: ParameterID] = [:]
        for parameter in table.parameters.values {
            if names[parameter.name] != nil {
                throw ParameterError.duplicateName(parameter.name)
            }
            names[parameter.name] = parameter.id
        }

        var state = ResolutionState(table: table)

        for parameterID in table.parameters.keys {
            _ = try state.resolve(parameterID)
        }

        return ResolvedParameterTable(values: state.resolved, names: names)
    }

    public func evaluate(
        _ expression: CADCore.CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity] = [:]
    ) throws -> Quantity {
        try evaluateExpression(
            expression,
            parameterValue: { parameterID in
                try parameters.value(for: parameterID)
            },
            variableValue: { name, expectedKind in
            guard let value = variables[name] else {
                throw ParameterError.unknownVariable(name)
            }
            guard value.kind == expectedKind else {
                throw UnitError.expectedQuantity(operation: "variable", expected: expectedKind, actual: value.kind)
            }
            return value
            }
        )
    }

    private struct ResolutionState {
        var table: ParameterTable
        var resolved: [ParameterID: Quantity] = [:]
        var visiting: [ParameterID] = []

        mutating func resolve(_ parameterID: ParameterID) throws -> Quantity {
            if let value = resolved[parameterID] {
                return value
            }
            guard let parameter = table.parameters[parameterID] else {
                throw ParameterError.unknownReference(parameterID)
            }
            if visiting.contains(parameterID) {
                throw ParameterError.cycleDetected(visiting + [parameterID])
            }

            visiting.append(parameterID)
            defer {
                visiting.removeLast()
            }
            let value = try evaluate(parameter.expression)
            guard value.kind == parameter.kind else {
                throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: value.kind)
            }
            resolved[parameterID] = value
            return value
        }

        mutating func evaluate(_ expression: CADCore.CADExpression) throws -> Quantity {
            try evaluateExpression(
                expression,
                parameterValue: { parameterID in
                    try resolve(parameterID)
                },
                variableValue: { name, _ in
                    throw ParameterError.unknownVariable(name)
                }
            )
        }
    }
}

private func evaluateExpression(
    _ expression: CADCore.CADExpression,
    parameterValue: (ParameterID) throws -> Quantity,
    variableValue: (String, QuantityKind) throws -> Quantity
) throws -> Quantity {
    switch expression {
    case let .constant(quantity):
        return try validatedQuantity(quantity)
    case let .reference(parameterID):
        return try validatedQuantity(parameterValue(parameterID))
    case let .variable(name, expectedKind):
        try CADIdentifierRules.validate(name)
        return try validatedQuantity(variableValue(name, expectedKind))
    case let .add(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue)
        guard lhsValue.kind == rhsValue.kind else {
            throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsValue.kind, rhs: rhsValue.kind)
        }
        return try validatedQuantity(Quantity(value: lhsValue.value + rhsValue.value, kind: lhsValue.kind))
    case let .subtract(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue)
        guard lhsValue.kind == rhsValue.kind else {
            throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsValue.kind, rhs: rhsValue.kind)
        }
        return try validatedQuantity(Quantity(value: lhsValue.value - rhsValue.value, kind: lhsValue.kind))
    case let .multiply(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue)
        if lhsValue.kind == QuantityKind.scalar {
            return try validatedQuantity(Quantity(value: lhsValue.value * rhsValue.value, kind: rhsValue.kind))
        }
        if rhsValue.kind == QuantityKind.scalar {
            return try validatedQuantity(Quantity(value: lhsValue.value * rhsValue.value, kind: lhsValue.kind))
        }
        throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsValue.kind, rhs: rhsValue.kind)
    case let .divide(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue)
        guard abs(rhsValue.value) > Double.ulpOfOne else {
            throw UnitError.divisionByZero
        }
        if rhsValue.kind == QuantityKind.scalar {
            return try validatedQuantity(Quantity(value: lhsValue.value / rhsValue.value, kind: lhsValue.kind))
        }
        if lhsValue.kind == rhsValue.kind {
            return try validatedQuantity(.scalar(lhsValue.value / rhsValue.value))
        }
        throw UnitError.incompatibleQuantity(operation: "divide", lhs: lhsValue.kind, rhs: rhsValue.kind)
    case let .sin(argument):
        return try evaluateTrigonometry("sin", argument, parameterValue: parameterValue, variableValue: variableValue, sin)
    case let .cos(argument):
        return try evaluateTrigonometry("cos", argument, parameterValue: parameterValue, variableValue: variableValue, cos)
    case let .tan(argument):
        return try evaluateTrigonometry("tan", argument, parameterValue: parameterValue, variableValue: variableValue, tan)
    }
}

private func evaluateTrigonometry(
    _ name: String,
    _ argument: CADCore.CADExpression,
    parameterValue: (ParameterID) throws -> Quantity,
    variableValue: (String, QuantityKind) throws -> Quantity,
    _ function: (Double) -> Double
) throws -> Quantity {
    let value = try evaluateExpression(argument, parameterValue: parameterValue, variableValue: variableValue)
    guard value.kind == QuantityKind.angle else {
        throw UnitError.expectedQuantity(operation: name, expected: .angle, actual: value.kind)
    }
    return try validatedQuantity(.scalar(function(value.value)))
}

private func validatedQuantity(_ quantity: Quantity) throws -> Quantity {
    try quantity.validate()
    return quantity
}
