/// One original template's complete domain and exact forward coordinate laws.
public struct OriginalContainedLiftPlanePiece: Sendable {
    public let templateOrdinal: Int
    public let domain: ExactParameterSet<OriginalExactScalarDomain>
    public let polynomials: ExactPolynomialDomain<OriginalExactScalarDomain>
    public let originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>]
    public let homogeneous: [ExactPolynomial<OriginalExactScalarDomain>]
    public let planeNumerators: [ExactPolynomial<OriginalExactScalarDomain>]
    public let mapEvidence: ExactPolynomialCurveMapEvidence<OriginalExactScalarDomain>
    public let intervalDimensions: [Int]
    public let depth: ExactScalarDepth
    private let owner: any Sendable
    init(templateOrdinal: Int, domain: ExactParameterSet<OriginalExactScalarDomain>,
        polynomials: ExactPolynomialDomain<OriginalExactScalarDomain>, originalCoordinates: [ExactPolynomial<OriginalExactScalarDomain>],
        homogeneous: [ExactPolynomial<OriginalExactScalarDomain>], planeNumerators: [ExactPolynomial<OriginalExactScalarDomain>],
        mapEvidence: ExactPolynomialCurveMapEvidence<OriginalExactScalarDomain>, intervalDimensions: [Int], depth: ExactScalarDepth, owner: any Sendable) {
        self.templateOrdinal = templateOrdinal; self.domain = domain; self.polynomials = polynomials
        self.originalCoordinates = originalCoordinates; self.homogeneous = homogeneous; self.planeNumerators = planeNumerators
        self.mapEvidence = mapEvidence; self.intervalDimensions = intervalDimensions; self.depth = depth; self.owner = owner
    }
    public func imageDimension(at intervalOrdinal: Int) -> Int? {
        guard intervalDimensions.indices.contains(intervalOrdinal) else { return nil }
        return mapEvidence.isConstant ? 0 : intervalDimensions[intervalOrdinal]
    }
    public func fiberDimension(at intervalOrdinal: Int) -> Int? {
        guard let image = imageDimension(at: intervalOrdinal) else { return nil }
        return intervalDimensions[intervalOrdinal] - image
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(_ originalT: OriginalExactScalar, using admission: inout A) throws -> Bool {
        try admission.checkpoint()
        try admission.admitDepth(value: depth.value, coefficient: depth.coefficient)
        let domain = try ExactParameterDomain(retaining: self.domain, using: &admission)
        let result = try domain.contains(originalT, in: self.domain, using: &admission)
        try admission.checkpoint(); return result
    }
}
