#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADIR
import CADGeometry

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
        var execution = try OriginalQueryExecution.independentGeometry()

        for parameterID in table.parameters.keys {
            _ = try state.resolve(parameterID, depth: 0, using: &execution)
        }

        return ResolvedParameterTable(values: state.resolved, names: names)
    }

    public func evaluate(
        _ expression: CADCore.CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity] = [:]
    ) throws -> Quantity {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try evaluate(expression, parameters: parameters, variables: variables, using: &execution)
    }

    public func evaluate(
        _ expression: CADCore.CADExpression,
        parameters: ResolvedParameterTable,
        variables: [String: Quantity] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> Quantity {
        let result = try evaluateExpression(
            expression,
            parameterValue: { parameterID, _, _ in
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
            }, depth: 0, using: &execution
        )
        try execution.checkpoint()
        return result
    }

    private struct ResolutionState {
        var table: ParameterTable
        var resolved: [ParameterID: Quantity] = [:]
        var visiting: [ParameterID] = []

        mutating func resolve(_ parameterID: ParameterID, depth: Int,
            using execution: inout OriginalQueryExecution) throws -> Quantity {
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
            let value = try evaluate(parameter.expression, depth: depth, using: &execution)
            guard value.kind == parameter.kind else {
                throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: value.kind)
            }
            resolved[parameterID] = value
            return value
        }

        mutating func evaluate(_ expression: CADCore.CADExpression, depth: Int,
            using execution: inout OriginalQueryExecution) throws -> Quantity {
            try evaluateExpression(
                expression,
                parameterValue: { parameterID, depth, execution in
                    try resolve(parameterID, depth: depth, using: &execution)
                },
                variableValue: { name, _ in
                    throw ParameterError.unknownVariable(name)
                }, depth: depth, using: &execution
            )
        }
    }
}

private func evaluateExpression(
    _ expression: CADCore.CADExpression,
    parameterValue: (ParameterID, Int, inout OriginalQueryExecution) throws -> Quantity,
    variableValue: (String, QuantityKind) throws -> Quantity,
    depth: Int, using execution: inout OriginalQueryExecution
) throws -> Quantity {
    try execution.admitDepth(value: depth, coefficient: 0)
    try execution.consumeWork(1)
    func childDepth() throws -> Int {
        let next = depth.addingReportingOverflow(1)
        guard !next.overflow else { throw ExactScalarFailure.countOverflow }
        return next.partialValue
    }
    switch expression {
    case let .constant(quantity):
        return try validatedQuantity(quantity)
    case let .reference(parameterID):
        return try validatedQuantity(parameterValue(parameterID, try childDepth(), &execution))
    case let .variable(name, expectedKind):
        for _ in name.unicodeScalars { try execution.consumeWork(1) }
        try CADIdentifierRules.validate(name)
        for _ in name.utf8 { try execution.consumeWork(1) }
        return try validatedQuantity(variableValue(name, expectedKind))
    case let .add(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        guard lhsValue.kind == rhsValue.kind else {
            throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsValue.kind, rhs: rhsValue.kind)
        }
        return try validatedQuantity(Quantity(value: lhsValue.value + rhsValue.value, kind: lhsValue.kind))
    case let .subtract(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        guard lhsValue.kind == rhsValue.kind else {
            throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsValue.kind, rhs: rhsValue.kind)
        }
        return try validatedQuantity(Quantity(value: lhsValue.value - rhsValue.value, kind: lhsValue.kind))
    case let .multiply(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        if lhsValue.kind == QuantityKind.scalar {
            return try validatedQuantity(Quantity(value: lhsValue.value * rhsValue.value, kind: rhsValue.kind))
        }
        if rhsValue.kind == QuantityKind.scalar {
            return try validatedQuantity(Quantity(value: lhsValue.value * rhsValue.value, kind: lhsValue.kind))
        }
        throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsValue.kind, rhs: rhsValue.kind)
    case let .divide(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
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
    case let .bezierNaturalExtension(coordinates, length, index):
        try execution.retainStorage(count: coordinates.count, stride: MemoryLayout<Quantity>.stride)
        let values = try coordinates.map {
            try evaluateExpression($0, parameterValue: parameterValue,
                variableValue: variableValue, depth: childDepth(), using: &execution)
        }
        let lengthValue = try evaluateExpression(length, parameterValue: parameterValue,
            variableValue: variableValue, depth: childDepth(), using: &execution)
        return try NaturalBezierContinuation(tolerance: .standard).coordinate(
            values, length: lengthValue, index: index, using: &execution)
    case let .bezierShapedExtension(shape, coordinates, length, index):
        try execution.retainStorage(count: coordinates.count, stride: MemoryLayout<Quantity>.stride)
        let values = try coordinates.map {
            try evaluateExpression($0, parameterValue: parameterValue,
                variableValue: variableValue, depth: childDepth(), using: &execution)
        }
        let lengthValue = try evaluateExpression(length, parameterValue: parameterValue,
            variableValue: variableValue, depth: childDepth(), using: &execution)
        return try BezierShapedExtension(tolerance: .standard).coordinate(
            shape: shape, coordinates: values, length: lengthValue, index: index, using: &execution)
    case let .hypot(lhs, rhs):
        let lhsValue = try evaluateExpression(lhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        let rhsValue = try evaluateExpression(rhs, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution)
        guard lhsValue.kind == rhsValue.kind else {
            throw UnitError.incompatibleQuantity(operation: "hypot", lhs: lhsValue.kind, rhs: rhsValue.kind)
        }
        return try validatedQuantity(Quantity(value: hypot(lhsValue.value, rhsValue.value), kind: lhsValue.kind))
    case let .sin(argument):
        return try evaluateTrigonometry("sin", argument, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution, sin)
    case let .cos(argument):
        return try evaluateTrigonometry("cos", argument, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution, cos)
    case let .tan(argument):
        return try evaluateTrigonometry("tan", argument, parameterValue: parameterValue, variableValue: variableValue, depth: childDepth(), using: &execution, tan)
    }
}

private func evaluateTrigonometry(
    _ name: String,
    _ argument: CADCore.CADExpression,
    parameterValue: (ParameterID, Int, inout OriginalQueryExecution) throws -> Quantity,
    variableValue: (String, QuantityKind) throws -> Quantity,
    depth: Int, using execution: inout OriginalQueryExecution,
    _ function: (Double) -> Double
) throws -> Quantity {
    let value = try evaluateExpression(argument, parameterValue: parameterValue, variableValue: variableValue, depth: depth, using: &execution)
    guard value.kind == QuantityKind.angle else {
        throw UnitError.expectedQuantity(operation: name, expected: .angle, actual: value.kind)
    }
    return try validatedQuantity(.scalar(function(value.value)))
}

private func validatedQuantity(_ quantity: Quantity) throws -> Quantity {
    try quantity.validate()
    return quantity
}
