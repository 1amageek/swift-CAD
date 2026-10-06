import CADCore
@testable import CADGeometry
import Testing

@Suite("Original native prefix exclusion preserves selected coverage")
struct NativePrefixPruningTests {
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
    }

    @Test(.timeLimit(.minutes(1)), arguments: [0,1,2])
    func retainedOriginalDomainsPreservePointEmptyAndPositiveCoverage(mode: Int) throws {
        var admission = usage()
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
            [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)]])
        let curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: mode == 2 ? 0 : 0.5,y: 0.5,z: mode == 0 ? -1 : mode == 1 ? 1 : 0),
            .init(x: mode == 2 ? 1 : 0.5,y: 0.5,z: mode == 0 ? 1 : mode == 1 ? 2 : 0)])
        let box = SurfaceParameterBox(u: try .init(lower: 0, upper: 1), v: try .init(lower: 0, upper: 1))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard)
        let span = try #require(prepared.originalNativeSpans(over: box, tolerance: .standard).first)
        let curveLaw = try OriginalRationalCurvePolynomial(source: curve, spanIndex: 1, tolerance: .standard, usage: &admission)
        let surfaceLaw = try OriginalRationalSurfacePolynomial(source: surface, native: span, domain: box,
            view: .init(x: 0,y: 0,z: 1), tolerance: .standard, usage: &admission)
        let system = try OriginalRationalIntersectionSystem(curve: curveLaw, surface: surfaceLaw, usage: &admission)
        let original = try OriginalRationalIntersectionDecomposition.prepare(system: system, maximumDepth: 32, usage: &admission)
        let pruned = try OriginalRationalIntersectionDecomposition.prepare(system: system,
            pruneExcludedPrefixes: true, maximumDepth: 32, usage: &admission)
        guard case .parameterCells(let full, _, _) = original.coverage,
            case .parameterCells(let reduced, _, _) = pruned.coverage else {
            Issue.record("Native prefix exclusion changed whole-domain coverage kind.")
            return
        }
        #expect(original.nativeDomains == pruned.nativeDomains && original.requestedDomains == pruned.requestedDomains)
        #expect(full.partition.solutionCells.count == reduced.partition.solutionCells.count)
        for ordinal in full.partition.solutionCells.indices {
            let a = full.partition.cells[full.partition.solutionCells[ordinal]]
            let b = reduced.partition.cells[reduced.partition.solutionCells[ordinal]]
            #expect(a.dimension == b.dimension)
            for axis in 0..<3 {
                #expect(try a.coordinates[axis].rationalValue(usage: &admission)
                    == b.coordinates[axis].rationalValue(usage: &admission))
            }
        }
        #expect(!reduced.partition.excludedPrefixes.isEmpty)
        if mode == 0 { #expect(reduced.partition.solutionCells.count == 1) }
        if mode == 1 { #expect(reduced.partition.solutionCells.isEmpty) }
        if mode == 2 { #expect(reduced.partition.solutionCells.contains { reduced.partition.cells[$0].dimension > 0 }) }
    }
}
