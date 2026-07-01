import CADCore

public extension CADDocument {
    func parameterID(named name: String) -> ParameterID? {
        parameters.parameterID(named: name)
    }

    @discardableResult
    mutating func upsertParameter(
        name: String,
        expression: CADExpression,
        kind: QuantityKind
    ) -> ParameterID {
        let parameterID = parameters.upsertParameter(
            name: name,
            expression: expression,
            kind: kind
        )
        return parameterID
    }

    @discardableResult
    mutating func deleteParameter(
        named name: String,
        tolerance: ModelingTolerance = .standard
    ) throws -> ParameterID {
        guard let parameterID = parameters.parameterID(named: name) else {
            throw FeatureEvaluationError.missingInput("Parameter name could not be resolved.")
        }

        var updatedDocument = self
        updatedDocument.parameters.deleteParameter(id: parameterID)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return parameterID
    }

    @discardableResult
    mutating func renameParameter(
        named currentName: String,
        to newName: String,
        tolerance: ModelingTolerance = .standard
    ) throws -> ParameterID {
        guard let parameterID = parameters.parameterID(named: currentName) else {
            throw FeatureEvaluationError.missingInput("Parameter name could not be resolved.")
        }

        var updatedDocument = self
        try updatedDocument.parameters.renameParameter(id: parameterID, to: newName)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return parameterID
    }
}

extension ParameterTable {
    func parameterID(named name: String) -> ParameterID? {
        parameters.values.first { $0.name == name }?.id
    }

    @discardableResult
    mutating func upsertParameter(
        name: String,
        expression: CADExpression,
        kind: QuantityKind
    ) -> ParameterID {
        let parameterID = parameterID(named: name) ?? ParameterID()
        parameters[parameterID] = Parameter(
            id: parameterID,
            name: name,
            expression: expression,
            kind: kind
        )
        revision = revision.advanced()
        return parameterID
    }

    mutating func deleteParameter(id: ParameterID) {
        parameters.removeValue(forKey: id)
        revision = revision.advanced()
    }

    mutating func renameParameter(id: ParameterID, to name: String) throws {
        try CADIdentifierRules.validate(name)
        guard var parameter = parameters[id] else {
            throw ParameterError.unknownReference(id)
        }
        guard parameter.name != name else {
            return
        }
        guard parameters.values.contains(where: { $0.id != id && $0.name == name }) == false else {
            throw ParameterError.duplicateName(name)
        }

        parameter.name = name
        parameters[id] = parameter
        revision = revision.advanced()
    }
}
