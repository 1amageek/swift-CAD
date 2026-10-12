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
        var rectangleIDs: [Int] = []
        for (index, graph) in family.graphs.enumerated() {
            let original = graph.original.graph, originalRing = original.polynomials
            let zero = try originalRing.constant(f.integer(0, using: &a), using: &a)
            let unit = try originalRing.constant(f.integer(1, using: &a), using: &a)
            let expected = [try originalRing.variable(0, using: &a),
                try originalRing.variable(1, using: &a), zero, unit]
            guard original.layout.variableCount == 2, original.includesUpperBoundary == [true, true] else {
                throw ExactScalarFailure.invalidEvidence
            }
            for axis in 0..<4 {
                guard try originalRing.equals(original.homogeneous[axis], expected[axis], using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
            }
            for axis in 0..<2 {
                guard try originalRing.equals(original.parameterTransport.numerators[axis], expected[axis], using: &a),
                    try originalRing.equals(original.parameterTransport.denominators[axis], unit, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
            }
            var rectangle: [Double]?
            for vi in 0..<2 { for ui in 0..<2 {
                let candidate = [Double(ui)/2, Double(ui+1)/2, Double(vi)/2, Double(vi+1)/2]
                var matches = true
                for axis in 0..<2 {
                    if try f.compare(original.support[axis].lower,
                        f.binary64(exactly: candidate[2*axis], using: &a), using: &a) != .equal { matches = false }
                    if try f.compare(original.support[axis].upper,
                        f.binary64(exactly: candidate[2*axis+1], using: &a), using: &a) != .equal { matches = false }
                }
                if matches {
                    guard rectangle == nil, !rectangleIDs.contains(ui+2*vi) else { throw ExactScalarFailure.invalidEvidence }
                    rectangle = candidate; rectangleIDs.append(ui+2*vi)
                }
            } }
            guard let rectangle else { throw ExactScalarFailure.invalidEvidence }
            stage("L5_ENTRY chart \(index)")
            let input = try solver.compile(kind: .surfaceSurface, first: graph.graph, second: planeGraph.graph, using: &a)
            let relation = try solver.resolve(input, cellLimits: geometryLimits.cells,
                topologyLimits: geometryLimits.topology, using: &a)
            guard relation.components.count <= options.maximumSeedCount else { throw ExactScalarFailure.resourceLimit(.work) }
            stage("L5_RESULT chart \(index) selected \(relation.selection.cells.count) components \(relation.components.count)")
            let geometry = try DefaultExactGeometricGraphRelationResolver<Base>().resolve(relation,
                limits: geometryLimits, using: &a)
            let selection = relation.projection.original, partition = selection.partition
            guard partition.source.variableCount == 4,
                relation.original.firstCoordinates == [0,1], relation.original.secondCoordinates == [2,3] else {
                throw ExactScalarFailure.invalidEvidence
            }
            let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
            let coordinates = try (0..<4).map { try ring.variable($0, using: &a) }
            let half = try ring.constant(ring.field.importingBase(f.binary64(exactly: 0.5, using: &a), using: &a), using: &a)
            var constraints = [try ring.subtracting(coordinates[0], half, using: &a),
                coordinates[2], try ring.adding(coordinates[1], coordinates[3], using: &a)]
            for axis in 0..<2 { for end in 0..<2 {
                let value = try ring.field.importingBase(f.binary64(exactly: rectangle[2*axis+end], using: &a), using: &a)
                constraints.append(try ring.subtracting(coordinates[axis], ring.constant(value, using: &a), using: &a))
            } }
            let signs = try constraints.map { polynomial in
                guard let sign = try cells.signInvariant(for: polynomial, in: partition, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                return sign
            }
            for cell in partition.cells where cell.axis == 3 {
                var accepted = true
                for i in 0..<3 {
                    if try cells.sign(of: signs[i], at: cell, using: &a) != .zero { accepted = false }
                }
                for i in 3..<signs.count {
                    let sign = try cells.sign(of: signs[i], at: cell, using: &a)
                    if (i-3)%2 == 0 ? sign == .negative : sign == .positive { accepted = false }
                }
                guard selection.cells.contains(cell) == accepted else { throw ExactScalarFailure.invalidEvidence }
            }
            guard geometry.strata.count == 3,
                geometry.strata.filter({ $0.parameterDimension == 1 }).count == 1,
                geometry.strata.allSatisfy({ $0.imageDimension == $0.parameterDimension && $0.fiberDimension == 0 }) else {
                throw ExactScalarFailure.invalidEvidence
            }
            guard !relation.selection.cells.isEmpty else { throw ExactScalarFailure.invalidEvidence }
            nonempty += 1
            print("L6_RESULT chart", index, "strata", geometry.strata.count)
        }
        guard nonempty == 4, rectangleIDs.count == 4 else { throw ExactScalarFailure.invalidEvidence }
        try a.checkpoint()
        stage("PASS full partition oracle: U=.5, planeU=0, planeV=-V; all four closed charts; image1/fiber0")
        stage("SCOPE existing source/DI/L5/L6 verification only; ordinary dispatch, ownership publication and acceptance remain open")
    }
}
