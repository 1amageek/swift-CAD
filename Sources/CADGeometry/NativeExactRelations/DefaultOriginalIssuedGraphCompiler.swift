#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
@testable import SourceIssuer
#endif

/// Imports original laws once and pulls request membership through the forward map.
public struct DefaultOriginalIssuedGraphCompiler<S: Sendable,E: Sendable>: OriginalIssuedGraphCompiling {
    public typealias Source=S
    public typealias Evidence=E
    public typealias Base=OriginalExactScalarDomain
    public typealias Field=ExactAlgebraicScalarDomain<Base>
    typealias Polynomial=ExactPolynomial<Field>
    public init() {}
    public func compile<A: ExactScalarAdmission & ~Copyable>(binding: borrowing OriginalDomainBoundParametricGraph<S,Base,E>,
        field: borrowing Field, limits: OriginalDomainIdentityLimits, using admission:inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedGraphPreparation<S,E> {
        let binding=copy binding
        do {
            return try admission.withProofScope() { tracked in
                try compileTracked(binding: binding, field: copy field, limits: limits, using: &tracked)
            }
        } catch { throw .preserving(error) }
    }
    private func compileTracked<A: ExactScalarAdmission & ~Copyable>(binding: borrowing OriginalDomainBoundParametricGraph<S,Base,E>,
        field: borrowing Field, limits: OriginalDomainIdentityLimits, using admission:inout A)
        throws -> OriginalIssuedGraphPreparation<S,E> {
            try admission.checkpoint();try binding.admitProof(limits:limits,using:&admission)
            let original=binding.graph,n=original.layout.variableCount,p=original.layout.parameters.count
            _=try field.importingBase(original.field.integer(0,using:&admission),using:&admission)
            typealias Cells=ExactRealCellDomain<Base>
            let cells=try Cells(field:copy field,variableCount:n,using:&admission),ring=cells.polynomials
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Int.self))
            var placement=[Int](repeating:0,count:n)
            for i in 0..<p { try admission.consumeWork(1);placement[original.layout.parameters[i]]=i }
            for i in original.layout.auxiliaries.indices { try admission.consumeWork(1);placement[original.layout.auxiliaries[i]]=p+i }
            var laws:[Polynomial]=[],program:[ExactRealCellInstruction]=[]
            for law in original.homogeneous { try append(imported(law,placement:placement,into:ring,field:copy field,&admission),to:&laws,&admission) }
            try append(.literal(true),to:&program,&admission)
            for condition in original.conditions {
                try admission.consumeWork(1)
                let law=try imported(condition.polynomial,placement:placement,into:ring,field:copy field,&admission)
                let relation:ExactRealCellSignRelation
                switch condition.relation { case .equal:relation = .equal;case .notEqual:relation = .notEqual;case .positive:relation = .greater;case .nonnegative:relation = .greaterOrEqual }
                try atom(law,relation:relation,field:copy field,laws:&laws,program:&program,&admission)
                try append(.and,to:&program,&admission)
            }
            let roots=try ExactRealRootDomain(field:copy field,using:&admission)
            let line=try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:ExactRealRootInterval<Field.Value>.self))
            var domains=[ExactRealRootInterval<Field.Value>](repeating:line,count:n)
            for i in 0..<p {
                let support=original.support[i]
                domains[i]=try roots.domain(lower:.finite(field.importingBase(support.lower,using:&admission)),
                    upper:.finite(field.importingBase(support.upper,using:&admission)),includesLower:true,includesUpper:original.includesUpperBoundary[i],using:&admission)
            }
            // Parameter correspondence is a forward relation; no inverse or
            // positive-denominator assumption is needed for interval membership.
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:p,of:Int.self))
            let parameterPlacement=Array(0..<p)
            for axis in 0..<p {
                let numerator=try imported(original.parameterTransport.numerators[axis],placement:parameterPlacement,into:ring,field:copy field,&admission)
                let denominator=try imported(original.parameterTransport.denominators[axis],placement:parameterPlacement,into:ring,field:copy field,&admission)
                try atom(denominator,relation:.notEqual,field:copy field,laws:&laws,program:&program,&admission);try append(.and,to:&program,&admission)
                let intervals=binding.request.axes[axis].intervals
                // This identity is proved in the original coefficient field;
                // a single requested interval can then refine the solver domain.
                if intervals.count == 1,
                   try ring.equals(numerator, ring.multiplying(denominator, ring.variable(axis, using: &admission), using: &admission), using: &admission) {
                    if let restricted = try restricting(domains[axis], to: intervals[0], roots: roots, field: copy field, using: &admission) {
                        domains[axis] = restricted
                    } else {
                        try append(.literal(false), to: &program, &admission)
                        try append(.and, to: &program, &admission)
                    }
                    continue
                }
                if intervals.count != 1 { try append(.literal(false),to:&program,&admission) }
                for interval in intervals {
                    try admission.consumeWork(1);try append(.literal(true),to:&program,&admission)
                    if case .finite(let lower)=interval.lower {
                        let bound=try ring.constant(field.importingBase(lower,using:&admission),using:&admission)
                        let difference=try ring.subtracting(numerator,ring.multiplying(bound,denominator,using:&admission),using:&admission)
                        try atom(ring.multiplying(difference,denominator,using:&admission),relation:interval.includesLower ? .greaterOrEqual:.greater,field:copy field,laws:&laws,program:&program,&admission)
                        try append(.and,to:&program,&admission)
                    }
                    if case .finite(let upper)=interval.upper {
                        let bound=try ring.constant(field.importingBase(upper,using:&admission),using:&admission)
                        let difference=try ring.subtracting(ring.multiplying(bound,denominator,using:&admission),numerator,using:&admission)
                        try atom(ring.multiplying(difference,denominator,using:&admission),relation:interval.includesUpper ? .greaterOrEqual:.greater,field:copy field,laws:&laws,program:&program,&admission)
                        try append(.and,to:&program,&admission)
                    }
                    if intervals.count != 1 { try append(.or,to:&program,&admission) }
                }
                try append(.and,to:&program,&admission)
            }
            // Specialize only on the proved domain; keep every guard and parameter slot.
            var replacements:[Polynomial]=[]
            for axis in 0..<p {
                let selected=domains[axis]
                guard selected.includesLower,selected.includesUpper,
                    case .finite(let lower)=selected.lower,case .finite(let upper)=selected.upper,
                    try field.compare(lower,upper,using:&admission) == .equal else { continue }
                if replacements.isEmpty {
                    try admission.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Polynomial.self))
                    replacements.reserveCapacity(n)
                    for index in 0..<n {
                        try admission.consumeWork(1)
                        replacements.append(try ring.variable(index,using:&admission))
                    }
                }
                replacements[axis]=try ring.constant(lower,using:&admission)
            }
            if !replacements.isEmpty {
                for index in laws.indices {
                    try admission.consumeWork(1)
                    laws[index]=try ring.substituted(laws[index],with:replacements,using:&admission)
                }
            }
            let source=try cells.bind(polynomials:laws,domains:domains,using:&admission)
            let predicate=try cells.predicate(instructions:program,for:source,using:&admission)
            let domain=ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
            let graph=try domain.graph(from:predicate,parameterCount:p,using:&admission)
            let reached = try admission.depth
            let depth=try ExactScalarDepth(value:max(binding.depth.value,predicate.depth.value,reached.value),coefficient:max(binding.depth.coefficient,predicate.depth.coefficient,reached.coefficient))
            try admission.admitDepth(value:depth.value,coefficient:depth.coefficient)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedGraphPreparation<S,E>.self))
            let result=OriginalIssuedGraphPreparation(original:copy binding,graph:graph,field:copy field,depth:depth)
            try admission.checkpoint();return result
    }
    private func restricting<A:ExactScalarAdmission & ~Copyable>(_ support:ExactRealRootInterval<Field.Value>,
        to request:ExactParameterInterval<OriginalExactScalar>, roots:ExactRealRootDomain<Field>,field:Field,using a:inout A)
        throws -> ExactRealRootInterval<Field.Value>? {
        guard case .finite(var lower)=support.lower,case .finite(var upper)=support.upper else { throw NativeExactRelationFailure.invalidDomain }
        var includesLower=support.includesLower,includesUpper=support.includesUpper
        if case .finite(let bound)=request.lower {
            let value=try field.importingBase(bound,using:&a)
            switch try field.compare(value,lower,using:&a) {
            case .greater:lower=value;includesLower=request.includesLower
            case .equal:includesLower = includesLower && request.includesLower
            case .less:break
            }
        }
        if case .finite(let bound)=request.upper {
            let value=try field.importingBase(bound,using:&a)
            switch try field.compare(value,upper,using:&a) {
            case .less:upper=value;includesUpper=request.includesUpper
            case .equal:includesUpper = includesUpper && request.includesUpper
            case .greater:break
            }
        }
        let order=try field.compare(lower,upper,using:&a)
        guard !request.isEmpty,order != .greater,order != .equal || (includesLower && includesUpper) else { return nil }
        return try roots.domain(lower:.finite(lower),upper:.finite(upper),includesLower:includesLower,includesUpper:includesUpper,using:&a)
    }
    private func append<T,A:ExactScalarAdmission & ~Copyable>(_ value:T,to output:inout [T],_ a:inout A) throws {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:T.self));output.append(value)
    }
    private func atom<A:ExactScalarAdmission & ~Copyable>(_ law:Polynomial,relation:ExactRealCellSignRelation,field:Field,
        laws:inout [Polynomial],program:inout [ExactRealCellInstruction],_ a:inout A) throws {
        try a.consumeWork(law.variableCount)
        if law.termCount == 0 || (law.termCount == 1 && law.terms[0].powers.allSatisfy({ $0 == 0 })) {
            let sign:ExactSign
            if law.termCount == 0 { sign = .zero }
            else { sign = try field.sign(of:law.terms[0].coefficient,using:&a) }
            let accepted:Bool
            switch relation {
            case .equal:accepted = sign == .zero
            case .notEqual:accepted = sign != .zero
            case .greater:accepted = sign == .positive
            case .greaterOrEqual:accepted = sign != .negative
            case .less:accepted = sign == .negative
            case .lessOrEqual:accepted = sign != .positive
            }
            try append(.literal(accepted),to:&program,&a)
            return
        }
        let index=laws.count;try append(law,to:&laws,&a);try append(.sign(polynomial:index,relation:relation),to:&program,&a)
    }
    private func imported<A:ExactScalarAdmission & ~Copyable>(_ polynomial:ExactPolynomial<Base>,placement:[Int],
        into ring:ExactPolynomialDomain<Field>,field:Field,_ a:inout A) throws -> Polynomial {
        try a.admitDepth(value:polynomial.depth.value,coefficient:polynomial.depth.coefficient)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:polynomial.termCount,of:ExactPolynomialTerm<Field.Value>.self))
        var terms:[ExactPolynomialTerm<Field.Value>]=[];terms.reserveCapacity(polynomial.termCount)
        for term in polynomial.terms {
            try a.consumeWork(1)
            guard term.powers.count == placement.count else { throw NativeExactRelationFailure.invalidDomain }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:ring.variableCount,of:Int.self))
            var powers=[Int](repeating:0,count:ring.variableCount)
            for i in placement.indices { try a.consumeWork(1);powers[placement[i]]=term.powers[i] }
            terms.append(.init(powers:powers,coefficient:try field.importingBase(term.coefficient,using:&a)))
        }
        return try ring.polynomial(terms:terms,using:&a)
    }
}
