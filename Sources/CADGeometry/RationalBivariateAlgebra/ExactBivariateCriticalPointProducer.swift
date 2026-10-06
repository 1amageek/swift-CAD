import CADCore

/// Atomic all-original-equation lifting of every square-free critical zero.
package struct ExactBivariateCriticalPointProducer {
    package static func points<B: RationalAlgebraAdmitting>(
        authority: OriginalRationalZeroSetAuthority, over domain: SurfaceParameterBox,
        maximumDepth: Int, usage: inout B) throws -> [ExactBivariateCriticalPoint] {
        guard maximumDepth >= 0 else { throw rationalAlgebraFailure("Exact critical lifting requires caller proof depth.") }
        let source = authority.squareFree
        if source.isZero { throw rationalAlgebraFailure("A full zero field is not a discrete critical-point set.") }
        let pu = try source.differentiated(alongU: true, usage: &usage)
        let pv = try source.differentiated(alongU: false, usage: &usage)
        try usage.retainExactStorage(3)
        let roots = try ExactBivariateSystemSolver.isolatedRoots(of: [source, pu, pv],
            over: domain, maximumDepth: maximumDepth, usage: &usage)
        try usage.retainExactStorage(roots.count)
        var points: [ExactBivariateCriticalPoint] = []
        for root in roots {
            points.append(ExactBivariateCriticalPoint(original: source, projectionRoot: root.projectionRoot,
                fiber: root.fiber, fiberRoot: root.fiberRoot, sourceDomain: domain))
        }
        return points
    }
}
