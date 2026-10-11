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
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Public resource, identity, membership and retained-owner refusal controls.
@main struct CoonsGraphSelfContactControls {
    typealias Probe = CoonsGraphSelfContactProbe
    typealias Admission = PolylineLiftProof.Admission
    typealias Base = Probe.Base
    typealias Identity = OriginalParameterIdentity<Probe.Source, Base>
    typealias Result = OriginalIssuedGraphSelfContacts<Probe.Source, Probe.Evidence, Probe.Cover, Probe.Evidence, Probe.Cover>
    typealias Field = Result.Field
    struct Failure: Error { let line: Int }

    static func marker(_ message: StaticString) { print(message); fflush(nil) }

    static func group() -> String {
#if hasFeature(Embedded)
        if let value = getenv("CAD_PROOF_GROUP") { return String(cString: value) }
        return "membership"
#else
        return CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "membership"
#endif
    }

    static func query(_ raw: Probe.Raw, excluding identities: [Identity] = [],
        limits: OriginalDomainIdentityLimits, using a: inout Admission) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw, excluding: identities,
            domainLimits: limits, cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func contains(_ result: Result, pair: Int = 0, tuple: [Field.Value], queryField: Field? = nil,
        limits: OriginalDomainIdentityLimits, using a: inout Admission) throws -> Bool {
        try result.contains(pairOrdinal: pair, liftedCoordinates: tuple, queryField: queryField,
            domainLimits: limits, rootLimits: .init(maximumRoots: 100), using: &a)
    }

