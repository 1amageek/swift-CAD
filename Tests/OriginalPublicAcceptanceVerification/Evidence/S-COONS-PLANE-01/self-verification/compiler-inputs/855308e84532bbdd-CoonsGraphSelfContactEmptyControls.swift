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

/// Empty graph families retain source-frame authority even with no graph witness.
@main struct CoonsGraphSelfContactEmptyControls {
    typealias Probe = CoonsGraphSelfContactProbe
    typealias Base = Probe.Base
    typealias Admission = PolylineLiftProof.Admission
    typealias Identity = OriginalParameterIdentity<Probe.Source, Base>
    typealias Result = OriginalIssuedGraphSelfContacts<Probe.Source, Probe.Evidence, Probe.Cover, Probe.Evidence, Probe.Cover>
    struct Failure: Error {}
    static func raw(using a: inout Admission) throws -> Probe.Raw {
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &a).0
        let field = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try PolylineLiftProof.limits()
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Probe.Source>()
            .prepare(source: source, maximumCharts: 4, limits: limits.source, using: &a)
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in charts.support {
            intervals.append([try .checked(field: field, lower: .finite(bound.lower), upper: .finite(bound.upper), depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<Probe.Source, Base>().frame(source: source,
            field: field, support: intervals, semantics: [.authoredScalar, .authoredScalar], limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: frame.selection(intervals: [[], []], limits: limits, using: &a), limits: limits, using: &a)
        let algebraic = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: 32, using: &a)
        let family = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover, field: algebraic,
            maximumGraphs: 4, limits: limits, using: &a)
        try PolylineLiftProof.require(family.graphs.isEmpty)
        let raw = try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: 16, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
        try PolylineLiftProof.require(raw.pairs.isEmpty)
        return raw
    }
    static func identity(_ raw: Probe.Raw, field: Base, empty: Bool, wrongRole: Bool = false, using a: inout Admission) throws -> Identity {
        let limits = try PolylineLiftProof.limits(), zero = try field.integer(0, using: &a), one = try field.integer(1, using: &a)
        let interval = try ExactParameterInterval.checked(field: field, lower: .finite(zero), upper: .finite(one), depth: .zero, using: &a)
        let transporter = DefaultOriginalParameterTransporter<Probe.Source, Base>()
        let frame = try transporter.frame(source: raw.first.source, field: field, support: [[interval],[interval]],
            semantics: wrongRole ? [.physicalRadian,.authoredScalar] : [.authoredScalar,.authoredScalar], limits: limits, using: &a)
        let scope = try empty ? frame.selection(intervals: [[],[]], limits: limits, using: &a) : frame.fullSelection(limits: limits, using: &a)
        let map = try transporter.affine(from: scope, to: frame, permutation: [0,1], gains: [one,one], offsets: [zero,zero], limits: limits, using: &a)
        return try DefaultOriginalParameterIdentityIssuer<Probe.Source,Base>().authored(left: map, right: map, limits: limits, using: &a)
    }
    static func query(_ raw: Probe.Raw, _ identities: [Identity], using a: inout Admission) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw, excluding: identities,
            domainLimits: PolylineLiftProof.limits(), cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }
    static func requireScalar(_ error: any Error, matching expected: ExactScalarFailure) throws {
        guard let actual = error as? ExactScalarFailure else { throw error }
        switch (actual, expected) {
        case (.incompatibleDomain, .incompatibleDomain), (.cancelled, .cancelled): return
        case (.resourceLimit(let actualResource), .resourceLimit(let expectedResource)):
            try PolylineLiftProof.require(actualResource == expectedResource)
        default: throw actual
        }
    }
    static func expectScalar(_ expected: ExactScalarFailure, _ body: () throws -> Void) throws {
        do { try body(); throw Failure() }
        catch NativeExactRelationFailure.scalar(let failure) { try requireScalar(failure, matching: expected) }
        catch NativeExactRelationFailure.domain(.scalar(let failure)) { try requireScalar(failure, matching: expected) }
        catch NativeExactRelationFailure.domain(.operationRejected(let failure)) { try requireScalar(failure, matching: expected) }
    }
    static func main() throws {
        var preparation = try Admission()
        let raw = try raw(using: &preparation), field = raw.first.coverage.coverage.request.frame.scalarField
        let foreign = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        print("BEGIN complete empty source-bound family; no graph/pair witness"); fflush(nil)
        for empty in [false,true] {
            let wrong = try identity(raw, field: foreign, empty: empty, using: &preparation)
            var a = try Admission()
            try expectScalar(.incompatibleDomain) { _ = try query(raw, [wrong], using: &a) }
            let role = try identity(raw, field: field, empty: empty, wrongRole: true, using: &preparation)
            var b = try Admission()
            do { _ = try query(raw, [role], using: &b); throw Failure() }
            catch NativeExactRelationFailure.domain(.incompatibleCoordinateSemantics) { }
        }
        let valid = try identity(raw, field: field, empty: false, using: &preparation)
        let emptyIdentity = try identity(raw, field: field, empty: true, using: &preparation)
        var measured = try Admission()
        let result = try query(raw, [valid,emptyIdentity], using: &measured)
        try PolylineLiftProof.require(result.refinements.isEmpty && result.raw.pairs.isEmpty && result.identities.count == 2)
        let work = measured.ledger.work, bytes = measured.ledger.storageBytes
        for resource in [ExactResource.work,.storage] {
            var exact = try Admission(work: resource == .work ? work : 80_000_000, bytes: resource == .storage ? bytes : 1_073_741_824)
            _ = try query(raw, [valid,emptyIdentity], using: &exact)
            var short = try Admission(work: resource == .work ? work-1 : 80_000_000, bytes: resource == .storage ? bytes-1 : 1_073_741_824)
            try expectScalar(.resourceLimit(resource)) { _ = try query(raw, [valid,emptyIdentity], using: &short) }
        }
        for tick in [1,max(2,measured.checkpoints/2),measured.checkpoints] {
            var cancelled = try Admission(cancelAt: tick)
            try expectScalar(.cancelled) { _ = try query(raw, [valid,emptyIdentity], using: &cancelled) }
        }
        var identities = result.identities
        identities.removeAll()
        try PolylineLiftProof.require(result.identities.count == 2 && result.raw.first.coverage.coverage.request.isEmpty)
        print("PASS F1 empty-family valid/foreign-field/semantic identities, exact/one-less resources and publication cancellation")
    }
}
