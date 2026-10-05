import CADCore

/// A proved real original graph component, rather than an unproved common polynomial factor.
public struct NativeCurveCurveAlgebraicCorrespondence: Sendable {
    public enum DependentParameter: Sendable {
        case first, second, unconstrained
        /// The retained polynomial locus map owns traversal; neither native axis is asserted monotone.
        case polynomialMap
    }
    public let parameters: SurfaceParameterBox
    public let commonFactor: ExactBivariatePolynomial
    public let originalEquationQuotients: [ExactBivariatePolynomial]
    public let dependentParameter: DependentParameter
    public let firstNativeSpan: Int
    public let secondNativeSpan: Int
    /// Retains the original clipped-sector authority when edge signs need exact partitioning.
    let originalMonotoneGraph: ExactMonotoneRectangleGraph?
    /// Retains the original polynomial map and complete rectangle clipping authority.
    let originalPolynomialParameterDomain: OriginalRationalPolynomialParameterDomain?

    init(parameters: SurfaceParameterBox, commonFactor: ExactBivariatePolynomial,
         originalEquationQuotients: [ExactBivariatePolynomial], dependentParameter: DependentParameter,
         firstNativeSpan: Int, secondNativeSpan: Int,
         originalMonotoneGraph: ExactMonotoneRectangleGraph? = nil,
         originalPolynomialParameterDomain: OriginalRationalPolynomialParameterDomain? = nil) {
        self.parameters = parameters
        self.commonFactor = commonFactor
        self.originalEquationQuotients = originalEquationQuotients
        self.dependentParameter = dependentParameter
        self.firstNativeSpan = firstNativeSpan
        self.secondNativeSpan = secondNativeSpan
        self.originalMonotoneGraph = originalMonotoneGraph
        self.originalPolynomialParameterDomain = originalPolynomialParameterDomain
    }
}