    static func scalar(_ error: any Error) -> ExactScalarFailure? {
        switch error {
        case let value as ExactScalarFailure: return value
        case let value as NativeExactRelationFailure:
            switch value {
            case .scalar(let e): return e
            case .domain(let e): return scalar(e)
            case .source(let e): return scalar(e)
            case .cell(let e): return scalar(e)
            case .root(let e): return scalar(e)
            case .relation(let e): return scalar(e)
            case .geometry(let e): return scalar(e)
            default: return nil
            }
        case let value as OriginalDomainIdentityFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .source(let e): return scalar(e); default: return nil }
        case let value as OriginalSourceIssuanceFailure:
            switch value { case .scalar(let e): return e; case .sourceRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); default: return nil }
        case let value as ExactRealCellFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .root(let e): return scalar(e); default: return nil }
        case let value as ExactRealRootFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); default: return nil }
        case let value as ExactParametricRelationFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .cell(let e): return scalar(e); case .topology(let e): return scalar(e); default: return nil }
        case let value as ExactRealTopologyFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .cell(let e): return scalar(e); default: return nil }
        case let value as ExactPolynomialFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); default: return nil }
        default: return nil
        }
    }

    static func expectResource(_ resource: ExactResource, line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch { guard case .resourceLimit(let actual) = scalar(error), actual == resource else { throw error } }
    }

    static func expectCancel(line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch { guard case .cancelled = scalar(error) else { throw error } }
    }

    static func expectForeignField(line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch { guard case .incompatibleDomain = scalar(error) else { throw error } }
    }

    static func empty(_ result: Result) throws {
        try PolylineLiftProof.require(result.raw.pairs.count == 16 && result.authoredDiagonals.count == 16 && result.refinements.count == 16)
        for ordinal in result.refinements.indices {
            let refined = result.refinements[ordinal], pullback = refined.pullback
            let original = result.raw.pairs[ordinal].relation.projection.original.cells
            try PolylineLiftProof.require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0, 1, 2, 3])
            try PolylineLiftProof.require(pullback.source.cells.count == original.count)
            for index in original.indices { try PolylineLiftProof.require(pullback.source.cells[index] == original[index]) }
            try PolylineLiftProof.require(pullback.region.included.allSatisfy { !$0 })
            try PolylineLiftProof.require(pullback.sourceCellOrdinals.allSatisfy { $0 == -1 })
        }
    }

    static func resources(_ raw: Probe.Raw, resource: ExactResource, limits: OriginalDomainIdentityLimits) throws {
        var measured = try Admission(work: 80_000_000)
        let result = try query(raw, limits: limits, using: &measured)
        try empty(result)
        let work = measured.ledger.work, bytes = measured.ledger.storageBytes
        try PolylineLiftProof.require(work > 0 && bytes > 0)
        // Test each budget independently so a different budget cannot cause refusal.
        var exact = try Admission(work: resource == .work ? work : 80_000_000,
            bytes: resource == .storage ? bytes : 1_073_741_824)
        try empty(query(raw, limits: limits, using: &exact))
        try PolylineLiftProof.require(exact.ledger.work == work && exact.ledger.storageBytes == bytes)
        var short = try Admission(work: resource == .work ? work - 1 : 80_000_000,
            bytes: resource == .storage ? bytes - 1 : 1_073_741_824)
        try expectResource(resource) { _ = try query(raw, limits: limits, using: &short) }
        try PolylineLiftProof.require(measured.ledger.work == work && measured.ledger.storageBytes == bytes)
        marker("PASS public self query independent exact budget and one-less typed refusal")
    }

    static func cancellation(_ raw: Probe.Raw, limits: OriginalDomainIdentityLimits) throws {
        var measured = try Admission(work: 80_000_000)
        try empty(query(raw, limits: limits, using: &measured))
        try PolylineLiftProof.require(measured.checkpoints > 2)
        for tick in [1, max(2, measured.checkpoints / 2), measured.checkpoints] {
            var cancelled = try Admission(work: 80_000_000, cancelAt: tick)
            try expectCancel { _ = try query(raw, limits: limits, using: &cancelled) }
            try PolylineLiftProof.require(cancelled.checkpoints == tick)
        }
        marker("PASS public self query entry/mid/final empty-result publication cancellation")
    }

    static func identity(source: OriginalSourceBinding<Probe.Source>, field: Base, empty: Bool = false,
        semantics: [OriginalCoordinateSemantics] = [.authoredScalar, .authoredScalar],
        limits: OriginalDomainIdentityLimits, using a: inout Admission) throws -> Identity {
        let zero = try field.integer(0, using: &a), one = try field.integer(1, using: &a)
        let interval = try ExactParameterInterval.checked(field: field, lower: .finite(zero), upper: .finite(one), depth: .zero, using: &a)
        let transporter = DefaultOriginalParameterTransporter<Probe.Source, Base>()
        let frame = try transporter.frame(source: source, field: field, support: [[interval], [interval]],
            semantics: semantics, limits: limits, using: &a)
        let scope = try empty ? frame.selection(intervals: [[], []], limits: limits, using: &a)
            : frame.fullSelection(limits: limits, using: &a)
        try PolylineLiftProof.require(scope.isEmpty == empty)
        let map = try transporter.affine(from: scope, to: frame, permutation: [0, 1], gains: [one, one],
            offsets: [zero, zero], limits: limits, using: &a)
        return try DefaultOriginalParameterIdentityIssuer<Probe.Source, Base>().authored(left: map, right: map,
            limits: limits, using: &a)
    }

    static func limits(_ raw: Probe.Raw, standard: OriginalDomainIdentityLimits) throws {
        try PolylineLiftProof.require(raw.first.source.sourceDepth > 0 && raw.first.templateCount == 4)
        for kind in 0..<4 {
            let limited = try OriginalDomainIdentityLimits(
                source: .init(remainingSourceDepth: kind == 0 ? 0 : standard.source.remainingSourceDepth),
                maximumTransportDepth: kind == 1 ? 0 : standard.maximumTransportDepth,
                maximumCharts: kind == 2 ? 3 : standard.maximumCharts,
                maximumFamilies: standard.maximumFamilies,
                maximumIdentityProofs: kind == 3 ? 0 : standard.maximumIdentityProofs)
            var a = try Admission(work: 80_000_000)
            do { _ = try query(raw, limits: limited, using: &a); throw Failure(line: #line) }
            catch NativeExactRelationFailure.domain(let cause) {
                switch (kind, cause) {
                case (0, .sourceDepthLimit), (1, .transportDepthLimit), (2, .chartLimit), (3, .identityLimit): break
                default: throw cause
                }
            }
        }
        marker("PASS source/transport depth, finite chart count and identity proof count typed refusal")
    }

    static func identities(_ raw: Probe.Raw, limits: OriginalDomainIdentityLimits) throws {
        var preparation = try Admission()
        let field = raw.first.graphs[0].original.graph.field
        let foreignSource = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(raw.first.source.original.original, limits: limits.source, using: &preparation)
        let anchor = try raw.first.source.chart(0, limits: limits.source, using: &preparation)
        try PolylineLiftProof.require(!foreignSource.owns(anchor))
        for isEmpty in [false, true] {
            let foreign = try identity(source: foreignSource, field: field, empty: isEmpty, limits: limits, using: &preparation)
            var a = try Admission(work: 80_000_000)
            do { _ = try query(raw, excluding: [foreign], limits: limits, using: &a); throw Failure(line: #line) }
            catch NativeExactRelationFailure.domain(.foreignOwner) { }
        }
        let foreignField = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let wrongField = try identity(source: raw.first.source, field: foreignField, limits: limits, using: &preparation)
        var fieldAdmission = try Admission(work: 80_000_000)
        try expectForeignField { _ = try query(raw, excluding: [wrongField], limits: limits, using: &fieldAdmission) }
        let wrongRole = try identity(source: raw.first.source, field: field,
            semantics: [.physicalRadian, .authoredScalar], limits: limits, using: &preparation)
        var roleAdmission = try Admission(work: 80_000_000)
        do { _ = try query(raw, excluding: [wrongRole], limits: limits, using: &roleAdmission); throw Failure(line: #line) }
        catch NativeExactRelationFailure.domain(.incompatibleCoordinateSemantics) { }
        marker("PASS equal-valued foreign-owner identity including empty scope, foreign field and semantic role refusal")
    }

    static func membership(_ result: Result, limits: OriginalDomainIdentityLimits) throws {
        try empty(result)
        let field = result.raw.first.field
        var preparation = try Admission()
        let quarter = try field.binary64(exactly: 0.25, using: &preparation)
        let tuple = [quarter, quarter, quarter, quarter]
        var measured = try Admission(work: 80_000_000)
        try PolylineLiftProof.require(!contains(result, tuple: tuple, limits: limits, using: &measured))
        let work = measured.ledger.work, bytes = measured.ledger.storageBytes
        var independent = try Admission(work: 80_000_000)
        try PolylineLiftProof.require(!contains(result, tuple: tuple, limits: limits, using: &independent))
        try PolylineLiftProof.require(independent.ledger.work == work && independent.ledger.storageBytes == bytes)
        try PolylineLiftProof.require(measured.ledger.work == work && measured.ledger.storageBytes == bytes)
        for resource in [ExactResource.work, .storage] {
            var exact = try Admission(work: resource == .work ? work : 80_000_000,
                bytes: resource == .storage ? bytes : 1_073_741_824)
            try PolylineLiftProof.require(!contains(result, tuple: tuple, limits: limits, using: &exact))
            var short = try Admission(work: resource == .work ? work - 1 : 80_000_000,
                bytes: resource == .storage ? bytes - 1 : 1_073_741_824)
            try expectResource(resource) { _ = try contains(result, tuple: tuple, limits: limits, using: &short) }
        }
        for tick in [1, max(2, measured.checkpoints / 2), measured.checkpoints] {
            var cancelled = try Admission(work: 80_000_000, cancelAt: tick)
            try expectCancel { _ = try contains(result, tuple: tuple, limits: limits, using: &cancelled) }
            try PolylineLiftProof.require(cancelled.checkpoints == tick)
        }
        for pair in [-1, result.raw.pairs.count] {
            var a = try Admission()
            do { _ = try contains(result, pair: pair, tuple: tuple, limits: limits, using: &a); throw Failure(line: #line) }
            catch NativeExactRelationFailure.invalidDomain { }
        }
        for invalidTuple in [[], [quarter], tuple + [quarter]] {
            var a = try Admission()
            do { _ = try contains(result, tuple: invalidTuple, limits: limits, using: &a); throw Failure(line: #line) }
            catch NativeExactRelationFailure.cell(.invalidVariable) { }
        }
        let foreignBase = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let foreignField = try Field.base(field: foreignBase, maximumExtensionLevel: 32, using: &preparation)
        var foreign = try Admission()
        try expectForeignField { _ = try contains(result, tuple: tuple, queryField: foreignField, limits: limits, using: &foreign) }
        marker("PASS residual membership independent admissions, exact/one-less budgets, cancel, invalid pair/dimension and foreign query field")
    }

    static func detached(limits: OriginalDomainIdentityLimits) throws -> Result {
        var preparation = try Admission(work: 80_000_000)
        let raw = try Probe.raw(using: &preparation)
        let field = raw.first.graphs[0].original.graph.field
        var supplied = [try identity(source: raw.first.source, field: field, limits: limits, using: &preparation)]
        var queryAdmission = try Admission(work: 80_000_000)
        let result = try query(raw, excluding: supplied, limits: limits, using: &queryAdmission)
        supplied.removeAll()
        var graphs = raw.first.graphs, pairs = raw.pairs
        graphs.removeLast(); pairs.removeLast()
        try PolylineLiftProof.require(graphs.count == 3 && raw.first.graphs.count == 4)
        try PolylineLiftProof.require(pairs.count == 15 && raw.pairs.count == 16 && result.identities.count == 1)
        return result
    }

    static func lifetime(limits: OriginalDomainIdentityLimits) throws {
        let result = try detached(limits: limits)
        try empty(result)
        var refinements = result.refinements, diagonals = result.authoredDiagonals, identities = result.identities
        refinements.removeAll(); diagonals.removeAll(); identities.removeAll()
        try PolylineLiftProof.require(refinements.isEmpty && diagonals.isEmpty && identities.isEmpty)
        try PolylineLiftProof.require(result.refinements.count == 16 && result.authoredDiagonals.count == 16 && result.identities.count == 1)
        let snapshot = result.raw.first.source.original
        try PolylineLiftProof.require(snapshot.originalCellCount == 4)
        var sourceAdmission = try Admission()
        let bound = snapshot.originalCellLowerBound(at: 0, axis: 0)
        _ = try snapshot.originalField.sign(of: bound, using: &sourceAdmission)
        var identityAdmission = try Admission()
        let view = try DefaultOriginalParameterIdentityIssuer<Probe.Source, Base>()
            .relation(of: result.identities[0], limits: limits, using: &identityAdmission)
        try PolylineLiftProof.require(!view.left.isEmpty && !view.right.isEmpty)
        try membership(result, limits: limits)
        marker("PASS detached source/field/raw/identity/result owners, COW arrays and independent retained result readers")
    }

    static func main() throws {
        let selected = group(), standard = try PolylineLiftProof.limits()
        let groups = ["query-work", "query-storage", "query-cancel", "limits", "identities", "membership", "lifetime"]
        try PolylineLiftProof.require(groups.contains(selected))
        if selected == "lifetime" { try lifetime(limits: standard); return }
        var preparation = try Admission(work: 80_000_000)
        let raw = try Probe.raw(using: &preparation)
        try PolylineLiftProof.require(raw.pairs.count == 16)
        if selected == "query-work" { try resources(raw, resource: .work, limits: standard) }
        if selected == "query-storage" { try resources(raw, resource: .storage, limits: standard) }
        if selected == "query-cancel" { try cancellation(raw, limits: standard) }
        if selected == "limits" { try limits(raw, standard: standard) }
        if selected == "identities" { try identities(raw, limits: standard) }
        if selected == "membership" {
            var admission = try Admission(work: 80_000_000)
            let result = try query(raw, limits: standard, using: &admission)
            try membership(result, limits: standard)
        }
        // The lifetime group prepares its only raw inside detached(), after which
        // all producer locals have left scope before the retained result is read.
    }
}
