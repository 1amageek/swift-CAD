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

import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicCoonsSelf
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// The real Native offset retains its positive normal-root auxiliary q.
@main struct CoonsGraphSelfContactAuxiliary {
    typealias Base = OriginalExactScalarDomain
    typealias Source = OriginalOffsetSnapshot<BSplineSurface3D>
    typealias Evidence = OriginalOffsetLawReceipt<Source, OriginalBSplineChartSelection, Base>
    typealias Cover = OriginalNativeOffsetDomainCover<Source>
    typealias Raw = PublicLiftPlane.OriginalIssuedGraphRelations<Source, Evidence, Cover, Source, Evidence, Cover>
    typealias Result = OriginalIssuedGraphSelfContacts<Source, Evidence, Cover, Evidence, Cover>
    typealias Admission = PolylineLiftProof.Admission
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>

    static func marker(_ value: StaticString) { print(value); fflush(nil) }

    static func raw(using a: inout Admission) throws -> Raw {
        let native = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let shape = OffsetSurface3D(source: .bSpline(native), distance: 0.25)
        let limits = try PolylineLiftProof.limits()
        let source = try DefaultOriginalSourceBindingIssuer(provider: OriginalOffsetSnapshotProvider(
            child: OriginalNativeSurfaceFamilySnapshotProvider(tolerance: .standard)))
            .bind(shape, limits: limits.source, using: &a)
        let base = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let child = try PolylineLiftAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
            source: source.original.originalChild, field: base, maximumCharts: 1, limits: limits.source, using: &a)
        let laws = try DefaultOriginalFiniteNativeOffsetLawPreparer<Source>().prepare(source: source,
            child: child, maximumCharts: 1, limits: limits.source, using: &a)
        let issuer = DefaultOriginalNativeOffsetDomainIssuer<Source>()
        let frame = try issuer.frame(family: laws, limits: limits, using: &a)
        let zero = try base.integer(0, using: &a)
        let singleton = try ExactParameterInterval.checked(field: base, lower: .finite(zero), upper: .finite(zero),
            depth: .zero, using: &a)
        let request = try frame.selection(intervals: [[singleton], [singleton]], limits: limits, using: &a)
        let cover = try issuer.issue(request: request, family: laws, limits: limits, using: &a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: base, maximumExtensionLevel: 32, using: &a)
        let family = try DefaultOriginalOffsetGraphFamilyPreparer<Source>().prepare(cover: cover,
            field: field, maximumGraphs: 1, limits: limits, using: &a)
        try PolylineLiftProof.require(family.parameterCount == 2 && family.graphs.count == 1)
        let graph = family.graphs[0].original.graph
        try PolylineLiftProof.require(graph.layout.variableCount == 3 && graph.layout.parameters == [0, 1]
            && graph.layout.auxiliaries == [2])
        let ring = graph.polynomials
        let q = try ring.variable(2, using: &a)
        let one = try ring.constant(base.integer(1, using: &a), using: &a)
        let quarter = try base.binary64(exactly: 0.25, using: &a)
        let expected = [try ring.multiplying(q, ring.variable(0, using: &a), using: &a),
            try ring.multiplying(q, ring.variable(1, using: &a), using: &a),
            try ring.scaled(one, by: quarter, using: &a), q]
        for axis in expected.indices {
            try PolylineLiftProof.require(ring.equals(graph.homogeneous[axis], expected[axis], using: &a))
        }
        return try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: 1, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func oracle(_ raw: Raw, using a: inout Admission) throws {
        try PolylineLiftProof.require(raw.pairs.count == 1 && raw.first.source.owner === raw.second.source.owner)
        let pair = raw.pairs[0], selected = pair.relation.projection.original
        let partition = selected.partition
        try PolylineLiftProof.require(partition.source.variableCount == 6)
        try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0, 1, 4]
            && pair.relation.original.secondCoordinates == [2, 3, 5])
        let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
        let one = try ring.constant(ring.field.integer(1, using: &a), using: &a)
        // The singleton request leaves authored UV dimension two; q is still the original guarded root.
        let laws = [try ring.variable(0, using: &a), try ring.variable(1, using: &a),
            try ring.variable(2, using: &a), try ring.variable(3, using: &a),
            try ring.subtracting(ring.multiplying(ring.variable(4, using: &a), ring.variable(4, using: &a), using: &a), one, using: &a),
            try ring.subtracting(ring.multiplying(ring.variable(5, using: &a), ring.variable(5, using: &a), using: &a), one, using: &a),
            try ring.variable(4, using: &a), try ring.variable(5, using: &a)]
        let invariants = try laws.map { law in
            guard let value = try cells.signInvariant(for: law, in: partition, using: &a) else {
                throw ExactScalarFailure.invalidEvidence
            }
            return value
        }
        var selectedCount = 0
        for cell in partition.cells where cell.axis == 5 {
            var expected = true
            for index in invariants.indices {
                let sign = try cells.sign(of: invariants[index], at: cell, using: &a)
                expected = expected && (index < 6 ? sign == .zero : sign == .positive)
            }
            try PolylineLiftProof.require(selected.cells.contains(cell) == expected)
            if expected { selectedCount += 1 }
        }
        try PolylineLiftProof.require(selectedCount > 0)
        marker("PASS real Native offset singleton control raw equals complete UV0=UV1=(0,0) plus q0=q1=1 oracle in six lifted variables")
    }

    static func main() throws {
        var preparation = try Admission(work: 80_000_000)
        marker("BEGIN actual Native offset source/DI six-variable raw construction")
        let raw = try raw(using: &preparation)
        marker("PASS actual Native offset source/DI raw construction")
        try oracle(raw, using: &preparation)
        var query = try Admission(work: 80_000_000)
        marker("BEGIN actual auxiliary public self consumer")
        let result: Result = try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw,
            domainLimits: PolylineLiftProof.limits(),
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try PolylineLiftProof.require(result.raw.pairs.count == 1 && result.authoredDiagonals.count == 1 && result.refinements.count == 1)
        let refined = result.refinements[0], pullback = refined.pullback
        let source = raw.pairs[0].relation.projection.original
        try PolylineLiftProof.require(refined.pairOrdinal == 0 && pullback.coordinateMap == [0, 1, 2, 3, 4, 5])
        try PolylineLiftProof.require(pullback.source.cells.count == source.cells.count)
        for index in source.cells.indices { try PolylineLiftProof.require(pullback.source.cells[index] == source.cells[index]) }
        try PolylineLiftProof.require(pullback.region.included.allSatisfy { !$0 }
            && pullback.sourceCellOrdinals.allSatisfy { $0 == -1 })
        try oracle(result.raw, using: &preparation)
        marker("PASS real Native offset self query complete empty residual retains source cells and both positive normal-root auxiliaries")
    }
}
