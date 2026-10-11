import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicCoonsBoundary
import CADTopology
import CADKernel
import HashTreeCollections

/// Empty publication and detached readers use the same original Coons support.
@main struct CoonsHoleBoundaryExtras {
    typealias Controls = CoonsHoleBoundaryControls
    typealias Admission = Controls.Admission
    typealias F = OriginalExactScalarDomain
    typealias Field = PublicLiftPlane.ExactAlgebraicScalarDomain<F>

    static func face(host: OriginalCoonsSurface3D) throws -> (ValidatedBRepModel, FaceID) {
        var model = BRepModel()
        let support = Surface3D.procedural(.originalCoons(host)), surfaceID = SurfaceID()
        let curves = CoonsHoleBoundaryProbe.rectangle(0, 0.25)
        let vertices = try curves.map { curve -> Vertex in
            let uv = try curve.startParameter(tolerance: .standard)
            return Vertex(point: try support.point(u: uv.u, v: uv.v, tolerance: .standard))
        }
        var coedges: [Coedge] = []
        for index in curves.indices {
            let next = (index + 1) % curves.count, curveID = CurveID()
            model.geometry.curves[curveID] = .surfaceLift(.init(surface: support,
                parameterCurve: try curves[index].reversed(tolerance: .standard)))
            let edge = Edge(curveID: curveID, startVertexID: vertices[next].id, endVertexID: vertices[index].id,
                trim: .init(startParameter: 0, endParameter: 1))
            model.edges[edge.id] = edge
            coedges.append(.init(edgeID: edge.id, orientation: .reversed, surfaceParameterCurve: curves[index]))
        }
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        let loop = Loop(role: .outer, coedges: coedges), face = Face(surfaceID: surfaceID, loops: [loop.id])
        let shell = Shell(faceIDs: [face.id]), body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support
        model.loops[loop.id] = loop
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return (try .init(model, tolerance: .standard, validationLevel: .exact), face.id)
    }

