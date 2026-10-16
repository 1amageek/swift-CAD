/// Complete original point-blowup resolution at a retained ordered-field station.
package struct OriginalFieldSingularResolution: Sendable {
    package let original: OriginalSingularFieldPlanePolynomial
    package let originalStation: OriginalSingularFieldSystemRoot
    package let germs: [OriginalSingularResolution.Germ]
    package let isolatedGerms: [OriginalSingularResolution.IsolatedGerm]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldPlanePolynomial,
        at station: OriginalSingularFieldSystemRoot, maximumDepth: Int, usage: inout B) throws {
        guard case .zero = try station.sign(of: original, maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original field singular resolution requires a proved source zero.")
        }
        let context = station.v.context
        let first = try station.u.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        let x = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true, in: context,
            maximumDepth: maximumDepth, usage: &usage).adding(
                .constant(first, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        let y = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: false, in: context,
            maximumDepth: maximumDepth, usage: &usage).adding(
                .constant(station.v, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        let repeated = try OriginalSingularFieldPlaneGCD.gcd(original,
            original.differentiated(alongU: true, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        let common = try OriginalSingularFieldPlaneGCD.gcd(repeated,
            original.differentiated(alongU: false, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        let reduced = try original.dividedExactly(by: common, maximumDepth: maximumDepth, usage: &usage)
        let local = try reduced.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
            .composed(withU: x, v: y, maximumDepth: maximumDepth, usage: &usage)
        let depth = max(station.projectionRoot.isolation.depth, station.fiberRoot.isolation.depth)
        let resolved = try OriginalSingularResolution.resolve(local: local, originalU: x, originalV: y,
            inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
        self.original = original; originalStation = station
        germs = resolved.germs; isolatedGerms = resolved.isolatedGerms
    }
}
