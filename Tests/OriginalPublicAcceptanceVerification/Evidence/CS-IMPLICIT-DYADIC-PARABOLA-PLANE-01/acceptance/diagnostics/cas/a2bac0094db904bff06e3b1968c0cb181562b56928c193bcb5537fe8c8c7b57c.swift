/// Sealed whole-support triangular graph theorem and original host correspondence.
public struct OriginalImplicitCurveGraphEvidence: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public typealias Polynomial = ExactPolynomial<Field>
    public let source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>
    public let field: Field
    public let first: OriginalFiniteBSplineCharts<BSplineSurface3D>
    public let second: OriginalFiniteBSplineCharts<BSplineSurface3D>
    public let graphPolynomials: ExactPolynomialDomain<Field>
    public let conditions: [OriginalParametricGraphCondition<Field>]
    public let parameterPolynomials: ExactPolynomialDomain<Field>
    public let freeOffset: Field.Value
    public let freeGain: Field.Value
    public let forwardHostCoordinates: [Polynomial]
    public let forwardHomogeneous: [Polynomial]
    public let forwardHomogeneousDerivative: [Polynomial]
    public let hostCoordinateRanges: [OriginalSourceParameterInterval<Field.Value>]
    public let eliminationAxes: [Int]
    public let eliminationEquations: [Int]
    public let eliminationPivots: [Field.Value]
    public let dependentJacobian: Polynomial
    public let proofDepth: ExactScalarDepth

    init(source: OriginalSourceBinding<OriginalImplicitCurveSnapshot>, field: Field,
        first: OriginalFiniteBSplineCharts<BSplineSurface3D>, second: OriginalFiniteBSplineCharts<BSplineSurface3D>,
        graphPolynomials: ExactPolynomialDomain<Field>, conditions: [OriginalParametricGraphCondition<Field>],
        parameterPolynomials: ExactPolynomialDomain<Field>, freeOffset: Field.Value, freeGain: Field.Value,
        forwardHostCoordinates: [Polynomial],
        forwardHomogeneous: [Polynomial], forwardHomogeneousDerivative: [Polynomial],
        hostCoordinateRanges: [OriginalSourceParameterInterval<Field.Value>], eliminationAxes: [Int],
        eliminationEquations: [Int], eliminationPivots: [Field.Value], dependentJacobian: Polynomial,
        proofDepth: ExactScalarDepth) {
        self.source = source; self.field = field; self.first = first; self.second = second
        self.graphPolynomials = graphPolynomials; self.conditions = conditions
        self.freeOffset = freeOffset; self.freeGain = freeGain
        self.parameterPolynomials = parameterPolynomials; self.forwardHostCoordinates = forwardHostCoordinates
        self.forwardHomogeneous = forwardHomogeneous; self.forwardHomogeneousDerivative = forwardHomogeneousDerivative
        self.hostCoordinateRanges = hostCoordinateRanges; self.eliminationAxes = eliminationAxes
        self.eliminationEquations = eliminationEquations; self.eliminationPivots = eliminationPivots
        self.dependentJacobian = dependentJacobian; self.proofDepth = proofDepth
    }

    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            guard limits.remainingSourceDepth > 0, first.laws.count == 1, second.laws.count == 1,
                source.original.first.owns(first.laws[0].chart), source.original.second.owns(second.laws[0].chart) else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            try first.source.require(children); try second.source.require(children)
            func polynomial(_ p: Polynomial) throws {
                try a.admitDepth(value: p.depth.value, coefficient: p.depth.coefficient)
                for term in p.terms { try a.consumeWork(1); _ = try field.importing(term.coefficient, using: &a) }
            }
            func family(_ family: borrowing OriginalFiniteBSplineCharts<BSplineSurface3D>) throws {
                try a.consumeWork(1)
                for bound in family.support {
                    _ = try field.importing(bound.lower,using:&a); _ = try field.importing(bound.upper,using:&a)
                }
                for law in family.laws {
                    try law.admitProof(using:&a)
                    for p in law.homogeneous { try polynomial(p) }
                    for p in law.parameterTransport.numerators { try polynomial(p) }
                    for p in law.parameterTransport.denominators { try polynomial(p) }
                }
            }
            try family(first); try family(second)
            for condition in conditions { try polynomial(condition.polynomial) }
            _ = try field.importing(freeOffset,using:&a); _ = try field.importing(freeGain,using:&a)
            for p in forwardHostCoordinates { try polynomial(p) }
            for p in forwardHomogeneous { try polynomial(p) }
            for p in forwardHomogeneousDerivative { try polynomial(p) }
            try polynomial(dependentJacobian)
            for bound in hostCoordinateRanges {
                _ = try field.importing(bound.lower,using:&a); _ = try field.importing(bound.upper,using:&a)
            }
            for pivot in eliminationPivots { _ = try field.importing(pivot,using:&a) }
            try a.consumeWork(eliminationAxes.count + eliminationEquations.count)
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}
