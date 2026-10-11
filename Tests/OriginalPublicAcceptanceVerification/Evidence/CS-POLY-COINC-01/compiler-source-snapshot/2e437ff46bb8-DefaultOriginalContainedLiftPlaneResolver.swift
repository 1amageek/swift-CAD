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
/// Complete affine-guard preimages for a source-proved contained polynomial lift.
struct DefaultOriginalContainedLiftPlaneResolver {
    typealias Base = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Base>
    private final class Owner<S: OriginalLiftGraphSourceReading, P: OriginalPlaneSourceReading>: Sendable {
        let lift: OriginalRetainedSurfaceLiftDomainCover<S>
        let plane: OriginalIssuedPlaneGraph<P>
        let reductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>]
        init(lift: OriginalRetainedSurfaceLiftDomainCover<S>, plane: OriginalIssuedPlaneGraph<P>,
            reductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>]) {
            self.lift = lift; self.plane = plane; self.reductions = reductions
        }
    }
    func resolve<S: OriginalLiftGraphSourceReading, P: OriginalPlaneSourceReading, A: ExactScalarAdmission & ~Copyable>(
        lift: OriginalRetainedSurfaceLiftDomainCover<S>, plane: OriginalIssuedPlaneGraph<P>, maximumPieces: Int,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalContainedLiftPlaneFamily? {
        try a.checkpoint(); try lift.family.admitProof(limits: limits.source, using: &a); try plane.admitProof(limits: limits, using: &a)
        let count = lift.templateCount
        guard count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        let basis = plane.original.law, f = lift.family.field
        // Prove applicability over every original chart before preparing or solving relations.
        for g in lift.family.graphs {
            try a.consumeWork(1)
            let ring = g.polynomials
            var equation = try ring.constant(f.integer(0, using: &a), using: &a)
            for axis in 0..<3 {
                let offset = try ring.constant(basis.origin[axis], using: &a)
                let difference = try ring.subtracting(g.homogeneous[axis], ring.multiplying(offset, g.homogeneous[3], using: &a), using: &a)
                equation = try ring.adding(equation, ring.multiplying(ring.constant(basis.normal[axis], using: &a), difference, using: &a), using: &a)
            }
            if try !ring.isZero(equation, using: &a) { return nil }
            for term in g.homogeneous[3].terms {
                try a.consumeWork(1); if term.powers.contains(where: { $0 != 0 }) { return nil }
            }
            if try ring.isZero(g.homogeneous[3], using: &a) { return nil }
            for condition in g.conditions {
                for term in condition.polynomial.terms {
                    try a.consumeWork(1)
                    var total = 0
                    for power in term.powers {
                        let next = total.addingReportingOverflow(power)
                        guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                        total = next.partialValue
                    }
                    if total > 1 { return nil }
                }
            }
        }
        guard count <= maximumPieces else { throw ExactScalarFailure.resourceLimit(.work) }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: OriginalPolynomialSurfaceLiftGraphReduction<S>.self))
        var reductions: [OriginalPolynomialSurfaceLiftGraphReduction<S>] = []; reductions.reserveCapacity(count)
        for template in 0..<count {
            let member = try lift.member(template: template, limits: limits, using: &a)
            reductions.append(try DefaultOriginalPolynomialSurfaceLiftGraphReducer<S>().reduce(member.graph, limits: limits.source, using: &a))
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: (OriginalRetainedSurfaceLiftDomainCover<S>, OriginalIssuedPlaneGraph<P>, [OriginalPolynomialSurfaceLiftGraphReduction<S>]).self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self))
        let owner: any Sendable = Owner(lift: lift, plane: plane, reductions: reductions)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: OriginalContainedLiftPlanePiece.self))
        var pieces: [OriginalContainedLiftPlanePiece] = []; pieces.reserveCapacity(count)
        var empty = true, positive = false, imagePositive = false
        for template in 0..<count {
            try a.consumeWork(1)
            let reduction = reductions[template], g = reduction.graph, ring = g.polynomials
            let t = try ring.variable(0, using: &a)
            let numerator = try ring.importing(g.parameterTransport.numerators[0], using: &a)
            let denominator = try ring.importing(g.parameterTransport.denominators[0], using: &a)
            guard try ring.equals(numerator, ring.multiplying(denominator, t, using: &a), using: &a),
                try !ring.isZero(denominator, using: &a) else { throw NativeExactRelationFailure.invalidDomain }
            for term in denominator.terms {
                guard term.powers.allSatisfy({ $0 == 0 }) else { throw NativeExactRelationFailure.invalidDomain }
            }
            let domain = try ExactParameterDomain(field: f, depth: g.proofDepth, using: &a)
            let support = try domain.interval(lower: .finite(g.support[0].lower), upper: .finite(g.support[0].upper),
                includesLower: true, includesUpper: g.includesUpperBoundary[0], using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
            var selected = try domain.set(intervals: [support], using: &a)
            for condition in g.conditions {
                let allowed = try preimage(condition, ring: ring, domain: domain, using: &a)
                selected = try domain.intersection(selected, allowed, using: &a)
            }
            let binding = try DefaultOriginalParametricGraphDomainBinder().bind(graph: g, request: lift.request, limits: limits, using: &a)
            let prepared = try DefaultOriginalIssuedGraphCompiler<S, OriginalSurfaceLiftGraphEvidence<S>>()
                .compile(binding: binding, field: plane.field, limits: limits, using: &a)
            let map = try DefaultExactPolynomialCurveMapCertifier<Base>().certify(prepared.graph, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Polynomial.self))
            var planeUV: [Polynomial] = []; planeUV.reserveCapacity(2)
            for coordinate in 0..<2 {
                let direction = coordinate == 0 ? basis.u : basis.v
                var law = try ring.constant(f.integer(0, using: &a), using: &a)
                for axis in 0..<3 {
                    let difference = try ring.subtracting(g.homogeneous[axis], ring.multiplying(ring.constant(basis.origin[axis], using: &a), g.homogeneous[3], using: &a), using: &a)
                    law = try ring.adding(law, ring.multiplying(ring.constant(direction[axis], using: &a), difference, using: &a), using: &a)
                }
                planeUV.append(law)
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: selected.intervalCount, of: Int.self))
            var dimensions: [Int] = []; dimensions.reserveCapacity(selected.intervalCount)
            for interval in selected.intervals {
                guard case .finite(let lower) = interval.lower, case .finite(let upper) = interval.upper else { throw NativeExactRelationFailure.invalidDomain }
                let dimension = try f.compare(lower, upper, using: &a) == .equal ? 0 : 1
                dimensions.append(dimension); empty = false
                if dimension > 0 { positive = true; if !map.isConstant { imagePositive = true } }
            }
            let depth = try ExactScalarDepth(value:max(g.proofDepth.value,plane.depth.value,map.depth.value,selected.depth.value),
                coefficient:max(g.proofDepth.coefficient,plane.depth.coefficient,map.depth.coefficient,selected.depth.coefficient))
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            pieces.append(.init(templateOrdinal: template, domain: selected, polynomials: ring,
                originalCoordinates: reduction.originalCoordinates, homogeneous: g.homogeneous,
                planeNumerators: planeUV, mapEvidence: map, intervalDimensions: dimensions, depth: depth, owner: owner))
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalContainedLiftPlaneFamily.self))
        let result = OriginalContainedLiftPlaneFamily(pieces: pieces, isEmpty: empty,
            hasPositiveDimensionalSolutions: positive, hasPositiveDimensionalImage: imagePositive)
        try a.checkpoint(); return result
    }
    func preimage<A: ExactScalarAdmission & ~Copyable>(_ condition: OriginalParametricGraphCondition<Base>,
        ring: ExactPolynomialDomain<Base>, domain: ExactParameterDomain<Base>, using a: inout A) throws -> ExactParameterSet<Base> {
        let f = ring.field
        var constant = try f.integer(0, using: &a), gain = constant
        for term in condition.polynomial.terms {
            try a.consumeWork(1)
            guard term.powers.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
            if term.powers[0] == 0 { constant = try f.adding(constant, term.coefficient, using: &a) }
            else if term.powers[0] == 1 { gain = try f.adding(gain, term.coefficient, using: &a) }
            else { throw NativeExactRelationFailure.invalidDomain }
        }
        let slope = try f.sign(of: gain, using: &a)
        if slope == .zero {
            if try !condition.accepts(f.sign(of: constant, using: &a)) { return try domain.empty(using: &a) }
            let all = try domain.interval(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
            return try domain.set(intervals: [all], using: &a)
        }
        let root = try f.dividing(f.negated(constant, using: &a), gain, using: &a)
        let closed = condition.relation == .nonnegative || condition.relation == .equal
        let interval: ExactParameterInterval<OriginalExactScalar>
        switch condition.relation {
        case .equal:
            interval = try domain.interval(lower: .finite(root), upper: .finite(root), using: &a)
        case .notEqual:
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactParameterInterval<OriginalExactScalar>.self))
            return try domain.set(intervals: [domain.interval(lower: .negativeInfinity, upper: .finite(root), includesUpper: false, using: &a).retainingDepth(root.depth, using: &a),
                domain.interval(lower: .finite(root), upper: .positiveInfinity, includesLower: false, using: &a).retainingDepth(root.depth, using: &a)], using: &a)
        case .positive, .nonnegative:
            interval = slope == .positive
                ? try domain.interval(lower: .finite(root), upper: .positiveInfinity, includesLower: closed, using: &a)
                : try domain.interval(lower: .negativeInfinity, upper: .finite(root), includesUpper: closed, using: &a)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
        return try domain.set(intervals: [interval.retainingDepth(root.depth, using: &a)], using: &a)
    }
}
