import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import CADTopology
import NativeDomainAdapters
import NativeKernelAdapters

/// The original Coons face and full graph relation used by all three policy cells.
@main struct CoonsHoleBoundaryProbe {
    typealias F = OriginalExactScalarDomain
    typealias CurveCover = OriginalIssuedDomainCover<BSplineCurve3D, OriginalBSplineChartSelection, F>
    typealias SurfaceCover = OriginalIssuedDomainCover<OriginalCoonsAtlasSnapshot, Int, F>
    typealias Raw = PublicLiftPlane.OriginalIssuedGraphRelations<
        BSplineCurve3D, OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, F>, CurveCover,
        OriginalCoonsAtlasSnapshot, OriginalRationalChartReceipt<OriginalCoonsAtlasSnapshot, Int, F>, SurfaceCover>

    static func cover<S: Sendable, C: Sendable>(source: OriginalSourceBinding<S>,
        laws: [OriginalRationalChartReceipt<S, C, F>], support: [OriginalSourceParameterInterval<OriginalExactScalar>],
        field: F, limits: OriginalDomainIdentityLimits, using a: inout PolylineLiftProof.Admission)
        throws -> OriginalIssuedDomainCover<S, C, F> {
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in support {
            intervals.append([try .checked(field: field, lower: .finite(bound.lower), upper: .finite(bound.upper),
                depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<S, F>().frame(source: source, field: field,
            support: intervals, semantics: Array(repeating: .authoredScalar, count: support.count), limits: limits, using: &a)
        return try DefaultOriginalIssuedDomainBinder().bind(laws: laws,
            request: frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
    }

    static func raw(host: OriginalCoonsSurface3D, field: F, limits: OriginalDomainIdentityLimits,
        using a: inout PolylineLiftProof.Admission) throws -> Raw {
        let curve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.init(x: 0, y: 0.5, z: 0), .init(x: 1, y: 0.5, z: 0)])
        let curveSource = try DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineCurveSnapshotProvider(tolerance: .standard))
            .bind(curve, limits: limits.source, using: &a)
        let surfaceSource = try DefaultOriginalSourceBindingIssuer(provider: OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let curveCharts = try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>()
            .prepare(source: curveSource, field: field, maximumCharts: 1, limits: limits.source, using: &a)
        let surfaceCharts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<OriginalCoonsAtlasSnapshot>()
            .prepare(source: surfaceSource, maximumCharts: 4, limits: limits.source, using: &a)
        let algebraic = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: 32, using: &a)
        let first = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: cover(source: curveSource, laws: curveCharts.laws, support: curveCharts.support,
                field: field, limits: limits, using: &a), field: algebraic, maximumGraphs: 1, limits: limits, using: &a)
        let second = try DefaultOriginalRationalGraphFamilyPreparer().prepare(
            cover: cover(source: surfaceSource, laws: surfaceCharts.laws, support: surfaceCharts.support,
                field: field, limits: limits, using: &a), field: algebraic, maximumGraphs: 4, limits: limits, using: &a)
        print("RUN B-COONS complete original Native-line/Coons graph relation", first.graphs.count, second.graphs.count)
        return try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .curveSurface,
            first: first, second: second, maximumPairs: 4, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func rectangle(_ lower: Double, _ upper: Double) -> [SurfaceParameterCurve] {
        [.constantV(v: lower, uStart: lower, uEnd: upper),
         .constantU(u: upper, vStart: lower, vEnd: upper),
         .constantV(v: upper, uStart: upper, uEnd: lower),
         .constantU(u: lower, vStart: upper, vEnd: lower)]
    }

    static func face(host: OriginalCoonsSurface3D) throws -> (ValidatedBRepModel, FaceID) {
        var model = BRepModel()
        let support = Surface3D.procedural(.originalCoons(host)), surfaceID = SurfaceID()
        var loopIDs: [LoopID] = []
        for (role, curves) in [(LoopRole.outer, rectangle(0, 1)), (.inner, rectangle(0.25, 0.75))] {
            let vertices = try curves.map { pcurve -> Vertex in
                let start = try pcurve.startParameter(tolerance: .standard)
                return Vertex(point: try support.point(u: start.u, v: start.v, tolerance: .standard))
            }
            var coedges: [Coedge] = []
            for index in curves.indices {
                let next = (index + 1) % curves.count, curveID = CurveID()
                let canonical = try curves[index].reversed(tolerance: .standard)
                model.geometry.curves[curveID] = .surfaceLift(.init(surface: support, parameterCurve: canonical))
                let edge = Edge(curveID: curveID, startVertexID: vertices[next].id, endVertexID: vertices[index].id,
                    trim: .init(startParameter: 0, endParameter: 1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID: edge.id, orientation: .reversed, surfaceParameterCurve: curves[index]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role: role, coedges: coedges)
            model.loops[loop.id] = loop
            loopIDs.append(loop.id)
        }
        let face = Face(surfaceID: surfaceID, loops: loopIDs), shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return (try .init(model, tolerance: .standard, validationLevel: .exact), face.id)
    }

    static func main() throws {
        var a = try PolylineLiftProof.Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &a).0
        print("RUN B-COONS original four-cell face validation")
        let original = try face(host: host)
        guard let face = original.0.model.faces[original.1], face.loops.count == 2,
            case .procedural(.originalCoons(let retained)) = original.0.model.geometry.surfaces[face.surfaceID],
            retained == host else { throw ExactScalarFailure.invalidEvidence }
        for (index, identifier) in face.loops.enumerated() {
            guard let loop = original.0.model.loops[identifier], loop.role == (index == 0 ? .outer : .inner),
                loop.coedges.count == 4 else { throw ExactScalarFailure.invalidEvidence }
            let expected = index == 0 ? rectangle(0, 1) : rectangle(0.25, 0.75)
            for ordinal in loop.coedges.indices {
                try PolylineLiftProof.require(loop.coedges[ordinal].orientation == .reversed &&
                    loop.coedges[ordinal].surfaceParameterCurve == expected[ordinal])
            }
        }
        print("PASS B-COONS real exact-validated Coons face; outer/inner retained pcurves and reversed coedges")
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try PolylineLiftProof.limits()
        let raw = try raw(host: host, field: field, limits: limits, using: &a)
        try PolylineLiftProof.require(raw.pairs.count == 4)
        try PolylineLiftProof.require(raw.second.source.original.original == host)
        print("PASS B-COONS source/DI complete raw relation", raw.pairs.count)
#if B_COONS_BINDING_RED
        // The public Kernel clip entry requires this Native-only input constructor.
        _ = NativeDomainAdapters.OriginalExactNativeBoundarySource.curveSurface(raw)
#endif
    }
}
