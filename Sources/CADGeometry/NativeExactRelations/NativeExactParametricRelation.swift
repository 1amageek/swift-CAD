import CADCore

/// Original source bindings and complete exact parameter selection/incidence.
public struct NativeExactParametricRelation: Sendable {
    public let source: NativeExactRelationSource
    public let tolerance: ModelingTolerance
    public let coefficientField: ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let relation: ExactParametricRelation<ExactRationalScalarDomain>

    init(source: NativeExactRelationSource, tolerance: ModelingTolerance,
        coefficientField: ExactAlgebraicScalarDomain<ExactRationalScalarDomain>,
        relation: ExactParametricRelation<ExactRationalScalarDomain>) {
        self.source = source; self.tolerance = tolerance
        self.coefficientField = coefficientField; self.relation = relation
    }
}