    static func detached(empty: Bool, using query: inout Admission) throws -> Controls.Result {
        var preparation = try Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &preparation).0
        let original = try empty ? face(host: host) : CoonsHoleBoundaryProbe.face(host: host)
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let limits = try PolylineLiftProof.limits()
        let raw = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
        let binding = try OriginalFaceSurfaceBinding.coons(raw.second.source, limits: limits.source, using: &preparation)
        let source = try Controls.Source.secondSurface(raw, binding: binding, limits: limits, using: &preparation)
        return try Controls.clip(source, face: original, policy: .closed, limits: limits, using: &query)
    }

    static func reader(_ result: Controls.Result, value: Double) throws -> Bool {
        var a = try Admission(work: 80_000_000)
        let field = result.parameters.boundary.source.raw.first.field, limits = try PolylineLiftProof.limits()
        let t = try field.binary64(exactly: value, using: &a)
        let tuple = try [t, t, field.binary64(exactly: 0.5, using: &a)]
        var included = false
        for ordinal in result.parameters.refinements.indices {
            included = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: ordinal, limits: limits,
                rootLimits: .init(maximumRoots: 100), using: &a) || included
        }
        return included
    }

    static func winding() throws {
        var a = try Admission(work: 80_000_000)
        let base = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let roots = try PublicLiftPlane.ExactRealRootDomain(field: field, using: &a)
        let domain = try roots.domain(
            lower: .finite(field.integer(-1, using: &a)), upper: .finite(field.integer(1, using: &a)),
            using: &a)
        let loops = [OriginalNativeBoundaryDomain.Loop(isInner: false, curves: CoonsHoleBoundaryProbe.rectangle(0, 1)),
            .init(isInner: true, curves: CoonsHoleBoundaryProbe.rectangle(0.25, 0.75))]
        for denominatorIsZero in [false, true] {
            for policy in [OriginalNativeBoundaryDomain.Selection.closed, .strictInterior, .boundary] {
                var compiler = try OriginalExactBoundaryCompiler<F>(field: field, using: &a)
                let cells = compiler.cells, ring = cells.polynomials
                let zero = try ring.constant(field.integer(0, using: &a), using: &a)
                let minusOne = try ring.constant(field.integer(-1, using: &a), using: &a)
                let minusHalf = try ring.constant(field.binary64(exactly: -0.5, using: &a), using: &a)
                let x = try ring.variable(0, using: &a), square = try ring.multiplying(x, x, using: &a)
                let numerator = try ring.scaled(square, by: field.integer(-1, using: &a), using: &a)
                let root = try compiler.boundary(loops: loops,
                    numerators: denominatorIsZero ? [zero, zero] : [numerator, minusHalf],
                    denominator: denominatorIsZero ? zero : minusOne, selection: policy, &a)
                let source = try cells.bind(polynomials: compiler.laws, domains: [domain, domain], using: &a)
                let predicate = try cells.predicate(instructions: compiler.instructions(root, &a), for: source, using: &a)
                let partition = try cells.decompose(source, limits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100), using: &a)
                let selected = try cells.select(partition, matching: predicate, using: &a)
                if denominatorIsZero {
                    try PolylineLiftProof.require(selected.cells.isEmpty)
                    continue
                }
                var ordinals: [(Int, Bool)] = []
                for bound in [0.0, 0.25, 0.75, 1] {
                    let law = try ring.subtracting(square, ring.constant(field.binary64(exactly: bound, using: &a), using: &a), using: &a)
                    let inverse = try ring.scaled(law, by: field.integer(-1, using: &a), using: &a)
                    var match: (Int, Bool)?
                    for ordinal in compiler.laws.indices {
                        if try ring.equals(law, compiler.laws[ordinal], using: &a) { match = (ordinal, false); break }
                        if try ring.equals(inverse, compiler.laws[ordinal], using: &a) { match = (ordinal, true); break }
                    }
                    guard let match else { throw Controls.Failure(line: #line) }
                    ordinals.append(match)
                }
                guard let rootCell = try cells.root(in: partition, using: &a) else { throw Controls.Failure(line: #line) }
                var pending = [rootCell]
                while let cell = pending.popLast() {
                    let children = try cells.children(of: cell, in: partition, using: &a)
                    if !children.isEmpty { pending.append(contentsOf: children); continue }
                    var signs: [ExactSign] = []
                    for (ordinal, reverse) in ordinals {
                        let sign = cell.signs[ordinal]
                        signs.append(reverse ? (sign == .zero ? .zero : sign == .negative ? .positive : .negative) : sign)
                    }
                    let closed = signs[0] != .negative && signs[3] != .positive && (signs[1] != .positive || signs[2] != .negative)
                    let boundary = signs[0] == .zero || signs[1] == .zero || signs[2] == .zero || signs[3] == .zero
                    let expected: Bool
                    switch policy {
                    case .closed: expected = closed
                    case .strictInterior: expected = closed && !boundary
                    case .boundary: expected = closed && boundary
                    }
                    try PolylineLiftProof.require(selected.cells.contains(cell) == expected)
                }
            }
        }
        Controls.marker("PASS negative denominator/nonlinear many-preimage winding, full-cell original-law signs and zero-denominator exclusion")
    }

    static func firstSurface() throws {
        var a = try Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &a).0
        let face = try CoonsHoleBoundaryProbe.face(host: host), limits = try PolylineLiftProof.limits()
        let base = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let target = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.init(x: 0, y: 0.5, z: 0), .init(x: 1, y: 0.5, z: 0)],
                            [.init(x: 0, y: 0.5, z: 1), .init(x: 1, y: 0.5, z: 1)]])
        let coons = try DefaultOriginalSourceBindingIssuer(provider: OriginalCoonsAtlasSnapshotProvider(field: base, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let native = try DefaultOriginalSourceBindingIssuer(provider: PolylineLiftAdapters.OriginalBSplineSurfaceSnapshotProvider(tolerance: .standard))
            .bind(target, limits: limits.source, using: &a)
        let coonsCharts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalCoonsAtlasSnapshot>()
            .prepare(source: coons, maximumCharts: 4, limits: limits.source, using: &a)
        let nativeCharts = try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>()
            .prepare(source: native, field: base, maximumCharts: 1, limits: limits.source, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let first = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: CoonsHoleBoundaryProbe.cover(source: coons, laws: coonsCharts.laws, support: coonsCharts.support,
                field: base, limits: limits, using: &a), field: field, maximumGraphs: 4, limits: limits, using: &a)
        let second = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: CoonsHoleBoundaryProbe.cover(source: native, laws: nativeCharts.laws, support: nativeCharts.support,
                field: base, limits: limits, using: &a), field: field, maximumGraphs: 1, limits: limits, using: &a)
        for graph in first.graphs { try CoonsHoleBoundaryAcceptance.checkLaw(graph, isSurface: true, using: &a) }
        for graph in second.graphs {
            let original = graph.original.graph, ring = original.polynomials
            let expected = try [ring.variable(0, using: &a), ring.constant(base.binary64(exactly: 0.5, using: &a), using: &a),
                ring.variable(1, using: &a), ring.constant(base.integer(1, using: &a), using: &a)]
            for axis in expected.indices { try PolylineLiftProof.require(ring.equals(original.homogeneous[axis], expected[axis], using: &a)) }
        }
        let raw = try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: first, second: second, maximumPairs: 4, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
        let binding = try OriginalFaceSurfaceBinding.coons(raw.first.source, limits: limits.source, using: &a)
        let source = try OriginalIssuedGraphBoundarySource.firstSurface(raw, binding: binding, limits: limits, using: &a)
        let nativeBinding = try OriginalFaceSurfaceBinding.native(raw.second.source, limits: limits.source, using: &a)
        let nativeSource = try OriginalIssuedGraphBoundarySource.secondSurface(raw, binding: nativeBinding, limits: limits, using: &a)
        try PolylineLiftProof.require(nativeSource.surface == .bSpline(target))
        var query = try Admission(work: 80_000_000)
        let result = try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
            selection: .closed, domainLimits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try PolylineLiftProof.require(result.parameters.refinements.count == 4)
        guard case .first = result.parameters.boundary.source.side else { throw Controls.Failure(line: #line) }
        for refinement in result.parameters.refinements {
            let pullback = refinement.parameters.pullback, region = pullback.region
            let pair = raw.pairs[refinement.parameters.pairOrdinal]
            try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0, 1] &&
                pair.relation.original.secondCoordinates == [2, 3] && pullback.coordinateMap == [0, 1, 2, 3])
            let cells = try PublicLiftPlane.ExactRealCellDomain<F>(retaining: region.partition.source, using: &a)
            let ring = cells.polynomials, f = try cells.coefficientField(of: region.partition.source, using: &a)
            let t = try ring.variable(0, using: &a)
            var laws = try [0.0, 0.25, 0.75, 1].map { try ring.subtracting(t, ring.constant(f.binary64(exactly: $0, using: &a), using: &a), using: &a) }
            laws += try [ring.subtracting(ring.variable(1, using: &a), ring.constant(f.binary64(exactly: 0.5, using: &a), using: &a), using: &a),
                ring.subtracting(t, ring.variable(2, using: &a), using: &a), ring.variable(3, using: &a)]
            let invariants = try laws.map { law in
                guard let invariant = try cells.signInvariant(for: law, in: region.partition, using: &a) else { throw Controls.Failure(line: #line) }
                return invariant
            }
            for index in region.cells.indices {
                let signs = try invariants.map { try cells.sign(of: $0, at: region.cells[index], using: &a) }
                let expected = signs[0] != .negative && signs[3] != .positive &&
                    (signs[1] != .positive || signs[2] != .negative) && signs[4] == .zero && signs[5] == .zero && signs[6] == .zero
                try PolylineLiftProof.require(region.included[index] == expected)
                let ordinal = pullback.sourceCellOrdinals[index]
                try PolylineLiftProof.require(expected ? pullback.source.cells.indices.contains(ordinal) : ordinal == -1)
                let boundary = signs[0] == .zero || signs[1] == .zero || signs[2] == .zero || signs[3] == .zero
                try CoonsHoleBoundaryAcceptance.verifySpans(refinement.boundarySpans[index],
                    signs: signs, selected: expected, boundary: boundary)
            }
        }
        Controls.marker("PASS SSI first-surface public Kernel complete four-coordinate material oracle and Native source binding")
    }

    static func main() async throws {
        let group = Controls.group()
        if group == "winding" { try winding(); return }
        if group == "ssi" { try firstSurface(); return }
        let limits = try PolylineLiftProof.limits()
        var query = try Admission(work: 80_000_000)
        let result = try detached(empty: false, using: &query)
        try Controls.membership(result, limits: limits)
        async let first = reader(result, value: 0.125)
        async let second = reader(result, value: 0.5)
        let concurrent = try await (first, second)
        try PolylineLiftProof.require(concurrent.0 && !concurrent.1)
        var a = try Admission()
        let foreignBase = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let foreignField = try Field.base(field: foreignBase, maximumExtensionLevel: 32, using: &a)
        let ownField = result.parameters.boundary.source.raw.first.field
        let tuple = try [ownField.integer(0, using: &a), ownField.integer(0, using: &a), ownField.binary64(exactly: 0.5, using: &a)]
        do {
            _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: 0, queryField: foreignField,
                limits: limits, rootLimits: .init(maximumRoots: 100), using: &a)
            throw Controls.Failure(line: #line)
        } catch {
            guard case .incompatibleDomain = Controls.scalar(error) else { throw error }
        }
        Controls.marker("PASS detached source/field/model lifetime, COW, concurrent independent readers and foreign query field refusal")
        var emptyQuery = try Admission(work: 80_000_000)
        let empty = try detached(empty: true, using: &emptyQuery)
        try PolylineLiftProof.require(empty.parameters.refinements.count == 4)
        for refinement in empty.parameters.refinements {
            try PolylineLiftProof.require(refinement.parameters.pullback.region.included.allSatisfy { !$0 } &&
                refinement.parameters.pullback.sourceCellOrdinals.allSatisfy { $0 == -1 } &&
                refinement.boundarySpans.allSatisfy { $0.isEmpty })
        }
        try PolylineLiftProof.require(!reader(empty, value: 0.125))
        var emptyCancelled = try Admission(work: 80_000_000, cancelAt: emptyQuery.checkpoints)
        try Controls.expectCancel { _ = try detached(empty: true, using: &emptyCancelled) }
        Controls.marker("PASS complete empty material result, raw pair retention, detached empty membership and final empty publication cancel")
        if group == "all" {
            try winding()
            try firstSurface()
        }
    }
}
