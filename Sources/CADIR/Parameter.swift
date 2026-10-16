#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADIR numeric algorithms require the target C math module.")
#endif
import CADCore
import CADGeometry
import CADTopology

public struct ParameterTable: Equatable, Sendable {
    public var parameters: [ParameterID: Parameter]
    public var revision: DocumentRevision

    public init(parameters: [ParameterID: Parameter] = [:], revision: DocumentRevision = DocumentRevision()) {
        self.parameters = parameters
        self.revision = revision
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case parameters
        case revision
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.parameters, .revision], in: decoder)
        parameters = try container.decode([ParameterID: Parameter].self, forKey: .parameters)
        revision = try container.decode(DocumentRevision.self, forKey: .revision)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(revision, forKey: .revision)
    }
#endif

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try revision.validate()
        var names: Set<String> = []
        for (parameterID, parameter) in parameters {
            try execution.consumeWork(1)
            guard parameter.id == parameterID else {
                throw ParameterError.tableKeyMismatch(key: parameterID, parameterID: parameter.id)
            }
            for _ in parameter.name.unicodeScalars { try execution.consumeWork(1) }
            try CADIdentifierRules.validate(parameter.name)
            guard try OriginalParameterQueryStorage.insert(parameter.name, in: &names, using: &execution) else {
                throw ParameterError.duplicateName(parameter.name)
            }
        }

        var state = ParameterValidationState(table: self)
        for parameterID in parameters.keys {
            _ = try state.kind(for: parameterID, using: &execution)
        }
        var valueState = ParameterValueValidationState(table: self)
        for parameterID in parameters.keys {
            _ = try valueState.value(for: parameterID, using: &execution)
        }
    }

    public func inferredKind(for expression: CADExpression, allowingVariables: Bool = false) throws -> QuantityKind {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try inferredKind(for: expression, allowingVariables: allowingVariables, using: &execution)
    }

    public func inferredKind(for expression: CADExpression, allowingVariables: Bool = false,
        using execution: inout OriginalQueryExecution) throws -> QuantityKind {
        var state = ParameterValidationState(table: self, allowsVariables: allowingVariables)
        return try state.kind(for: expression, using: &execution)
    }

    public func resolvedValue(for expression: CADExpression) throws -> Quantity {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try resolvedValue(for: expression, using: &execution)
    }

    public func resolvedValue(for expression: CADExpression,
        using execution: inout OriginalQueryExecution) throws -> Quantity {
        var state = ParameterValueValidationState(table: self)
        return try state.value(for: expression, using: &execution)
    }
}

public struct Parameter: Sendable, Hashable {
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case expression
        case kind
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .name, .expression, .kind], in: decoder)
        id = try container.decode(ParameterID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        expression = try container.decode(CADExpression.self, forKey: .expression)
        kind = try container.decode(QuantityKind.self, forKey: .kind)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(expression, forKey: .expression)
        try container.encode(kind, forKey: .kind)
    }
#endif
}

private struct ParameterValidationState {
    var table: ParameterTable
    var allowsVariables = false
    var resolvedKinds: [ParameterID: QuantityKind] = [:]
    var visiting: [ParameterID] = []
    private var sourceDepth = 0

    init(table: ParameterTable, allowsVariables: Bool = false) {
        self.table = table
        self.allowsVariables = allowsVariables
    }

