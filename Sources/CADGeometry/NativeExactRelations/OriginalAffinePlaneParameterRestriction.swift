import CADCore

/// Existing source-owned necessary plane preimage; never a contact certificate.
struct OriginalAffinePlaneParameterRestriction {
    enum Kind: Sendable { case unchanged, excluded, singleton(OriginalExactScalar) }

    static func selectionIntervals<A: ExactScalarAdmission & ~Copyable>(
        _ singleton: ExactParameterInterval<OriginalExactScalar>?, using a: inout A
    ) throws -> [[ExactParameterInterval<OriginalExactScalar>]] {
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalExactScalar>].self))
        if let singleton {
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalExactScalar>.self))
            return [[singleton]]
        }
        return [[]]
    }

    /// Both consumers supply issued one-parameter graphs. The caller owns the
    /// original proof scope and the final retained receipt's typed storage.
    func select<S: Sendable, E: Sendable, P: OriginalPlaneSourceReading,
        A: ExactScalarAdmission & ~Copyable>(
        _ binding: OriginalDomainBoundParametricGraph<S, OriginalExactScalarDomain, E>,
        plane: OriginalIssuedPlaneGraph<P>, limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (selected: OriginalDomainBoundParametricGraph<S, OriginalExactScalarDomain, E>,
            equation: ExactPolynomial<OriginalExactScalarDomain>, kind: Kind) {
        try binding.admitProof(limits:limits,using:&a)
        let g = binding.graph,f = g.field,r = g.polynomials,basis = plane.original.law
        var equation = try r.constant(f.integer(0,using:&a),using:&a)
        for axis in 0..<3 {
            try a.consumeWork(1)
            let offset = try r.scaled(g.homogeneous[3],by:f.importing(basis.origin[axis],using:&a),using:&a)
            equation = try r.adding(equation,r.scaled(r.subtracting(g.homogeneous[axis],offset,using:&a),
                by:f.importing(basis.normal[axis],using:&a),using:&a),using:&a)
        }
        var kind: Kind = .unchanged
        var request = binding.request
        var candidate = equation
        var degree = try r.degree(of:equation,in:0,using:&a)
        let parameterRing = try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        let identity = try parameterRing.equals(parameterRing.importing(g.parameterTransport.numerators[0],using:&a),parameterRing.variable(0,using:&a),using:&a)
            && parameterRing.equals(parameterRing.importing(g.parameterTransport.denominators[0],using:&a),parameterRing.constant(f.integer(1,using:&a),using:&a),using:&a)
        if identity,let originalDegree = degree,originalDegree > 1,
            let weightDegree = try r.degree(of:g.homogeneous[3],in:0,using:&a),weightDegree > 0 {
            // The existing L5 map retains Hw != 0; P = Hw * Q preserves its plane preimage.
            let division = try r.divided(equation,by:g.homogeneous[3],using:&a)
            if try r.isZero(division.remainder,using:&a),
                let quotientDegree = try r.degree(of:division.quotient,in:0,using:&a),quotientDegree <= 1 {
                candidate = division.quotient;degree = quotientDegree
            }
        }
        if identity,let degree,degree <= 1 {
            if degree == 0 {
                kind = .excluded
                let intervals = try Self.selectionIntervals(nil, using: &a)
                request = try request.frame.selection(intervals:intervals,limits:limits,using:&a)
            } else {
                var constant = try f.integer(0,using:&a),slope = try f.integer(0,using:&a)
                for term in candidate.terms {
                    try a.consumeWork(1)
                    guard term.powers.count == 1 else { throw NativeExactRelationFailure.invalidDomain }
                    if term.powers[0] == 0 { constant = term.coefficient }
                    else if term.powers[0] == 1 { slope = term.coefficient }
                    else { throw NativeExactRelationFailure.invalidDomain }
                }
                let root = try f.dividing(f.negated(constant,using:&a),slope,using:&a)
                let lower = try f.compare(root,g.support[0].lower,using:&a),upper = try f.compare(root,g.support[0].upper,using:&a)
                if lower == .less || upper == .greater || (upper == .equal && !g.includesUpperBoundary[0]) {
                    kind = .excluded
                    let intervals = try Self.selectionIntervals(nil, using: &a)
                    request = try request.frame.selection(intervals:intervals,limits:limits,using:&a)
                } else {
                    kind = .singleton(root)
                    let interval = try ExactParameterInterval.checked(field:f,lower:.finite(root),upper:.finite(root),
                        includesLower:true,includesUpper:true,depth:root.depth,using:&a)
                    let intervals = try Self.selectionIntervals(interval, using: &a)
                    let candidate = try request.frame.selection(intervals:intervals,limits:limits,using:&a)
                    request = try request.intersection(candidate,limits:limits,using:&a)
                }
            }
        }
        let selected = try DefaultOriginalParametricGraphDomainBinder().bind(graph:g,request:request,limits:limits,using:&a)
        return (selected, equation, kind)
    }
}
