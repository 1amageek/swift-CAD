import CADCore

public extension KernelQuery {
    func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case .evaluatedDocument, .diagnostics:
            return
        case let .lineage(subshapeID):
            guard subshapeID.isValid else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: subshapeID,
                    tolerance: tolerance,
                    message: "Kernel lineage query contains an invalid subshape identity."
                )
            }
        case let .snap(query):
            try query.validate(tolerance: tolerance)
        case let .measurement(query):
            try query.validate()
        case .selectionDimensionEvaluation:
            return
        case let .projection(query):
            try query.validate(tolerance: tolerance)
        }
    }
}
