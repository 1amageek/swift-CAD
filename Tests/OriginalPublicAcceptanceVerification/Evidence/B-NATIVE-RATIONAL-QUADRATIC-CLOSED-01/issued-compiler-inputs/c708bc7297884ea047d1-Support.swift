import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import enum PublicLiftPlane.NativeExactGeometryPublicationFailure
import enum PublicLiftPlane.GeometryExactScalarFailure
import struct PublicLiftPlane.DefaultExactOriginalScalarTransporter
import class PublicLiftPlane.ExactAlgebraicCalculation
import struct PublicLiftPlane.ExactAlgebraicEmbedding
import protocol PublicLiftPlane.ExactAlgebraicExtending
import struct PublicLiftPlane.ExactAlgebraicExtension
import struct PublicLiftPlane.ExactAlgebraicScalar
import struct PublicLiftPlane.ExactAlgebraicScalarDomain
import struct PublicLiftPlane.ExactOriginalScalarTransferReceipt
import protocol PublicLiftPlane.ExactOriginalScalarTransferring
import struct PublicLiftPlane.ExactRealRoot
import enum PublicLiftPlane.ExactRealRootBound
import enum PublicLiftPlane.ExactRealRootClassification
import struct PublicLiftPlane.ExactRealRootCount
import struct PublicLiftPlane.ExactRealRootDomain
import enum PublicLiftPlane.ExactRealRootFailure
import struct PublicLiftPlane.ExactRealRootInterval
import struct PublicLiftPlane.ExactRealRootLimits
import protocol PublicLiftPlane.ExactRealRootPreparing
import protocol PublicLiftPlane.ExactRealRootProducing
import protocol PublicLiftPlane.ExactRealRootQuerying
import struct PublicLiftPlane.ExactRealRootSeparation
import struct PublicLiftPlane.ExactRealRootSet
import struct PublicLiftPlane.ExactRealRootSigns
import struct PublicLiftPlane.ExactRealRootSource
import struct PublicLiftPlane.ExactRealRootTransport
import protocol PublicLiftPlane.ExactRealRootTransporting
import struct PublicLiftPlane.ExactRealCellBoundaryRoot
import struct PublicLiftPlane.ExactRealCellCondition
import struct PublicLiftPlane.ExactRealCellDefinition
import struct PublicLiftPlane.ExactRealCellDefinitionStep
import protocol PublicLiftPlane.ExactRealCellDescribing
import struct PublicLiftPlane.ExactRealCellDomain
import enum PublicLiftPlane.ExactRealCellFailure
import struct PublicLiftPlane.ExactRealCellID
import enum PublicLiftPlane.ExactRealCellInstruction
import enum PublicLiftPlane.ExactRealCellKind
import struct PublicLiftPlane.ExactRealCellLimits
import struct PublicLiftPlane.ExactRealCellPartition
import struct PublicLiftPlane.ExactRealCellPredicate
import protocol PublicLiftPlane.ExactRealCellPreparing
import protocol PublicLiftPlane.ExactRealCellProducing
import struct PublicLiftPlane.ExactRealCellProjectionBinding
import struct PublicLiftPlane.ExactRealCellProjectionEvidence
import enum PublicLiftPlane.ExactRealCellProjectionWitness
import protocol PublicLiftPlane.ExactRealCellQuerying
import struct PublicLiftPlane.ExactRealCellSample
import protocol PublicLiftPlane.ExactRealCellSelecting
import struct PublicLiftPlane.ExactRealCellSelection
import struct PublicLiftPlane.ExactRealCellSignInvariant
import enum PublicLiftPlane.ExactRealCellSignRelation
import struct PublicLiftPlane.ExactRealCellSource
import struct PublicLiftPlane.ExactRealCellStackEvidence
import protocol PublicLiftPlane.ExactRealCellTraversing
import struct PublicLiftPlane.ExactRealCellView
import struct PublicLiftPlane.ExactRealAttachment
import struct PublicLiftPlane.ExactRealCellPullback
import protocol PublicLiftPlane.ExactRealCellPullbackResolving
import struct PublicLiftPlane.ExactRealClosure
import protocol PublicLiftPlane.ExactRealClosureProducing
import enum PublicLiftPlane.ExactRealClosureProof
import enum PublicLiftPlane.ExactRealClosureStrategy
import struct PublicLiftPlane.ExactRealComponents
import protocol PublicLiftPlane.ExactRealComponentsProducing
import struct PublicLiftPlane.ExactRealIncidence
import struct PublicLiftPlane.ExactRealIncidencePair
import protocol PublicLiftPlane.ExactRealIncidenceProducing
import struct PublicLiftPlane.ExactRealProjection
import struct PublicLiftPlane.ExactRealProjectionLifts
import protocol PublicLiftPlane.ExactRealProjectionProducing
import typealias PublicLiftPlane.ExactRealTopology
import struct PublicLiftPlane.ExactRealTopologyDomain
import struct PublicLiftPlane.ExactRealTopologyElimination
import struct PublicLiftPlane.ExactRealTopologyFactor
import enum PublicLiftPlane.ExactRealTopologyFailure
import struct PublicLiftPlane.ExactRealTopologyLimits
import protocol PublicLiftPlane.ExactRealTopologyQuerying
import struct PublicLiftPlane.ExactRealTopologyReduction
import struct PublicLiftPlane.ExactRealTopologyRegion
import struct PublicLiftPlane.ExactRealTopologySignInvariant
import struct PublicLiftPlane.ExactParametricConstraintDivision
import struct PublicLiftPlane.ExactParametricGraph
import protocol PublicLiftPlane.ExactParametricGraphConstructing
import struct PublicLiftPlane.ExactParametricGraphRelation
import struct PublicLiftPlane.ExactParametricGraphRelationSource
import protocol PublicLiftPlane.ExactParametricGraphResolving
import struct PublicLiftPlane.ExactParametricGuardDivision
import struct PublicLiftPlane.ExactParametricGuardRemainder
import struct PublicLiftPlane.ExactParametricMap
import struct PublicLiftPlane.ExactParametricRelation
import protocol PublicLiftPlane.ExactParametricRelationConstructing
import struct PublicLiftPlane.ExactParametricRelationDomain
import enum PublicLiftPlane.ExactParametricRelationFailure
import enum PublicLiftPlane.ExactParametricRelationKind
import protocol PublicLiftPlane.ExactParametricRelationResolving
import struct PublicLiftPlane.ExactParametricRelationSource
import struct PublicLiftPlane.ExactParametricSquareReduction
import struct PublicLiftPlane.DefaultExactGeometricGraphRelationResolver
import struct PublicLiftPlane.DefaultExactGeometricRelationResolver
import enum PublicLiftPlane.ExactCurveParameterBoundary
import struct PublicLiftPlane.ExactCurveParameterSpan
import enum PublicLiftPlane.ExactGeometricEvidenceKind
import struct PublicLiftPlane.ExactGeometricFiber
import struct PublicLiftPlane.ExactGeometricGraphFiber
import struct PublicLiftPlane.ExactGeometricGraphPoint
import struct PublicLiftPlane.ExactGeometricGraphRelation
import protocol PublicLiftPlane.ExactGeometricGraphRelationResolving
import struct PublicLiftPlane.ExactGeometricRelation
import enum PublicLiftPlane.ExactGeometricRelationFailure
import struct PublicLiftPlane.ExactGeometricRelationLimits
import protocol PublicLiftPlane.ExactGeometricRelationQuerying
import protocol PublicLiftPlane.ExactGeometricRelationResolving
import enum PublicLiftPlane.ExactGeometricStation
import struct PublicLiftPlane.ExactGeometricStratumID
import struct PublicLiftPlane.ExactGeometricStratumRecord
import struct PublicLiftPlane.ExactGeometricStratumView
import struct PublicLiftPlane.ExactUV
import struct PublicLiftPlane.ExactXYZ
import struct PublicLiftPlane.DefaultOriginalIssuedGraphCompiler
import struct PublicLiftPlane.DefaultOriginalIssuedGraphParameterRefiner
import struct PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver
import enum PublicLiftPlane.NativeExactRelationFailure
import protocol PublicLiftPlane.OriginalIssuedGraphCompiling
import struct PublicLiftPlane.OriginalIssuedGraphFamily
import protocol PublicLiftPlane.OriginalIssuedGraphFamilyPreparing
import struct PublicLiftPlane.OriginalIssuedGraphParameterRefinement
import protocol PublicLiftPlane.OriginalIssuedGraphParameterRefining
import struct PublicLiftPlane.OriginalIssuedGraphPreparation
import protocol PublicLiftPlane.OriginalIssuedGraphRelationOwning
import struct PublicLiftPlane.OriginalIssuedGraphRelationPair
import protocol PublicLiftPlane.OriginalIssuedGraphRelationResolving
import struct PublicLiftPlane.OriginalIssuedGraphRelations
import struct PublicLiftPlane.DefaultOriginalIssuedGeometricRelationResolver
import enum PublicLiftPlane.NativeExactGeometricRelationFailure
import struct PublicLiftPlane.OriginalIssuedExactIntersectionPoint
import struct PublicLiftPlane.OriginalIssuedGeometricRelationPair
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationReading
import protocol PublicLiftPlane.OriginalIssuedGeometricRelationResolving
import struct PublicLiftPlane.OriginalIssuedGeometricRelations
import struct PublicLiftPlane.OriginalLiftPlaneParameterRestriction
import protocol PublicLiftPlane.OriginalPlaneGraphCompiling
import struct PublicLiftPlane.OriginalIssuedPlaneGraph
import struct PublicLiftPlane.DefaultOriginalPlaneGraphCompiler
import struct PublicLiftPlane.OriginalLiftPlaneRelations
import protocol PublicLiftPlane.OriginalLiftPlaneRelationResolving
import struct PublicLiftPlane.DefaultOriginalLiftPlaneRelationResolver
import struct PublicLiftPlane.OriginalLiftPlaneGeometricRelations
import CADCore


@testable import CADKernel
import HashTreeCollections
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import CADTopology

/// The original Coons face and full graph relation used by all three policy cells.
struct CoonsHoleBoundaryProbe {
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
        print("RUN B-COONS complete original Native-line/Coons graph relation")
#if !hasFeature(Embedded)
        print("Graph counts", first.graphs.count, second.graphs.count)
#endif
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

}
