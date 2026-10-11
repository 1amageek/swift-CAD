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
import PublicCoonsBoundary
import CADTopology
import CADKernel

/// Independent whole-cell material oracle for the frozen three Coons policy cells.
struct CoonsHoleBoundaryAcceptance {
    typealias F = OriginalExactScalarDomain
    typealias Field = PublicLiftPlane.ExactAlgebraicScalarDomain<F>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<F>

    static func label(_ policy: OriginalNativeBoundaryDomain.Selection) -> StaticString {
        switch policy {
        case .closed: return "B-COONS-HOLE-CLOSED-01"
        case .strictInterior: return "B-COONS-HOLE-STRICT-01"
        case .boundary: return "B-COONS-HOLE-BOUNDARY-01"
        }
    }

    static func verifySpans(_ spans: [OriginalNativeBoundaryDomain.SpanReference],
        signs: [ExactSign], selected: Bool, boundary: Bool) throws {
        if selected && boundary {
            // The authored rectangles traverse bottom, right, top, then left.
            // At V=1/2, the four boundary values meet exactly one vertical span.
            let loop = signs[0] == .zero || signs[3] == .zero ? 0 : 1
            let curve = signs[0] == .zero || signs[1] == .zero ? 3 : 1
            guard spans.count == 1 else { throw ExactScalarFailure.invalidEvidence }
            let span = spans[0]
            guard span.loopOrdinal == loop && span.curveOrdinal == curve && span.segmentOrdinal == 0 else {
                throw ExactScalarFailure.invalidEvidence
            }
        } else {
            guard spans.isEmpty else { throw ExactScalarFailure.invalidEvidence }
        }
    }

    static func rejectWrongSpanOwner() throws {
        let wrong = OriginalNativeBoundaryDomain.SpanReference(loopOrdinal: 0, curveOrdinal: 0, segmentOrdinal: 0)
        var rejected = false
        do {
            try verifySpans([wrong], signs: [.positive, .zero, .negative, .negative], selected: true, boundary: true)
        } catch ExactScalarFailure.invalidEvidence {
            rejected = true
        }
        try PolylineLiftProof.require(rejected)
        print("PASS F1 rejects a valid-index span with the wrong boundary owner")
    }

    static func checkLaw<S: Sendable, E: Sendable>(_ graph: OriginalIssuedGraphPreparation<S, E>,
        isSurface: Bool, using a: inout PolylineLiftProof.Admission) throws {
        let source = graph.original.graph, ring = source.polynomials
        let zero = try ring.constant(source.field.integer(0, using: &a), using: &a)
        let one = try ring.constant(source.field.integer(1, using: &a), using: &a)
        let half = try ring.constant(source.field.binary64(exactly: 0.5, using: &a), using: &a)
        let expected = [try ring.variable(0, using: &a), isSurface ? try ring.variable(1, using: &a) : half, zero, one]
        try PolylineLiftProof.require(source.layout.variableCount == (isSurface ? 2 : 1))
        for axis in expected.indices {
            try PolylineLiftProof.require(ring.equals(source.homogeneous[axis], expected[axis], using: &a))
        }
        for axis in source.parameterTransport.numerators.indices {
            try PolylineLiftProof.require(ring.equals(source.parameterTransport.numerators[axis], ring.variable(axis, using: &a), using: &a))
            try PolylineLiftProof.require(ring.equals(source.parameterTransport.denominators[axis], one, using: &a))
        }
        for condition in source.conditions {
            for term in condition.polynomial.terms {
                for power in term.powers { try PolylineLiftProof.require(power == 0) }
            }
            let coordinates = Array(repeating: try source.field.integer(0, using: &a), count: source.layout.variableCount)
            let value = try ring.evaluated(condition.polynomial, at: coordinates, using: &a).value
            try PolylineLiftProof.require(condition.accepts(source.field.sign(of: value, using: &a)))
        }
    }

