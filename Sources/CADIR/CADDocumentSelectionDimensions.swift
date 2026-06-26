import CADCore

public extension CADDocument {
    @discardableResult
    mutating func addSelectionDimension(
        id: SelectionDimensionID = SelectionDimensionID(),
        name: String? = nil,
        kind: SelectionDimensionKind,
        first: SelectionReference,
        second: SelectionReference,
        target: CADExpression,
        tolerance: ModelingTolerance = .standard
    ) throws -> SelectionDimensionID {
        let dimension = SelectionDimension(
            id: id,
            name: name,
            kind: kind,
            first: first,
            second: second,
            target: target
        )
        return try addSelectionDimension(dimension, tolerance: tolerance)
    }

    @discardableResult
    mutating func addSelectionDimension(
        _ dimension: SelectionDimension,
        tolerance: ModelingTolerance = .standard
    ) throws -> SelectionDimensionID {
        try dimension.validate(parameters: parameters, tolerance: tolerance)
        guard selectionDimensions.contains(where: { $0.id == dimension.id }) == false else {
            throw FeatureEvaluationError.invalidGraph("Selection dimension IDs must be unique.")
        }

        var updatedDocument = self
        updatedDocument.selectionDimensions.append(dimension)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return dimension.id
    }

    func addingSelectionDimension(
        _ dimension: SelectionDimension,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocument {
        var document = self
        try document.addSelectionDimension(dimension, tolerance: tolerance)
        return document
    }

    @discardableResult
    mutating func setSelectionDimensionTarget(
        id: SelectionDimensionID,
        target: CADExpression,
        tolerance: ModelingTolerance = .standard
    ) throws -> SelectionDimension {
        guard let index = selectionDimensions.firstIndex(where: { $0.id == id }) else {
            throw FeatureEvaluationError.invalidGraph("Selection dimension was not found.")
        }

        var updatedDocument = self
        updatedDocument.selectionDimensions[index].target = target
        let updatedDimension = updatedDocument.selectionDimensions[index]
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return updatedDimension
    }

    func settingSelectionDimensionTarget(
        id: SelectionDimensionID,
        target: CADExpression,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocument {
        var document = self
        try document.setSelectionDimensionTarget(
            id: id,
            target: target,
            tolerance: tolerance
        )
        return document
    }

    @discardableResult
    mutating func removeSelectionDimension(
        id: SelectionDimensionID,
        tolerance: ModelingTolerance = .standard
    ) throws -> SelectionDimension {
        guard let index = selectionDimensions.firstIndex(where: { $0.id == id }) else {
            throw FeatureEvaluationError.invalidGraph("Selection dimension was not found.")
        }

        var updatedDocument = self
        let removedDimension = updatedDocument.selectionDimensions.remove(at: index)
        try updatedDocument.validate(tolerance: tolerance)
        self = updatedDocument
        return removedDimension
    }

    func removingSelectionDimension(
        id: SelectionDimensionID,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADDocument {
        var document = self
        try document.removeSelectionDimension(id: id, tolerance: tolerance)
        return document
    }
}
