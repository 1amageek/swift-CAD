import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
import PublicCoonsBoundary
import CADTopology
import CADKernel

/// Independent whole-cell material oracle for the frozen three Coons policy cells.
@main struct CoonsHoleBoundaryAcceptance {
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
