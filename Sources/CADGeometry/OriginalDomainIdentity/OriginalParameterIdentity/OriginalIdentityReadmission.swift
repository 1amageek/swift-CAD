#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Retains original decisions even when transported coefficients cancel.
final class OriginalIdentityReadmission<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    struct Scalar: Sendable {
        let field: F
        let value: F.Value
    }
    let scalars: [Scalar]
    let parents: [OriginalIdentityReadmission<F>]
    // Data-only retention; no existential method or runtime type lookup is used.
    let retained: [any Sendable]
    let depth: ExactScalarDepth?
    init(scalars: [Scalar], parents: [OriginalIdentityReadmission<F>], retained: [any Sendable], depth: ExactScalarDepth? = nil) {
        self.scalars = scalars; self.parents = parents; self.retained = retained
        self.depth = depth
    }
    func admit<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws {
        if let depth { try a.admitDepth(value:depth.value,coefficient:depth.coefficient) }
        for scalar in scalars {
            try a.consumeWork(1)
            _ = try scalar.field.sign(of: scalar.value, using: &a)
        }
        for parent in parents { try a.consumeWork(1); try parent.admit(using: &a) }
    }
    static func preserving<S: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ receipt: OriginalParameterIdentity<S,F>, using a: inout A
    ) throws -> OriginalIdentityReadmission<F> {
        var count = try OriginalDomainAccess.multiplied(receipt.gains.count,2)
        count = try OriginalDomainAccess.add(count,OriginalDomainAccess.multiplied(receipt.proof.periods.count,3))
        for fiber in receipt.proof.fibers { try a.consumeWork(1); count = try OriginalDomainAccess.add(count,OriginalDomainAccess.add(fiber.position.count,1)) }
        for pole in receipt.proof.poles { try a.consumeWork(1); count = try OriginalDomainAccess.add(count,OriginalDomainAccess.add(pole.position.count,1)) }
        try OriginalDomainAccess.storage(count,Scalar.self,&a)
        var scalars: [Scalar] = []; scalars.reserveCapacity(count)
        func append(_ value: F.Value,_ field: F,_ a: inout A) throws {
            try a.consumeWork(1); scalars.append(.init(field:field,value:value))
        }
        for i in receipt.gains.indices { try append(receipt.gains[i],receipt.right.frame.scalarField,&a); try append(receipt.offsets[i],receipt.right.frame.scalarField,&a) }
        for period in receipt.proof.periods { try append(period.period,period.field,&a); try append(period.lower,period.field,&a); try append(period.upper,period.field,&a) }
        for fiber in receipt.proof.fibers { try append(fiber.fixedValue,receipt.left.frame.scalarField,&a); for value in fiber.position { try append(value,receipt.left.frame.scalarField,&a) } }
        for pole in receipt.proof.poles { try append(pole.latitude,pole.field,&a); for value in pole.position { try append(value,pole.field,&a) } }
        let parentCount = receipt.proof.inherited == nil ? receipt.proof.parents.count : 1
        try OriginalDomainAccess.storage(parentCount,OriginalIdentityReadmission<F>.self,&a)
        var parents: [OriginalIdentityReadmission<F>] = []; parents.reserveCapacity(parentCount)
        if let inherited = receipt.proof.inherited {
            // Inherited owners already include every ancestor decision; share them.
            parents.append(inherited)
        } else {
            for parent in receipt.proof.parents { try a.consumeWork(1); parents.append(try preserving(parent,using:&a)) }
        }
        var valueDepth = receipt.evidenceDepth.value, coefficientDepth = receipt.evidenceDepth.coefficient
        for axis in receipt.left.axes { try a.consumeWork(1); valueDepth = max(valueDepth,axis.depth.value); coefficientDepth = max(coefficientDepth,axis.depth.coefficient) }
        for axis in receipt.right.axes { try a.consumeWork(1); valueDepth = max(valueDepth,axis.depth.value); coefficientDepth = max(coefficientDepth,axis.depth.coefficient) }
        try OriginalDomainAccess.owner(([Scalar],[OriginalIdentityReadmission<F>],[any Sendable],ExactScalarDepth?).self,&a)
        return .init(scalars:scalars,parents:parents,retained:[],depth:try .init(value:valueDepth,coefficient:coefficientDepth))
    }
}
