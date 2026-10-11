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

/// Consumes original graph laws and checked M5 views without repeating equality solving.
public struct DefaultOriginalIssuedGraphSelfContactQuery<S: Sendable,E: Sendable,C: OriginalIssuedGraphSelfContactRequestReading,F: Sendable,D: OriginalIssuedGraphSelfContactRequestReading>: OriginalIssuedGraphSelfContactQuerying where C.Source == S, D.Source == S {
    public typealias Source = S
    public typealias FirstEvidence = E
    public typealias FirstCover = C
    public typealias SecondEvidence = F
    public typealias SecondCover = D
    public init() {}
    public func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: OriginalIssuedGraphRelations<S,E,C,S,F,D>,
        excluding identities: [OriginalParameterIdentity<S,OriginalExactScalarDomain>] = [],
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphSelfContacts<S,E,C,F,D> {
        do {
            try a.checkpoint(); try raw.admitProof(limits: domainLimits, using: &a)
            guard raw.kind == .surfaceSurface, raw.first.parameterCount == 2, raw.second.parameterCount == 2 else {
                throw NativeExactRelationFailure.invalidDomain
            }
            let anchor = try raw.first.source.chart(0, limits: domainLimits.source, using: &a)
            guard raw.second.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let reference = raw.first.graphs.first?.original.request ?? raw.second.graphs.first?.original.request
                ?? raw.first.coverage.selfContactRequest
            func validate(_ scope: OriginalParameterSelection<S,OriginalExactScalarDomain>) throws {
                guard scope.arity == 2, scope.frame.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
                guard scope.frame.coordinateSemantics.elementsEqual(reference.frame.coordinateSemantics) else {
                    throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics
                }
                _ = try reference.frame.scalarField.sign(of: scope.frame.scalarField.integer(0, using: &a), using: &a)
            }
            if raw.first.graphs.isEmpty { try validate(raw.first.coverage.selfContactRequest) }
            if raw.second.graphs.isEmpty { try validate(raw.second.coverage.selfContactRequest) }
            for graph in raw.first.graphs { try a.consumeWork(1); try validate(graph.original.request) }
            for graph in raw.second.graphs { try a.consumeWork(1); try validate(graph.original.request) }
            let issuer = DefaultOriginalParameterIdentityIssuer<S,OriginalExactScalarDomain>()
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: identities.count,
                of: OriginalParameterIdentityRelation<S,OriginalExactScalarDomain>.self))
            var views: [OriginalParameterIdentityRelation<S,OriginalExactScalarDomain>] = []
            views.reserveCapacity(identities.count)
            for identity in identities {
                try a.consumeWork(1)
                let view = try issuer.relation(of: identity, limits: domainLimits, using: &a)
                try validate(view.left); try validate(view.right)
                views.append(view)
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: raw.pairs.count,
                of: OriginalParameterIdentity<S,OriginalExactScalarDomain>.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: raw.pairs.count,
                of: OriginalIssuedGraphParameterRefinement<S,E,C,S,F,D>.self))
            var diagonals: [OriginalParameterIdentity<S,OriginalExactScalarDomain>] = []
            var refinements: [OriginalIssuedGraphParameterRefinement<S,E,C,S,F,D>] = []
            diagonals.reserveCapacity(raw.pairs.count); refinements.reserveCapacity(raw.pairs.count)
            let transporter = DefaultOriginalParameterTransporter<S,OriginalExactScalarDomain>()
            for ordinal in raw.pairs.indices {
                try a.consumeWork(1)
                let pair = raw.pairs[ordinal]
                guard raw.first.graphs.indices.contains(pair.firstGraphIndex),
                    raw.second.graphs.indices.contains(pair.secondGraphIndex) else { throw NativeExactRelationFailure.invalidDomain }
                let first = raw.first.graphs[pair.firstGraphIndex], second = raw.second.graphs[pair.secondGraphIndex]
                let lhs = first.original.request, rhs = second.original.request, field = lhs.frame.scalarField
                let zero = try field.integer(0, using: &a), one = try field.integer(1, using: &a)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Int.self))
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: OriginalExactScalar.self))
                let left = try transporter.affine(from: lhs, to: rhs.frame, permutation: [0,1],
                    gains: [one,one], offsets: [zero,zero], limits: domainLimits, using: &a)
                let right = try transporter.affine(from: rhs, to: rhs.frame, permutation: [0,1],
                    gains: [one,one], offsets: [zero,zero], limits: domainLimits, using: &a)
                let diagonal = try issuer.authored(left: left, right: right, limits: domainLimits, using: &a)
                let view = try issuer.relation(of: diagonal, limits: domainLimits, using: &a)
                var compiler = try OriginalIssuedGraphSelfIdentityCompiler(pair.relation.projection.original, using: &a)
                let predicate = try compiler.residual(first: first, second: second,
                    firstPlacement: pair.relation.original.firstCoordinates, secondPlacement: pair.relation.original.secondCoordinates,
                    diagonal: view, identities: views, using: &a)
                let refined = try DefaultOriginalIssuedGraphParameterRefiner().refine(in: raw, pairOrdinal: ordinal,
                    matching: predicate, limits: domainLimits, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
                diagonals.append(diagonal); refinements.append(refined)
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedGraphSelfContacts<S,E,C,F,D>.self))
            let result = OriginalIssuedGraphSelfContacts(raw: raw, authoredDiagonals: diagonals,
                identities: identities, refinements: refinements)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
