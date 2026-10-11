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

/// Invocation-local forward UV compilation in the retained lifted polynomial ring.
struct OriginalIssuedGraphSelfIdentityCompiler {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    struct Coordinate { let numerator: Polynomial; let denominator: Polynomial }
    let cells: ExactRealCellDomain<Base>
    let field: Field
    private let selection: ExactRealCellSelection<Base>
    private var laws: [Polynomial] = []
    private var instructions: [ExactRealCellInstruction] = []
    init<A: ExactScalarAdmission & ~Copyable>(_ selection: ExactRealCellSelection<Base>, using a: inout A) throws {
        self.selection = selection
        cells = try .init(retaining: selection.predicate.source, using: &a)
        field = try cells.coefficientField(of: selection.predicate.source, using: &a)
    }
    private mutating func append<A: ExactScalarAdmission & ~Copyable>(_ instruction: ExactRealCellInstruction, _ a: inout A) throws {
        try a.consumeWork(1)
        guard !instructions.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactRealCellInstruction.self))
        instructions.append(instruction)
    }
    private mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, _ relation: ExactRealCellSignRelation, _ a: inout A) throws {
        for index in laws.indices {
            try a.consumeWork(1)
            if try cells.polynomials.equals(law, laws[index], using: &a) {
                try append(.sign(polynomial: index, relation: relation), &a); return
            }
        }
        guard !laws.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Polynomial.self))
        laws.append(law); try append(.sign(polynomial: laws.count - 1, relation: relation), &a)
    }
    private func coordinates<S: Sendable,E: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ preparation: OriginalIssuedGraphPreparation<S,E>, placement: [Int], using a: inout A
    ) throws -> [Coordinate] {
        let original = preparation.original.graph, transport = original.parameterTransport, ring = cells.polynomials
        guard original.layout.parameters.count == 2, preparation.graph.parameterCount == 2,
            transport.numerators.count == 2, transport.denominators.count == 2,
            placement.count == original.layout.variableCount, placement.count == preparation.graph.variableCount else {
            throw NativeExactRelationFailure.invalidDomain
        }
        for index in placement.indices {
            try a.consumeWork(1)
            guard placement[index] >= 0, placement[index] < ring.variableCount else { throw NativeExactRelationFailure.invalidDomain }
            for previous in 0..<index {
                try a.consumeWork(1)
                guard placement[previous] != placement[index] else { throw NativeExactRelationFailure.invalidDomain }
            }
        }
        func imported(_ polynomial: ExactPolynomial<Base>) throws -> Polynomial {
            guard polynomial.variableCount == placement.count else { throw NativeExactRelationFailure.invalidDomain }
            try a.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.termCount, of: ExactPolynomialTerm<Field.Value>.self))
            var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(polynomial.termCount)
            for term in polynomial.terms {
                try a.consumeWork(1)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: ring.variableCount, of: Int.self))
                var powers = Array(repeating: 0, count: ring.variableCount)
                for axis in placement.indices { try a.consumeWork(1); powers[placement[axis]] = term.powers[axis] }
                terms.append(.init(powers: powers, coefficient: try field.importingBase(term.coefficient, using: &a)))
            }
            return try ring.polynomial(terms: terms, using: &a)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Coordinate.self))
        var result: [Coordinate] = []; result.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            result.append(.init(numerator: try imported(transport.numerators[axis]),
                denominator: try imported(transport.denominators[axis])))
        }
        return result
    }
    private mutating func scope<S: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ scope: OriginalParameterSelection<S,Base>, coordinates: [Coordinate], using a: inout A
    ) throws {
        let ring = cells.polynomials
        try append(.literal(true), &a)
        for axis in 0..<2 {
            try a.consumeWork(1)
            let coordinate = coordinates[axis]
            try atom(coordinate.denominator, .notEqual, &a); try append(.and, &a)
            try append(.literal(false), &a)
            for interval in scope.axes[axis].intervals {
                try a.consumeWork(1); try append(.literal(true), &a)
                func signed(_ value: Base.Value) throws -> Polynomial {
                    let bound = try field.importingBase(value, using: &a)
                    return try ring.multiplying(ring.subtracting(coordinate.numerator,
                        ring.scaled(coordinate.denominator, by: bound, using: &a), using: &a), coordinate.denominator, using: &a)
                }
                switch interval.lower {
                case .negativeInfinity: break
                case .positiveInfinity: throw NativeExactRelationFailure.invalidDomain
                case .finite(let value):
                    try atom(signed(value), interval.includesLower ? .greaterOrEqual : .greater, &a)
                    try append(.and, &a)
                }
                switch interval.upper {
                case .positiveInfinity: break
                case .negativeInfinity: throw NativeExactRelationFailure.invalidDomain
                case .finite(let value):
                    try atom(signed(value), interval.includesUpper ? .lessOrEqual : .less, &a)
                    try append(.and, &a)
                }
                try append(.or, &a)
            }
            try append(.and, &a)
        }
    }
    mutating func residual<S: Sendable,E: Sendable,F: Sendable,A: ExactScalarAdmission & ~Copyable>(
        first: OriginalIssuedGraphPreparation<S,E>, second: OriginalIssuedGraphPreparation<S,F>,
        firstPlacement: [Int], secondPlacement: [Int], diagonal: OriginalParameterIdentityRelation<S,Base>,
        identities: [OriginalParameterIdentityRelation<S,Base>], using a: inout A
    ) throws -> ExactRealCellPredicate<Base> {
        let left = try coordinates(first, placement: firstPlacement, using: &a)
        let right = try coordinates(second, placement: secondPlacement, using: &a), ring = cells.polynomials
        let total = identities.count.addingReportingOverflow(1)
        guard !total.overflow else { throw ExactScalarFailure.countOverflow }
        try append(.literal(false), &a)
        for ordinal in 0..<total.partialValue {
            try a.consumeWork(1)
            let identity = ordinal == 0 ? diagonal : identities[ordinal - 1]
            try scope(identity.left, coordinates: left, using: &a)
            try scope(identity.right, coordinates: right, using: &a); try append(.and, &a)
            switch identity.constraints {
            case .completeProduct: break
            case .affine(let permutation, let gains, let offsets):
                guard permutation.count == 2, gains.count == 2, offsets.count == 2 else { throw NativeExactRelationFailure.invalidDomain }
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard permutation[axis] >= 0, permutation[axis] < 2 else { throw NativeExactRelationFailure.invalidDomain }
                    let l = left[permutation[axis]], r = right[axis]
                    let gain = try field.importingBase(gains[axis], using: &a), offset = try field.importingBase(offsets[axis], using: &a)
                    let numerator = try ring.adding(ring.scaled(l.numerator, by: gain, using: &a),
                        ring.scaled(l.denominator, by: offset, using: &a), using: &a)
                    try atom(ring.subtracting(ring.multiplying(r.numerator, l.denominator, using: &a),
                        ring.multiplying(numerator, r.denominator, using: &a), using: &a), .equal, &a)
                    try append(.and, &a)
                }
            }
            try append(.or, &a)
        }
        try append(.not, &a)
        let source = try cells.bind(polynomials: laws, domains: selection.predicate.source.domains, using: &a)
        return try cells.predicate(instructions: instructions, for: source, using: &a)
    }
}