    static func verify<S: Sendable, E: Sendable, C: Sendable, T: Sendable, G: Sendable, D: Sendable>(
        _ result: OriginalIssuedGraphFaceClippedParameters<S, E, C, T, G, D>,
        using a: inout PolylineLiftProof.Admission) throws {
        let raw = result.parameters.boundary.source.raw
        try PolylineLiftProof.require(result.parameters.refinements.count == raw.pairs.count && raw.pairs.count == 4)
        for refinement in result.parameters.refinements {
            let pullback = refinement.parameters.pullback, region = pullback.region
            let pair = raw.pairs[refinement.parameters.pairOrdinal]
            try PolylineLiftProof.require(pullback.coordinateMap == [0, 1, 2])
            try PolylineLiftProof.require(pair.relation.original.firstCoordinates == [0] && pair.relation.original.secondCoordinates == [1, 2])
            try PolylineLiftProof.require(region.coordinateCount == 3 && region.reductions.isEmpty && region.eliminations.isEmpty)
            let cells = try Cells(retaining: region.partition.source, using: &a), ring = cells.polynomials
            let field = try cells.coefficientField(of: region.partition.source, using: &a)
            let t = try ring.variable(0, using: &a), u = try ring.variable(1, using: &a), v = try ring.variable(2, using: &a)
            let bounds = [0.0, 0.25, 0.75, 1.0]
            var laws = try bounds.map { bound in
                try ring.subtracting(t, ring.constant(field.binary64(exactly: bound, using: &a), using: &a), using: &a)
            }
            laws.append(try ring.subtracting(t, u, using: &a))
            laws.append(try ring.subtracting(v, ring.constant(field.binary64(exactly: 0.5, using: &a), using: &a), using: &a))
            var invariants: [ExactRealCellSignInvariant<F>] = []
            for law in laws {
                guard let proof = try cells.signInvariant(for: law, in: region.partition, using: &a) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                invariants.append(proof)
            }
            var selected = 0, boundarySpans = 0
            for index in region.cells.indices {
                var signs: [ExactSign] = []
                for invariant in invariants { signs.append(try cells.sign(of: invariant, at: region.cells[index], using: &a)) }
                let incidence = signs[4] == .zero && signs[5] == .zero
                let within = signs[0] != .negative && signs[3] != .positive
                let outerMaterial = signs[1] != .positive || signs[2] != .negative
                let boundary = signs[0] == .zero || signs[1] == .zero || signs[2] == .zero || signs[3] == .zero
                let expected: Bool
                switch result.parameters.selection {
                case .closed: expected = incidence && within && outerMaterial
                case .strictInterior: expected = incidence && within && outerMaterial && !boundary
                case .boundary: expected = incidence && within && boundary
                }
                try PolylineLiftProof.require(region.included[index] == expected)
                let ordinal = pullback.sourceCellOrdinals[index]
                try PolylineLiftProof.require(expected ? pullback.source.cells.indices.contains(ordinal) : ordinal == -1)
                let spans = refinement.boundarySpans[index]
                try verifySpans(spans, signs: signs, selected: expected, boundary: boundary)
                boundarySpans += spans.count
                if expected { selected += 1 }
            }
            print("PASS whole-cell oracle")
#if !hasFeature(Embedded)
            print("Policy", result.parameters.selection, "pair", refinement.parameters.pairOrdinal,
                "cells", region.cells.count, "included", selected, "boundarySpans", boundarySpans)
#endif
        }
    }

    static func main() throws {
        try rejectWrongSpanOwner()
        var preparation = try PolylineLiftProof.Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &preparation).0
        let face = try CoonsHoleBoundaryProbe.face(host: host)
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let limits = try PolylineLiftProof.limits()
        let raw = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
        for graph in raw.first.graphs { try checkLaw(graph, isSurface: false, using: &preparation) }
        for graph in raw.second.graphs { try checkLaw(graph, isSurface: true, using: &preparation) }
        let binding = try OriginalFaceSurfaceBinding.coons(raw.second.source, limits: limits.source, using: &preparation)
        let source = try OriginalIssuedGraphBoundarySource.secondSurface(raw, binding: binding, limits: limits, using: &preparation)
        for policy in [OriginalNativeBoundaryDomain.Selection.closed, .strictInterior, .boundary] {
            var query = try PolylineLiftProof.Admission(work: 80_000_000)
            print(label(policy))
            let result = try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
                selection: policy, domainLimits: limits,
                cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
                topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                    maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
            try PolylineLiftProof.require(result.faceID == face.1 && result.loops.count == 2 &&
                result.parameters.boundary.source.raw.second.source.owner === raw.second.source.owner)
            var oracle = try PolylineLiftProof.Admission(work: 80_000_000)
            try verify(result, using: &oracle)
            print("PASS public Coons-hole policy")
#if !hasFeature(Embedded)
            print("Policy", policy, "queryWork", query.ledger.work, "queryBytes", query.ledger.storageBytes)
#endif
        }
    }
}
