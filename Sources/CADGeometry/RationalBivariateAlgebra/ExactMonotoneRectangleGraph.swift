/// Complete source zero coverage under an original whole-box monotonicity proof.
package struct ExactMonotoneRectangleGraph: Sendable {
    package struct Span: Sendable {
        package let lowerStation: Int
        package let upperStation: Int
    }
    package struct Station: Sendable {
        package let endpoint: ExactMonotoneGraphEndpoint
        package let containsRoot: Bool
    }
    package let original: ExactBivariatePolynomial
    package let sourceDomain: SurfaceParameterBox
    package let freeAlongU: Bool
    package let transverseDerivative: OutwardScalarInterval
    package let stations: [Station]
    package let spans: [Span]
    package let isolatedStationIndices: [Int]
}
