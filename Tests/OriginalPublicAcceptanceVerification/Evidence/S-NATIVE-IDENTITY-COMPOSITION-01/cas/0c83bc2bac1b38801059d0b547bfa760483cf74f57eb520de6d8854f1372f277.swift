import CADCore
import CADGeometry

public protocol BRepDistanceQuerying: Sendable {
    func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions) throws -> BRepDistanceQueryResult
    func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult
    func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, accuracy: Double, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult
}

public extension BRepDistanceQuerying {
    func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        validatedModel: ValidatedBRepModel, options: BRepDistanceOptions) throws -> BRepDistanceQueryResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: validatedModel.tolerance,
            message: "This distance provider has no immutable original-source receipt implementation.")
    }

    func distance(from first: BRepDistanceSelection, to second: BRepDistanceSelection,
        in model: BRepModel, options: BRepDistanceOptions, tolerance: ModelingTolerance) throws -> BRepDistanceQueryResult {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This distance provider has no caller-owned relative-accuracy and proof-budget implementation.")
    }
}
