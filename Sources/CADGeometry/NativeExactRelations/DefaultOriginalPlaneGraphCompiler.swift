#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Compiles the proved original basis over its exact selected, possibly unbounded UV domain.
public struct DefaultOriginalPlaneGraphCompiler<S: OriginalPlaneSourceReading>: OriginalPlaneGraphCompiling {
    public typealias Source = S
    public typealias Base = OriginalExactScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    public init() {}
    public func compile<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalIssuedPlaneGraph<S>.Cover,
        field: borrowing Field, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(NativeExactRelationFailure) -> OriginalIssuedPlaneGraph<S> {
        let original = copy cover, field = copy field
        do {
            return try admission.withProofScope() { a in
                try a.checkpoint(); try original.source.require(limits.source)
                guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
                guard original.effective.arity == 2 else { throw NativeExactRelationFailure.invalidDomain }
                let basis = original.law, f = original.request.frame.scalarField
                guard original.source.owns(try basis.source.chart(0,limits:limits.source,using:&a)) else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                _ = try field.importingBase(f.integer(0,using:&a),using:&a)
                for axis in original.effective.axes { try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient) }
                typealias Cells = ExactRealCellDomain<Base>
                let cells = try Cells(field:field,variableCount:2,using:&a), ring = cells.polynomials
                let x = try ring.variable(0,using:&a), y = try ring.variable(1,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                var laws: [Polynomial] = []; laws.reserveCapacity(4)
                for i in 0..<3 {
                    try a.consumeWork(1)
                    let o = try ring.constant(field.importingBase(basis.origin[i],using:&a),using:&a)
                    let u = try ring.constant(field.importingBase(basis.u[i],using:&a),using:&a)
                    let v = try ring.constant(field.importingBase(basis.v[i],using:&a),using:&a)
                    laws.append(try ring.adding(o,ring.adding(ring.multiplying(u,x,using:&a),ring.multiplying(v,y,using:&a),using:&a),using:&a))
                }
                laws.append(try ring.constant(field.integer(1,using:&a),using:&a))
                let roots = try ExactRealRootDomain(field:field,using:&a)
                let whole = try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactRealRootInterval<Field.Value>.self))
                var domains = [whole,whole]
                var program: [ExactRealCellInstruction] = []
                try append(.literal(true),to:&program,&a)
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    let intervals = original.effective.axes[axis].intervals
                    if intervals.count == 1, !intervals[0].isEmpty {
                        let interval = intervals[0]
                        domains[axis] = try roots.domain(lower:bound(interval.lower,field,&a),upper:bound(interval.upper,field,&a),
                            includesLower:interval.includesLower,includesUpper:interval.includesUpper,using:&a)
                        continue
                    }
                    try append(.literal(false),to:&program,&a)
                    let coordinate = axis == 0 ? x:y
                    for interval in intervals {
                        try a.consumeWork(1)
                        guard !interval.isEmpty else { continue }
                        try append(.literal(true),to:&program,&a)
                        if case .finite(let lower) = interval.lower {
                            let value = try ring.constant(field.importingBase(lower,using:&a),using:&a)
                            try atom(ring.subtracting(coordinate,value,using:&a),interval.includesLower ? .greaterOrEqual:.greater,laws:&laws,program:&program,&a)
                        }
                        if case .finite(let upper) = interval.upper {
                            let value = try ring.constant(field.importingBase(upper,using:&a),using:&a)
                            try atom(ring.subtracting(value,coordinate,using:&a),interval.includesUpper ? .greaterOrEqual:.greater,laws:&laws,program:&program,&a)
                        }
                        try append(.or,to:&program,&a)
                    }
                    try append(.and,to:&program,&a)
                }
                // Specialize only on proved closed singleton domains; retain both
                // authored parameter slots and every original membership guard.
                var replacements: [Polynomial] = []
                for axis in 0..<2 {
                    try a.consumeWork(1)
                    let selected = domains[axis]
                    guard selected.includesLower, selected.includesUpper,
                        case .finite(let lower) = selected.lower,
                        case .finite(let upper) = selected.upper,
                        try field.compare(lower, upper, using: &a) == .equal else { continue }
                    if replacements.isEmpty {
                        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Polynomial.self))
                        replacements.reserveCapacity(2)
                        for index in 0..<2 {
                            try a.consumeWork(1)
                            replacements.append(try ring.variable(index, using: &a))
                        }
                    }
                    replacements[axis] = try ring.constant(lower, using: &a)
                }
                if !replacements.isEmpty {
                    for index in laws.indices {
                        try a.consumeWork(1)
                        laws[index] = try ring.substituted(laws[index], with: replacements, using: &a)
                    }
                }
                let source = try cells.bind(polynomials:laws,domains:domains,using:&a)
                let predicate = try cells.predicate(instructions:program,for:source,using:&a)
                let solver = ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
                let graph = try solver.graph(from:predicate,parameterCount:2,using:&a)
                let depth = try a.depth
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalIssuedPlaneGraph<S>.self))
                let result = OriginalIssuedPlaneGraph(original:original,graph:graph,field:field,depth:depth)
                try a.checkpoint(); return result
            }
        } catch { throw .preserving(error) }
    }
    private func bound<A: ExactScalarAdmission & ~Copyable>(_ value: ExactParameterBound<OriginalExactScalar>,
        _ field: Field, _ a: inout A) throws -> ExactRealRootBound<Field.Value> {
        switch value {
        case .negativeInfinity: return .negativeInfinity
        case .positiveInfinity: return .positiveInfinity
        case .finite(let value): return .finite(try field.importingBase(value,using:&a))
        }
    }
    private func append<T,A: ExactScalarAdmission & ~Copyable>(_ value: T,to array: inout [T],_ a: inout A) throws {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:T.self)); array.append(value)
    }
    private func atom<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial,_ relation: ExactRealCellSignRelation,
        laws: inout [Polynomial],program: inout [ExactRealCellInstruction],_ a: inout A) throws {
        let index = laws.count
        try append(law,to:&laws,&a)
        try append(.sign(polynomial:index,relation:relation),to:&program,&a)
        try append(.and,to:&program,&a)
    }
}
