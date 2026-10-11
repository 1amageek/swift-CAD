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

/// Compiles original forward UV into the retained lifted ring and refines only material.
public struct DefaultOriginalIssuedGraphBoundaryClipper<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: OriginalIssuedGraphBoundaryClipping {
    public typealias First = S
    public typealias FirstEvidence = E
    public typealias FirstCover = C
    public typealias Second = T
    public typealias SecondEvidence = F
    public typealias SecondCover = D
    public init() {}

    public func clip<A: ExactScalarAdmission & ~Copyable>(
        _ boundary: OriginalIssuedGraphBoundaryDomain<S, E, C, T, F, D>,
        selection: OriginalNativeBoundaryDomain.Selection, domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphClippedParameters<S, E, C, T, F, D> {
        do {
            try a.checkpoint()
            let raw = boundary.source.raw
            try raw.admitProof(limits: domainLimits, using: &a)
            typealias Refinement = OriginalIssuedGraphBoundaryRefinement<S, E, C, T, F, D>
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: raw.pairs.count, of: Refinement.self))
            var refinements: [Refinement] = []
            refinements.reserveCapacity(raw.pairs.count)
            for ordinal in raw.pairs.indices {
                try a.consumeWork(1)
                let pair = raw.pairs[ordinal], lifted = pair.relation.projection.original
                var compiler = try OriginalExactBoundaryCompiler<OriginalExactScalarDomain>(selection: lifted, using: &a)
                let uv: (numerators: [ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>],
                         denominator: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>)
                switch boundary.source.side {
                case .first:
                    guard raw.first.graphs.indices.contains(pair.firstGraphIndex) else { throw NativeExactRelationFailure.invalidDomain }
                    uv = try coordinates(raw.first.graphs[pair.firstGraphIndex], placement: pair.relation.original.firstCoordinates,
                        compiler: compiler, using: &a)
                case .second:
                    guard raw.second.graphs.indices.contains(pair.secondGraphIndex) else { throw NativeExactRelationFailure.invalidDomain }
                    uv = try coordinates(raw.second.graphs[pair.secondGraphIndex], placement: pair.relation.original.secondCoordinates,
                        compiler: compiler, using: &a)
                }
                let root = try compiler.boundary(preparedLoops: boundary.preparedLoops, numerators: uv.numerators,
                    denominator: uv.denominator, selection: selection, &a)
                let instructions = try compiler.instructions(root, &a)
                let source = try compiler.cells.bind(polynomials: compiler.laws, domains: lifted.predicate.source.domains, using: &a)
                let predicate = try compiler.cells.predicate(instructions: instructions, for: source, using: &a)
                let refined = try DefaultOriginalIssuedGraphParameterRefiner<S, E, C, T, F, D>().refine(
                    in: raw, pairOrdinal: ordinal, matching: predicate, limits: domainLimits,
                    cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
                let spans = try compiler.boundaryReferences(in: refined.pullback, using: &a)
                refinements.append(.init(parameters: refined, boundarySpans: spans))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedGraphClippedParameters<S, E, C, T, F, D>.self))
            let result = OriginalIssuedGraphClippedParameters(boundary: boundary, selection: selection, refinements: refinements)
            try a.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    private func coordinates<Source: Sendable, Evidence: Sendable, A: ExactScalarAdmission & ~Copyable>(
        _ preparation: OriginalIssuedGraphPreparation<Source, Evidence>, placement: [Int],
        compiler: OriginalExactBoundaryCompiler<OriginalExactScalarDomain>, using a: inout A
    ) throws -> (numerators: [ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>],
                 denominator: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>) {
        let original = preparation.original.graph, transport = original.parameterTransport
        guard preparation.graph.parameterCount == 2, transport.numerators.count == 2, transport.denominators.count == 2,
            placement.count == preparation.graph.variableCount else { throw NativeExactRelationFailure.invalidDomain }
        let ring = compiler.cells.polynomials, field = compiler.field
        func imported(_ polynomial: ExactPolynomial<OriginalExactScalarDomain>) throws -> ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>> {
            guard polynomial.variableCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            try a.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.termCount,
                of: ExactPolynomialTerm<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value>.self))
            var terms: [ExactPolynomialTerm<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>.Value>] = []
            terms.reserveCapacity(polynomial.termCount)
            for term in polynomial.terms {
                try a.consumeWork(1)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: ring.variableCount, of: Int.self))
                var powers = Array(repeating: 0, count: ring.variableCount)
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard placement[axis] >= 0, placement[axis] < powers.count else { throw NativeExactRelationFailure.invalidDomain }
                    powers[placement[axis]] = term.powers[axis]
                }
                terms.append(.init(powers: powers, coefficient: try field.importingBase(term.coefficient, using: &a)))
            }
            return try ring.polynomial(terms: terms, using: &a)
        }
        let u = try imported(transport.numerators[0]), v = try imported(transport.numerators[1])
        let du = try imported(transport.denominators[0]), dv = try imported(transport.denominators[1])
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomial<ExactAlgebraicScalarDomain<OriginalExactScalarDomain>>.self))
        return (try [ring.multiplying(u, dv, using: &a), ring.multiplying(v, du, using: &a)],
                try ring.multiplying(du, dv, using: &a))
    }
}
