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
import NativeDomainAdapters
#if S_COONS_SELF_RED
import protocol L0.ExactScalarAdmission
import struct L3.ExactRealCellLimits
import struct L4.ExactRealTopologyLimits
import struct DI.OriginalDomainIdentityLimits
#endif

/// Actual source/DI self product and independent whole-cell diagonal oracle.
@main struct CoonsGraphSelfContactProbe {
    typealias Base = OriginalExactScalarDomain
    typealias Source = OriginalCoonsAtlasSnapshot
    typealias Cover = OriginalIssuedDomainCover<Source, Int, Base>
    typealias Evidence = OriginalRationalChartReceipt<Source, Int, Base>
    typealias Raw = PublicLiftPlane.OriginalIssuedGraphRelations<Source, Evidence, Cover, Source, Evidence, Cover>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<Base>

    static func raw(using a: inout PolylineLiftProof.Admission) throws -> Raw {
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &a).0
        let field = try Base(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let limits = try PolylineLiftProof.limits()
        let source = try DefaultOriginalSourceBindingIssuer(
            provider: OriginalCoonsAtlasSnapshotProvider(field: field, tolerance: .standard))
            .bind(host, limits: limits.source, using: &a)
        let charts = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>()
            .prepare(source: source, maximumCharts: 4, limits: limits.source, using: &a)
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in charts.support {
            intervals.append([try .checked(field: field, lower: .finite(bound.lower), upper: .finite(bound.upper),
                depth: .zero, using: &a)])
        }
        let frame = try DefaultOriginalParameterTransporter<Source, Base>().frame(source: source, field: field,
            support: intervals, semantics: [.authoredScalar, .authoredScalar], limits: limits, using: &a)
        let cover = try DefaultOriginalIssuedDomainBinder().bind(laws: charts.laws,
            request: frame.fullSelection(limits: limits, using: &a), limits: limits, using: &a)
        let algebraic = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field: field, maximumExtensionLevel: 32, using: &a)
        let family = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: cover, field: algebraic,
            maximumGraphs: 4, limits: limits, using: &a)
        try PolylineLiftProof.require(family.graphs.count == 4)
        for graph in family.graphs {
            let original = graph.original.graph, ring = original.polynomials
            let zero = try ring.constant(field.integer(0, using: &a), using: &a)
            let one = try ring.constant(field.integer(1, using: &a), using: &a)
            let expected = [try ring.variable(0, using: &a), try ring.variable(1, using: &a), zero, one]
            try PolylineLiftProof.require(original.layout.variableCount == 2)
            for axis in expected.indices {
                try PolylineLiftProof.require(ring.equals(original.homogeneous[axis], expected[axis], using: &a))
            }
            for axis in 0..<2 {
                try PolylineLiftProof.require(ring.equals(original.parameterTransport.numerators[axis], expected[axis], using: &a))
                try PolylineLiftProof.require(ring.equals(original.parameterTransport.denominators[axis], one, using: &a))
            }
        }
        return try PublicLiftPlane.DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: family, second: family, maximumPairs: 16, limits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func oracle(_ raw: Raw, using a: inout PolylineLiftProof.Admission) throws {
        try PolylineLiftProof.require(raw.pairs.count == 16 && raw.first.source.owner === raw.second.source.owner)
        // Independently authored knot grid; validate the chart cover before using
        // its ordinals to test both inclusion and exclusion over every full cell.
        let base = raw.first.graphs[0].original.graph.field
        var rectangles: [[Double]] = []
        for graph in raw.first.graphs {
            let original = graph.original.graph
            var matched: [Double]?
            for v in [0.0, 0.5] {
                for u in [0.0, 0.5] {
                    let candidate = [u, u + 0.5, v, v + 0.5]
                    var equal = original.support.count == 2 && original.includesUpperBoundary == [true, true]
                    for axis in 0..<2 {
                        equal = try equal && base.compare(original.support[axis].lower,
                            base.binary64(exactly: candidate[2 * axis], using: &a), using: &a) == .equal
                        equal = try equal && base.compare(original.support[axis].upper,
                            base.binary64(exactly: candidate[2 * axis + 1], using: &a), using: &a) == .equal
                    }
                    if equal { matched = candidate }
                }
            }
            guard let matched, !rectangles.contains(matched) else { throw ExactScalarFailure.invalidEvidence }
            rectangles.append(matched)
        }
        var nonemptyPairs = 0
        for pair in raw.pairs {
            let selected = pair.relation.projection.original, partition = selected.partition
            try PolylineLiftProof.require(partition.source.variableCount == 4)
            try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0, 1])
            try PolylineLiftProof.require(pair.relation.original.secondCoordinates == [2, 3])
            let cells = try Cells(retaining: partition.source, using: &a), ring = cells.polynomials
            let u = try ring.subtracting(ring.variable(0, using: &a), ring.variable(2, using: &a), using: &a)
            let v = try ring.subtracting(ring.variable(1, using: &a), ring.variable(3, using: &a), using: &a)
            guard let us = try cells.signInvariant(for: u, in: partition, using: &a),
                let vs = try cells.signInvariant(for: v, in: partition, using: &a) else { throw ExactScalarFailure.invalidEvidence }
            let bounds = rectangles[pair.firstGraphIndex] + rectangles[pair.secondGraphIndex]
            var constraints: [ExactPolynomial<PublicLiftPlane.ExactAlgebraicScalarDomain<Base>>] = []
            for axis in 0..<4 {
                for endpoint in 0..<2 {
                    let value = try ring.field.importingBase(base.binary64(exactly: bounds[2 * axis + endpoint], using: &a), using: &a)
                    constraints.append(try ring.subtracting(ring.variable(axis, using: &a), ring.constant(value, using: &a), using: &a))
                }
            }
            let invariants = try constraints.map { polynomial in
                guard let invariant = try cells.signInvariant(for: polynomial, in: partition, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                return invariant
            }
            var count = 0
            for cell in partition.cells where cell.axis == 3 {
                let diagonal = try cells.sign(of: us, at: cell, using: &a) == .zero && cells.sign(of: vs, at: cell, using: &a) == .zero
                var inside = true
                for index in invariants.indices {
                    let sign = try cells.sign(of: invariants[index], at: cell, using: &a)
                    if index % 2 == 0 ? sign == .negative : sign == .positive { inside = false }
                }
                try PolylineLiftProof.require(selected.cells.contains(cell) == (diagonal && inside))
                if selected.cells.contains(cell) { count += 1 }
            }
            if count > 0 { nonemptyPairs += 1 }
        }
        try PolylineLiftProof.require(nonemptyPairs == 16)
        print("PASS S-COONS-PLANE-01 all 16 chart pairs equal the complete independent closed-domain diagonal oracle")
    }

#if S_COONS_SELF_RED
    // The rejected module has separately named lower verification modules.
    // Supply its own valid limits/admission so only the public raw type fails.
    static func rejected<A: L0.ExactScalarAdmission & ~Copyable>(_ raw: Raw,
        domainLimits: DI.OriginalDomainIdentityLimits, cellLimits: L3.ExactRealCellLimits,
        topologyLimits: L4.ExactRealTopologyLimits, using a: inout A) throws {
        _ = try NativeDomainAdapters.DefaultOriginalExactNativeSelfContactQuery().contacts(in: raw,
            domainLimits: domainLimits, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
    }
#endif
    static func main() throws {
        var a = try PolylineLiftProof.Admission(work: 80_000_000)
        let raw = try raw(using: &a)
        try oracle(raw, using: &a)
        print("PASS S-COONS-PLANE-01 original input; public self consumer signature remains blocked")
    }
}
