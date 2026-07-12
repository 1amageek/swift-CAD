import Foundation
import CADCore

public struct ParameterTable: Codable, Sendable {
    public var parameters: [ParameterID: Parameter]
    public var revision: DocumentRevision

    public init(parameters: [ParameterID: Parameter] = [:], revision: DocumentRevision = DocumentRevision()) {
        self.parameters = parameters
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case parameters
        case revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.parameters, .revision], in: decoder)
        parameters = try container.decode([ParameterID: Parameter].self, forKey: .parameters)
        revision = try container.decode(DocumentRevision.self, forKey: .revision)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(revision, forKey: .revision)
    }

    public func validate() throws {
        try revision.validate()
        var names: Set<String> = []
        for (parameterID, parameter) in parameters {
            guard parameter.id == parameterID else {
                throw ParameterError.tableKeyMismatch(key: parameterID, parameterID: parameter.id)
            }
            try CADIdentifierRules.validate(parameter.name)
            guard names.insert(parameter.name).inserted else {
                throw ParameterError.duplicateName(parameter.name)
            }
        }

        var state = ParameterValidationState(table: self)
        for parameterID in parameters.keys {
            _ = try state.kind(for: parameterID)
        }
        var valueState = ParameterValueValidationState(table: self)
        for parameterID in parameters.keys {
            _ = try valueState.value(for: parameterID)
        }
    }

    public func inferredKind(for expression: CADExpression, allowingVariables: Bool = false) throws -> QuantityKind {
        var state = ParameterValidationState(table: self, allowsVariables: allowingVariables)
        return try state.kind(for: expression)
    }

    public func resolvedValue(for expression: CADExpression) throws -> Quantity {
        var state = ParameterValueValidationState(table: self)
        return try state.value(for: expression)
    }
}

public struct Parameter: Codable, Sendable, Hashable {
    public var id: ParameterID
    public var name: String
    public var expression: CADExpression
    public var kind: QuantityKind

    public init(id: ParameterID = ParameterID(), name: String, expression: CADExpression, kind: QuantityKind) {
        self.id = id
        self.name = name
        self.expression = expression
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case expression
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .name, .expression, .kind], in: decoder)
        id = try container.decode(ParameterID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        expression = try container.decode(CADExpression.self, forKey: .expression)
        kind = try container.decode(QuantityKind.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(expression, forKey: .expression)
        try container.encode(kind, forKey: .kind)
    }
}

private struct ParameterValidationState {
    var table: ParameterTable
    var allowsVariables = false
    var resolvedKinds: [ParameterID: QuantityKind] = [:]
    var visiting: [ParameterID] = []

    mutating func kind(for parameterID: ParameterID) throws -> QuantityKind {
        if let kind = resolvedKinds[parameterID] {
            return kind
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
        let inferredKind = try kind(for: parameter.expression)
        guard inferredKind == parameter.kind else {
            throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: inferredKind)
        }
        resolvedKinds[parameterID] = inferredKind
        return inferredKind
    }

    mutating func kind(for expression: CADExpression) throws -> QuantityKind {
        switch expression {
        case let .constant(quantity):
            try quantity.validate()
            return quantity.kind
        case let .reference(parameterID):
            return try kind(for: parameterID)
        case let .variable(name, kind):
            try CADIdentifierRules.validate(name)
            guard allowsVariables else {
                throw ParameterError.unknownVariable(name)
            }
            return kind
        case let .add(lhs, rhs):
            let lhsKind = try kind(for: lhs)
            let rhsKind = try kind(for: rhs)
            guard lhsKind == rhsKind else {
                throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsKind, rhs: rhsKind)
            }
            return lhsKind
        case let .subtract(lhs, rhs):
            let lhsKind = try kind(for: lhs)
            let rhsKind = try kind(for: rhs)
            guard lhsKind == rhsKind else {
                throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsKind, rhs: rhsKind)
            }
            return lhsKind
        case let .multiply(lhs, rhs):
            let lhsKind = try kind(for: lhs)
            let rhsKind = try kind(for: rhs)
            if lhsKind == .scalar {
                return rhsKind
            }
            if rhsKind == .scalar {
                return lhsKind
            }
            throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsKind, rhs: rhsKind)
        case let .divide(lhs, rhs):
            let lhsKind = try kind(for: lhs)
            let rhsKind = try kind(for: rhs)
            if rhsKind == .scalar {
                return lhsKind
            }
            if lhsKind == rhsKind {
                return .scalar
            }
            throw UnitError.incompatibleQuantity(operation: "divide", lhs: lhsKind, rhs: rhsKind)
        case let .sin(argument), let .cos(argument), let .tan(argument):
            let argumentKind = try kind(for: argument)
            guard argumentKind == .angle else {
                throw UnitError.expectedQuantity(operation: "trigonometry", expected: .angle, actual: argumentKind)
            }
            return .scalar
        }
    }
}