    mutating func kind(for parameterID: ParameterID, using execution: inout OriginalQueryExecution) throws -> QuantityKind {
        let nextDepth = sourceDepth.addingReportingOverflow(1)
        guard !nextDepth.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.admitSourceDepth(nextDepth.partialValue)
        try execution.consumeWork(1)
        sourceDepth = nextDepth.partialValue
        defer { sourceDepth -= 1 }
        if let kind = resolvedKinds[parameterID] {
            return kind
        }
        guard let parameter = table.parameters[parameterID] else {
            throw ParameterError.unknownReference(parameterID)
        }
        for visited in visiting {
            try execution.consumeWork(1)
            if visited == parameterID {
                var cycle = try OriginalParameterQueryStorage.materialize(visiting, using: &execution)
                try OriginalParameterQueryStorage.append(parameterID, to: &cycle, using: &execution)
                throw ParameterError.cycleDetected(cycle)
            }
        }
        try OriginalParameterQueryStorage.append(parameterID, to: &visiting, using: &execution)
        defer {
            visiting.removeLast()
        }
        let inferredKind = try kind(for: parameter.expression, using: &execution)
        guard inferredKind == parameter.kind else {
            throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: inferredKind)
        }
        try OriginalParameterQueryStorage.set(inferredKind, for: parameterID, in: &resolvedKinds, using: &execution)
        return inferredKind
    }

    mutating func kind(for expression: CADExpression, using execution: inout OriginalQueryExecution) throws -> QuantityKind {
        let nextDepth = sourceDepth.addingReportingOverflow(1)
        guard !nextDepth.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.admitSourceDepth(nextDepth.partialValue)
        try execution.consumeWork(1)
        sourceDepth = nextDepth.partialValue
        defer { sourceDepth -= 1 }
        switch expression {
        case let .constant(quantity):
            try quantity.validate()
            return quantity.kind
        case let .reference(parameterID):
            return try kind(for: parameterID, using: &execution)
        case let .variable(name, kind):
            for _ in name.unicodeScalars { try execution.consumeWork(1) }
            try CADIdentifierRules.validate(name)
            guard allowsVariables else {
                throw ParameterError.unknownVariable(name)
            }
            return kind
        case let .add(lhs, rhs):
            let lhsKind = try kind(for: lhs, using: &execution)
            let rhsKind = try kind(for: rhs, using: &execution)
            guard lhsKind == rhsKind else {
                throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsKind, rhs: rhsKind)
            }
            return lhsKind
        case let .subtract(lhs, rhs):
            let lhsKind = try kind(for: lhs, using: &execution)
            let rhsKind = try kind(for: rhs, using: &execution)
            guard lhsKind == rhsKind else {
                throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsKind, rhs: rhsKind)
            }
            return lhsKind
        case let .bezierNaturalExtension(coordinates, length, index):
            try NaturalBezierContinuation.validateCoordinateForm(count: coordinates.count, index: index)
            for expression in coordinates {
                let actual = try kind(for: expression, using: &execution)
                guard actual == .length else {
                    throw UnitError.expectedQuantity(operation: "bezierNaturalExtension", expected: .length, actual: actual)
                }
            }
            let actual = try kind(for: length, using: &execution)
            guard actual == .length else {
                throw UnitError.expectedQuantity(operation: "bezierNaturalExtension", expected: .length, actual: actual)
            }
            return .length
        case let .bezierShapedExtension(shape, coordinates, length, index):
            try BezierShapedExtension.validateCoordinateForm(shape: shape, count: coordinates.count, index: index)
            for expression in coordinates {
                let actual = try kind(for: expression, using: &execution)
                guard actual == .length else {
                    throw UnitError.expectedQuantity(operation: "bezierShapedExtension", expected: .length, actual: actual)
                }
            }
            let actual = try kind(for: length, using: &execution)
            guard actual == .length else {
                throw UnitError.expectedQuantity(operation: "bezierShapedExtension", expected: .length, actual: actual)
            }
            return .length
        case let .hypot(lhs, rhs):
            let lhsKind = try kind(for: lhs, using: &execution)
            let rhsKind = try kind(for: rhs, using: &execution)
            guard lhsKind == rhsKind else {
                throw UnitError.incompatibleQuantity(operation: "hypot", lhs: lhsKind, rhs: rhsKind)
            }
            return lhsKind
        case let .multiply(lhs, rhs):
            let lhsKind = try kind(for: lhs, using: &execution)
            let rhsKind = try kind(for: rhs, using: &execution)
            if lhsKind == .scalar {
                return rhsKind
            }
            if rhsKind == .scalar {
                return lhsKind
            }
            throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsKind, rhs: rhsKind)
        case let .divide(lhs, rhs):
            let lhsKind = try kind(for: lhs, using: &execution)
            let rhsKind = try kind(for: rhs, using: &execution)
            if rhsKind == .scalar {
                return lhsKind
            }
            if lhsKind == rhsKind {
                return .scalar
            }
            throw UnitError.incompatibleQuantity(operation: "divide", lhs: lhsKind, rhs: rhsKind)
        case let .sin(argument), let .cos(argument), let .tan(argument):
            let argumentKind = try kind(for: argument, using: &execution)
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
    private var sourceDepth = 0

    init(table: ParameterTable) { self.table = table }

    mutating func value(for parameterID: ParameterID, using execution: inout OriginalQueryExecution) throws -> Quantity {
        let nextDepth = sourceDepth.addingReportingOverflow(1)
        guard !nextDepth.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.admitSourceDepth(nextDepth.partialValue)
        try execution.consumeWork(1)
        sourceDepth = nextDepth.partialValue
        defer { sourceDepth -= 1 }
        if let value = resolvedValues[parameterID] {
            return value
        }
        guard let parameter = table.parameters[parameterID] else {
            throw ParameterError.unknownReference(parameterID)
        }
        for visited in visiting {
            try execution.consumeWork(1)
            if visited == parameterID {
                var cycle = try OriginalParameterQueryStorage.materialize(visiting, using: &execution)
                try OriginalParameterQueryStorage.append(parameterID, to: &cycle, using: &execution)
                throw ParameterError.cycleDetected(cycle)
            }
        }
        try OriginalParameterQueryStorage.append(parameterID, to: &visiting, using: &execution)
        defer {
            visiting.removeLast()
        }
        let resolvedValue = try value(for: parameter.expression, using: &execution)
        guard resolvedValue.kind == parameter.kind else {
            throw ParameterError.kindMismatch(parameterID: parameterID, expected: parameter.kind, actual: resolvedValue.kind)
        }
        try OriginalParameterQueryStorage.set(resolvedValue, for: parameterID, in: &resolvedValues, using: &execution)
        return resolvedValue
    }

    mutating func value(for expression: CADExpression, using execution: inout OriginalQueryExecution) throws -> Quantity {
        let nextDepth = sourceDepth.addingReportingOverflow(1)
        guard !nextDepth.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.admitSourceDepth(nextDepth.partialValue)
        try execution.consumeWork(1)
        sourceDepth = nextDepth.partialValue
        defer { sourceDepth -= 1 }
        switch expression {
        case let .constant(quantity):
            return try validated(quantity)
        case let .reference(parameterID):
            return try value(for: parameterID, using: &execution)
        case let .variable(name, _):
            for _ in name.unicodeScalars { try execution.consumeWork(1) }
            try CADIdentifierRules.validate(name)
            throw ParameterError.unknownVariable(name)
        case let .add(lhs, rhs):
            let lhsValue = try value(for: lhs, using: &execution)
            let rhsValue = try value(for: rhs, using: &execution)
            guard lhsValue.kind == rhsValue.kind else {
                throw UnitError.incompatibleQuantity(operation: "add", lhs: lhsValue.kind, rhs: rhsValue.kind)
            }
            return try validated(Quantity(value: lhsValue.value + rhsValue.value, kind: lhsValue.kind))
        case let .subtract(lhs, rhs):
            let lhsValue = try value(for: lhs, using: &execution)
            let rhsValue = try value(for: rhs, using: &execution)
            guard lhsValue.kind == rhsValue.kind else {
                throw UnitError.incompatibleQuantity(operation: "subtract", lhs: lhsValue.kind, rhs: rhsValue.kind)
            }
            return try validated(Quantity(value: lhsValue.value - rhsValue.value, kind: lhsValue.kind))
        case let .multiply(lhs, rhs):
            let lhsValue = try value(for: lhs, using: &execution)
            let rhsValue = try value(for: rhs, using: &execution)
            if lhsValue.kind == .scalar {
                return try validated(Quantity(value: lhsValue.value * rhsValue.value, kind: rhsValue.kind))
            }
            if rhsValue.kind == .scalar {
                return try validated(Quantity(value: lhsValue.value * rhsValue.value, kind: lhsValue.kind))
            }
            throw UnitError.incompatibleQuantity(operation: "multiply", lhs: lhsValue.kind, rhs: rhsValue.kind)
        case let .divide(lhs, rhs):
            let lhsValue = try value(for: lhs, using: &execution)
            let rhsValue = try value(for: rhs, using: &execution)
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
        case let .bezierNaturalExtension(coordinates, length, index):
            try execution.retainStorage(count: coordinates.count, stride: MemoryLayout<Quantity>.stride)
            var values: [Quantity] = []
            values.reserveCapacity(coordinates.count)
            for coordinate in coordinates { values.append(try value(for: coordinate, using: &execution)) }
            let extensionLength = try value(for: length, using: &execution)
            return try NaturalBezierContinuation(tolerance: .standard).coordinate(
                values, length: extensionLength, index: index, using: &execution)
        case let .bezierShapedExtension(shape, coordinates, length, index):
            try execution.retainStorage(count: coordinates.count, stride: MemoryLayout<Quantity>.stride)
            var values: [Quantity] = []
            values.reserveCapacity(coordinates.count)
            for coordinate in coordinates { values.append(try value(for: coordinate, using: &execution)) }
            let extensionLength = try value(for: length, using: &execution)
            return try BezierShapedExtension(tolerance: .standard).coordinate(
                shape: shape, coordinates: values, length: extensionLength, index: index, using: &execution)
        case let .hypot(lhs, rhs):
            let lhsValue = try value(for: lhs, using: &execution)
            let rhsValue = try value(for: rhs, using: &execution)
            guard lhsValue.kind == rhsValue.kind else {
                throw UnitError.incompatibleQuantity(operation: "hypot", lhs: lhsValue.kind, rhs: rhsValue.kind)
            }
            return try validated(Quantity(value: hypot(lhsValue.value, rhsValue.value), kind: lhsValue.kind))
        case let .sin(argument):
            return try trigonometricValue("sin", argument, sin, using: &execution)
        case let .cos(argument):
            return try trigonometricValue("cos", argument, cos, using: &execution)
        case let .tan(argument):
            return try trigonometricValue("tan", argument, tan, using: &execution)
        }
    }

    private mutating func trigonometricValue(
        _ operation: String,
        _ argument: CADExpression,
        _ function: (Double) -> Double,
        using execution: inout OriginalQueryExecution
    ) throws -> Quantity {
        let argumentValue = try value(for: argument, using: &execution)
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

public struct ResolvedParameterTable: Sendable {
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

#if !hasFeature(Embedded)
extension ParameterTable: Codable {}
extension Parameter: Codable {}
extension ResolvedParameterTable: Codable {}
#endif

extension CADExpression {
    /// Admits the authored source shape independently of its numeric validation.
    func validateDocumentLiteralQuantities(using execution: inout OriginalQueryExecution) throws {
        try admitDocumentSource(using: &execution)
        try validateLiteralQuantities(using: &execution)
    }

    private func admitDocumentSource(using execution: inout OriginalQueryExecution) throws {
        try execution.withSourceDepthOffset(1) { execution in
            try execution.admitSourceDepth(0)
            try execution.consumeWork(1)
            switch self {
            case .constant, .reference, .variable: break
            case let .add(left, right), let .subtract(left, right),
                 let .multiply(left, right), let .divide(left, right), let .hypot(left, right):
                try left.admitDocumentSource(using: &execution)
                try right.admitDocumentSource(using: &execution)
            case let .bezierNaturalExtension(coordinates, length, _),
                 let .bezierShapedExtension(_, coordinates, length, _):
                for coordinate in coordinates { try coordinate.admitDocumentSource(using: &execution) }
                try length.admitDocumentSource(using: &execution)
            case let .sin(argument), let .cos(argument), let .tan(argument):
                try argument.admitDocumentSource(using: &execution)
            }
        }
    }
}
