@testable import NativeDomainAdapters
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

/// Invocation-local polynomial compilation; all coordinates remain in retained original roles.
struct OriginalExactSelfIdentityCompiler {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Polynomial = ExactPolynomial<Field>
    let cells: ExactRealCellDomain<ExactRationalScalarDomain>
    let field: Field
    let raw: ExactParametricRelation<ExactRationalScalarDomain>
    private var laws: [Polynomial] = []
    private var instructions: [ExactRealCellInstruction] = []
    init<A: ExactScalarAdmission & ~Copyable>(_ raw: ExactParametricRelation<ExactRationalScalarDomain>,using a: inout A) throws {
        self.raw = raw
        cells = try .init(retaining:raw.original.predicate.source,using:&a)
        field = try cells.coefficientField(of:raw.original.predicate.source,using:&a)
        guard raw.original.predicate.source.variableCount == 4 else { throw NativeExactRelationFailure.invalidDomain }
    }
    private mutating func append<A: ExactScalarAdmission & ~Copyable>(_ instruction: ExactRealCellInstruction,_ a: inout A) throws {
        try a.consumeWork(1)
        guard !instructions.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealCellInstruction.self))
        instructions.append(instruction)
    }
    private mutating func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,_ relation: ExactRealCellSignRelation,_ a: inout A) throws {
        for index in laws.indices {
            try a.consumeWork(1)
            if try cells.polynomials.equals(law,laws[index],using:&a) { try append(.sign(polynomial:index,relation:relation),&a);return }
        }
        guard !laws.count.addingReportingOverflow(1).overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Polynomial.self))
        laws.append(law);try append(.sign(polynomial:laws.count-1,relation:relation),&a)
    }
    private mutating func scope<A: ExactScalarAdmission & ~Copyable>(_ scope: OriginalParameterSelection<BSplineSurface3D,Field>,
        coordinates: [Polynomial],_ a: inout A) throws {
        let ring = cells.polynomials
        try append(.literal(true),&a)
        for axis in 0..<2 {
            try a.consumeWork(1);try append(.literal(false),&a)
            for interval in scope.axes[axis].intervals {
                try append(.literal(true),&a)
                switch interval.lower {
                case .negativeInfinity:break
                case .positiveInfinity:throw NativeExactRelationFailure.invalidDomain
                case .finite(let value):
                    try atom(ring.subtracting(coordinates[axis],ring.constant(value,using:&a),using:&a),
                        interval.includesLower ? .greaterOrEqual:.greater,&a)
                    try append(.and,&a)
                }
                switch interval.upper {
                case .positiveInfinity:break
                case .negativeInfinity:throw NativeExactRelationFailure.invalidDomain
                case .finite(let value):
                    try atom(ring.subtracting(coordinates[axis],ring.constant(value,using:&a),using:&a),
                        interval.includesUpper ? .lessOrEqual:.less,&a)
                    try append(.and,&a)
                }
                try append(.or,&a)
            }
            try append(.and,&a)
        }
    }
    private func coordinates<A: ExactScalarAdmission & ~Copyable>(_ chart: OriginalDomainBoundRationalChart<BSplineSurface3D,Field>,
        offset: Int,limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> [Polynomial] {
        let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
        let forward = try transporter.inverse(chart.inverse,limits:limits,using:&a)
        let view = try transporter.affineCoordinates(of:forward,limits:limits,using:&a)
        guard view.local.arity == 2,view.image.arity == 2 else { throw NativeExactRelationFailure.invalidDomain }
        let ring = cells.polynomials
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
        var output: [Polynomial] = [];output.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            output.append(try ring.adding(ring.scaled(ring.variable(offset+view.permutation[axis],using:&a),
                by:view.gains[axis],using:&a),ring.constant(view.offsets[axis],using:&a),using:&a))
        }
        return output
    }
    mutating func residual<A: ExactScalarAdmission & ~Copyable>(
        piece: NativeExactParametricRelationPiece<BSplineSurface3D,BSplineSurface3D>,
        identities: [OriginalParameterIdentityRelation<BSplineSurface3D,Field>],
        limits: OriginalDomainIdentityLimits,using a: inout A
    ) throws -> ExactRealCellPredicate<ExactRationalScalarDomain> {
        let left = try coordinates(piece.first,offset:0,limits:limits,&a)
        let right = try coordinates(piece.second,offset:2,limits:limits,&a)
        let ring = cells.polynomials
        try append(.literal(false),&a)
        for identity in identities {
            try a.consumeWork(1)
            guard identity.left.frame.source.owns(piece.first.law.chart),
                identity.right.frame.source.owns(piece.second.law.chart) else { throw OriginalDomainIdentityFailure.foreignOwner }
            try scope(identity.left,coordinates:left,&a)
            try scope(identity.right,coordinates:right,&a)
            try append(.and,&a)
            switch identity.constraints {
            case .completeProduct:break
            case .affine(let permutation,let gains,let offsets):
                guard permutation.count == 2,gains.count == 2,offsets.count == 2 else { throw NativeExactRelationFailure.invalidDomain }
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    guard permutation[axis] >= 0,permutation[axis] < 2 else { throw NativeExactRelationFailure.invalidDomain }
                    let mapped = try ring.adding(ring.scaled(left[permutation[axis]],by:gains[axis],using:&a),ring.constant(offsets[axis],using:&a),using:&a)
                    try atom(ring.subtracting(right[axis],mapped,using:&a),.equal,&a)
                    try append(.and,&a)
                }
            }
            try append(.or,&a)
        }
        try append(.not,&a)
        let source = try cells.bind(polynomials:laws,domains:raw.original.predicate.source.domains,using:&a)
        return try cells.predicate(instructions:instructions,for:source,using:&a)
    }
}
