import CADCore

public protocol SolidComplexValidating: Sendable {
    func validate(
        _ complex: SolidComplexTopology, in model: BRepModel,
        tolerance: ModelingTolerance, options: SolidComplexValidationOptions
    ) throws
}