private struct ParameterValueValidationState {
    var table: ParameterTable
    var resolvedValues: [ParameterID: Quantity] = [:]
    var visiting: [ParameterID] = []

    mutating func value(for parameterID: ParameterID) throws -> Quantity {
        if let value = resolvedValues[parameterID] {
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
        let resolvedValue = try value(for: parameter.expression)
        guard resolvedValue.kind == parameter.kind else {
            throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: resolvedValue.kind)
        }
        resolvedValues[parameterID] = resolvedValue
        return resolvedValue
    }

    mutating func value(for expression: CADExpression) throws -> Quantity {
        switch expression {
        case let .constant(quantity):
            return try validated(quantity)
        case let .reference(parameterID):
            return try value(for: parameterID)
        case let .variable(name, _):
            try CADIdentifierRules.validate(name)
            throw ParameterError.unknownVariable(name)
        case let .add(lhs, rhs):
            let lhsValue = try value(for: lhs)
            let rhsValue = try value(for: rhs)
            guard lhsValue.kind == rhsValue.kind else {
                throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsValue.kind, rhs: rhsValue.kind)
            }
            return try validated(Quantity(value: lhsValue.value + rhsValue.value, kind: lhsValue.kind))
        case let .subtract(lhs, rhs):
            let lhsValue = try value(for: lhs)
            let rhsValue = try value(for: rhs)
            guard lhsValue.kind == rhsValue.kind else {
                throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsValue.kind, rhs: rhsValue.kind)
            }
            return try validated(Quantity(value: lhsValue.value - rhsValue.value, kind: lhsValue.kind))
        case let .multiply(lhs, rhs):
            let lhsValue = try value(for: lhs)
            let rhsValue = try value(for: rhs)
            if lhsValue.kind == .scalar {
                return try validated(Quantity(value: lhsValue.value * rhsValue.value, kind: rhsValue.kind))
            }
            if rhsValue.kind == .scalar {
                return try validated(Quantity(value: lhsValue.value * rhsValue.value, kind: lhsValue.kind))
            }
            throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsValue.kind, rhs: rhsValue.kind)
        case let .divide(lhs, rhs):
            let lhsValue = try value(for: lhs)
            let rhsValue = try value(for: rhs)
            guard abs(rhsValue.value) > Double.ulpOfOne else {
                throw UnitError.divisionByZero
            }
            if rhsValue.kind == .scalar {
                return try validated(Quantity(value: lhsValue.value / rhsValue.value, kind: lhsValue.kind))
            }
            if lhsValue.kind == rhsValue.kind {
                return try validated(.scalar(lhsValue.value / rhsValue.value))
            }
            throw UnitError.incompatibleQuantity(operation: "divide", lhs: lhsValue.kind, rhs: rhsValue.kind)
        case let .sin(argument):
            return try trigonometricValue("sin", argument, sin)
        case let .cos(argument):
            return try trigonometricValue("cos", argument, cos)
        case let .tan(argument):
            return try trigonometricValue("tan", argument, tan)
        }
    }

    private mutating func trigonometricValue(
        _ operation: String,
        _ argument: CADExpression,
        _ function: (Double) -> Double
    ) throws -> Quantity {
        let argumentValue = try value(for: argument)
        guard argumentValue.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: argumentValue.kind)
        }
        return try validated(.scalar(function(argumentValue.value)))
    }

    private func validated(_ quantity: Quantity) throws -> Quantity {
        try quantity.validate()
        return quantity
    }
}

public struct ResolvedParameterTable: Codable, Sendable {
    public var values: [ParameterID: Quantity]
    public var names: [String: ParameterID]

    public init(values: [ParameterID: Quantity] = [:], names: [String: ParameterID] = [:]) {
        self.values = values
        self.names = names
    }

    public func value(for id: ParameterID) throws -> Quantity {
        guard let value = values[id] else {
            throw ParameterError.unknownReference(id)
        }
        return value
    }
}
