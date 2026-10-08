import CADCore

/// Complete original source, parameter topology, XYZ image and all parameter fibers.
public struct NativeExactGeometricRelation: Sendable {
    public let parameterRelation: NativeExactParametricRelation
    public let geometry: ExactGeometricRelation<ExactRationalScalarDomain>

    public let hasPositiveDimensionalSolutions: Bool
    public let hasPositiveDimensionalImage: Bool

    init(parameterRelation: NativeExactParametricRelation,
        geometry: ExactGeometricRelation<ExactRationalScalarDomain>,
        hasPositiveDimensionalSolutions: Bool, hasPositiveDimensionalImage: Bool) {
        self.parameterRelation = parameterRelation
        self.geometry = geometry
        self.hasPositiveDimensionalSolutions = hasPositiveDimensionalSolutions
        self.hasPositiveDimensionalImage = hasPositiveDimensionalImage
    }
}
