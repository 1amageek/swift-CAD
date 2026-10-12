import CADCore
@testable import CADGeometry
import Foundation

/// Diagnoses the existing source/DI/plane L5 path without numerical SSI fallback.
@main struct CoonsPlaneIssuedGraphProbe {
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var checkpoints=0
        let cancelAt: Int?
        init(work: Int=300_000_000,bytes: Int=1_073_741_824,coefficient: Int=32,cancelAt: Int?=nil) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:coefficient));self.cancelAt=cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints==cancelAt { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    static func main() {
        do { try run() }
        catch { print("OBSERVED_FAILURE", error); exit(1) }
    }
    static func stage(_ message: String) { print(message); fflush(stdout) }
    static func run() throws {
        var construction = try Admission()
        let host = try ExactScalarNumericAccess.withAdmission(&construction) { usage in
            let stations = [0.0, 0.5, 1.0]
            let knots = [0.0, 0, 0.5, 1, 1]
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: stations.map { v in stations.map { u in .init(x: u, y: v, z: 0) } })
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of: .bSpline(native), at: side, maximumDepth: 0,
                    maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            return try OriginalCoonsSurface3D(vMinimumBoundary: boundary(.vLower),
                vMaximumBoundary: boundary(.vUpper), uMinimumBoundary: boundary(.uLower),
                uMaximumBoundary: boundary(.uUpper), tolerance: .standard, usage: &usage)
        }.value
        let options = SurfaceSurfaceIntersectionOptions()
        let usage = try NativeSurfaceSurfacePointAllowance(options: options, admission: .legacy)
        let depth = usage.maximumAlgebraicDepth
        var a = NativeExactPublicAdmission(usage: usage, maximumDepth: depth)
        let limits = try OriginalDomainIdentityLimits(source: .init(remainingSourceDepth: options.maximumSubdivisionDepth),
            maximumTransportDepth: depth, maximumCharts: options.maximumSubdivisionCells,
            maximumFamilies: 2, maximumIdentityProofs: 0)
        typealias Base = OriginalExactScalarDomain
        typealias Source = OriginalCoonsAtlasSnapshot
        typealias Cells = ExactRealCellDomain<Base>
        let f = try Base(maximumValueDepth: depth, maximumCoefficientDepth: depth, using: &a)
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalCoonsAtlasSnapshotProvider(field: f, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source: source, maximumCharts: 4, limits: limits.source, using: &a)
        let issuer = DefaultOriginalRetainedSurfaceDomainIssuer<Source>()
        let frame = try issuer.frame(family: charts, limits: limits, using: &a)
        let request = try frame.fullSelection(limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: request, limits: limits, using: &a)
        let field = try ExactAlgebraicScalarDomain.base(field: f, maximumExtensionLevel: depth, using: &a)
        let family = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover,
            field: field, maximumGraphs: 4, limits: limits, using: &a)
        guard family.graphs.count == 4 else { throw ExactScalarFailure.invalidEvidence }
        stage("SOURCE_DI complete original Coons four-chart family")
        let target = Surface3D.plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX))
        let plane = try DefaultOriginalSourceBindingIssuer(provider: OriginalPlaneSnapshotProvider(tolerance: .standard))
            .bind(target, limits: limits.source, using: &a)
        let one = try f.integer(1, using: &a)
        let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot,Base>()
            .issue(source: plane, field: f, firstLength: one, normalLength: one, limits: limits.source, using: &a)
        let domain = DefaultOriginalPlaneDomainIssuer<OriginalPlaneSnapshot,Base>()
        let planeFrame = try domain.frame(basis: basis, limits: limits, using: &a)
        let planeCover = try domain.issue(request: planeFrame.fullSelection(limits: limits, using: &a),
            basis: basis, limits: limits, using: &a)
        let planeGraph = try DefaultOriginalPlaneGraphCompiler<OriginalPlaneSnapshot>()
            .compile(cover: planeCover, field: field, limits: limits, using: &a)
        stage("PLANE_DI complete original unbounded UV graph")
        let solver = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(
            cells: Cells.self, topology: .init(cells: Cells.self))
        let geometryLimits = try NativeExactPublicLimits.unboundedStructure()
        var nonempty = 0
        for (index, graph) in family.graphs.enumerated() {
            stage("L5_ENTRY chart \(index)")
            let input = try solver.compile(kind: .surfaceSurface, first: graph.graph, second: planeGraph.graph, using: &a)
            let relation = try solver.resolve(input, cellLimits: geometryLimits.cells,
                topologyLimits: geometryLimits.topology, using: &a)
            guard relation.components.count <= options.maximumSeedCount else { throw ExactScalarFailure.resourceLimit(.work) }
            stage("L5_RESULT chart \(index) selected \(relation.selection.cells.count) components \(relation.components.count)")
            let geometry = try DefaultExactGeometricGraphRelationResolver<Base>().resolve(relation,
                limits: geometryLimits, using: &a)
            guard !relation.selection.cells.isEmpty else { throw ExactScalarFailure.invalidEvidence }
            nonempty += 1
            print("L6_RESULT chart", index, "strata", geometry.strata.count)
        }
        guard nonempty == 4 else { throw ExactScalarFailure.invalidEvidence }
        try a.checkpoint()
        stage("SCOPE existing source/DI/L5/L6 diagnostic only; ordinary dispatch, whole-cell oracle, ownership publication and acceptance remain open")
    }
}
