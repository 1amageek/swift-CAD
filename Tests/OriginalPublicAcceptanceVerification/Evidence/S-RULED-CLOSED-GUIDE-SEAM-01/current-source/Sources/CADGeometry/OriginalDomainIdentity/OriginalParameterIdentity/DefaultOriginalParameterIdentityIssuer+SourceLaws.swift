#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalRationalParameterIdentityIssuing where F: ExactScalarImporting {
    func validate<Selection: Sendable,A: ExactScalarAdmission & ~Copyable>(_ law: OriginalRationalChartReceipt<S,Selection,F>,
        scope: OriginalParameterSelection<S,F>,limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        try scope.frame.require(limits,&a)
        guard scope.frame.source.owns(law.chart) else { throw OriginalDomainIdentityFailure.foreignOwner }
        guard scope.arity == law.support.count else { throw OriginalDomainIdentityFailure.invalidDomain }
        for axis in 0..<scope.arity {
            try a.consumeWork(1)
            guard scope.frame.coordinateSemantics[axis] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let d = scope.frame.axisDomains[axis]
            let interval = try d.interval(lower:.finite(law.support[axis].lower),upper:.finite(law.support[axis].upper),using:&a)
            try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
            let allowed = try d.set(intervals:[interval],using:&a)
            guard try d.difference(scope.storage[axis],allowed,using:&a).isEmpty else { throw OriginalDomainIdentityFailure.outsideSupport }
        }
    }

    /// Polynomial identities are checked on every selected discrete fiber; an axis
    /// with an open interval is checked as a whole polynomial variable, never sampled.
    func zero<A: ExactScalarAdmission & ~Copyable>(_ p: ExactPolynomial<F>,on scope: OriginalParameterSelection<S,F>,
        ring: ExactPolynomialDomain<F>,limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> Bool {
        if scope.isEmpty { return true }
        try OriginalDomainAccess.storage(1,[F.Value?].self,&a)
        var cases: [[F.Value?]] = [[]]
        let f = scope.frame.scalarField
        for axis in scope.axes {
            try a.consumeWork(1)
            var continuous = false
            for interval in axis.intervals {
                try a.consumeWork(1)
                switch (interval.lower,interval.upper) {
                case (.finite(let lo),.finite(let hi)):
                    if try f.compare(lo,hi,using:&a) != .equal { continuous = true }
                default: continuous = true
                }
            }
            var next: [[F.Value?]] = []
            for prefix in cases {
                if continuous {
                    try OriginalDomainAccess.storage(try OriginalDomainAccess.add(prefix.count,1),Optional<F.Value>.self,&a)
                    var row = prefix; row.append(nil)
                    try OriginalDomainAccess.storage(1,[F.Value?].self,&a); next.append(row)
                } else {
                    for interval in axis.intervals {
                        try a.consumeWork(1)
                        guard case .finite(let x) = interval.lower else { throw OriginalDomainIdentityFailure.invalidDomain }
                        guard next.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(try OriginalDomainAccess.add(prefix.count,1),Optional<F.Value>.self,&a)
                        var row = prefix; row.append(x)
                        try OriginalDomainAccess.storage(1,[F.Value?].self,&a); next.append(row)
                    }
                }
            }
            cases = next
        }
        for row in cases {
            try a.consumeWork(1)
            try OriginalDomainAccess.storage(row.count,ExactPolynomial<F>.self,&a)
            var replacement: [ExactPolynomial<F>] = []
            for i in row.indices {
                try a.consumeWork(1)
                replacement.append(try row[i].map { try ring.constant($0,using:&a) } ?? ring.variable(i,using:&a))
            }
            if try !ring.isZero(ring.substituted(p,with:replacement,using:&a),using:&a) { return false }
        }
        return true
    }
    public func collapsed<Selection: Sendable,A: ExactScalarAdmission & ~Copyable>(law: borrowing OriginalRationalChartReceipt<S,Selection,F>,
        on scope: borrowing OriginalParameterSelection<S,F>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let law = copy law, scope = copy scope
        return try OriginalDomainAccess.run(&admission) { a in
            try validate(law,scope:scope,limits:limits,&a)
            guard !scope.isEmpty else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            let ring = law.polynomials, f = law.field
            try OriginalDomainAccess.storage(scope.arity,F.Value.self,&a)
            var point: [F.Value] = []
            for axis in scope.axes {
                try a.consumeWork(1)
                guard let interval = axis.intervals.first,case .finite(let lo) = interval.lower,case .finite(let hi) = interval.upper else { throw OriginalDomainIdentityFailure.invalidDomain }
                point.append(try f.dividing(f.adding(lo,hi,using:&a),f.integer(2,using:&a),using:&a))
            }
            let denominator = try ring.evaluated(law.denominator,at:point,using:&a).value
            guard try f.sign(of:denominator,using:&a) != .zero else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            try OriginalDomainAccess.storage(3,ExactPolynomial<F>.self,&a)
            var residuals: [ExactPolynomial<F>] = []
            for axis in 0..<3 {
                try a.consumeWork(1)
                let coordinate = try f.dividing(ring.evaluated(law.homogeneous[axis],at:point,using:&a).value,denominator,using:&a)
                let residual = try ring.subtracting(law.homogeneous[axis],ring.scaled(law.denominator,by:coordinate,using:&a),using:&a)
                guard try zero(residual,on:scope,ring:ring,limits:limits,&a) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
                residuals.append(residual)
            }
            try OriginalDomainAccess.storage(7,ExactPolynomial<F>.self,&a)
            return try make(kind:.collapsedSubset,left:scope,right:scope,permutation:nil,gains:[],offsets:[],laws:law.homogeneous + residuals,using:&a,limits:limits)
        }
    }
    func boundarySide<A: ExactScalarAdmission & ~Copyable>(_ scope: OriginalParameterSelection<S,F>,axis: Int,value: F.Value,_ a: inout A) throws {
        guard axis >= 0, axis < scope.arity, !scope.isEmpty else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
        let f = scope.frame.scalarField
        for i in scope.axes[axis].intervals {
            try a.consumeWork(1)
            guard case .finite(let lo) = i.lower,case .finite(let hi) = i.upper,
                try f.compare(lo,value,using:&a) == .equal,try f.compare(hi,value,using:&a) == .equal else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
        }
    }
    func boundary<A: ExactScalarAdmission & ~Copyable>(declaration d: OriginalSourceBoundaryDeclaration<S>,
        left l: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,right r: OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,
        scope: OriginalParameterSelection<S,F>,rightFrame: OriginalParameterFrame<S,F>,permutation p: [Int],gains g: [F.Value],offsets o: [F.Value],
        kind: OriginalParameterIdentityKind,limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> OriginalParameterIdentity<S,F> {
        try validate(l,scope:scope,limits:limits,&a)
        guard l.source.owns(d.left),r.source.owns(d.right),d.left.selection.spans == l.chart.selection.spans,d.right.selection.spans == r.chart.selection.spans else { throw OriginalDomainIdentityFailure.foreignOwner }
        guard d.leftAxis >= 0,d.leftAxis < l.support.count,d.rightAxis >= 0,d.rightAxis < r.support.count else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
        let n = scope.arity
        guard p.count == n,g.count == n,o.count == n,rightFrame.arity == n else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(n,Bool.self,&a); var seen = [Bool](repeating:false,count:n)
        for i in p.indices {
            try a.consumeWork(1)
            guard p[i] >= 0,p[i] < n,!seen[p[i]] else { throw OriginalDomainIdentityFailure.invalidDomain }; seen[p[i]] = true
            guard scope.frame.coordinateSemantics[p[i]] == rightFrame.coordinateSemantics[i] else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
        }
        try boundarySide(scope,axis:d.leftAxis,value:d.leftSide == .lower ? l.support[d.leftAxis].lower : l.support[d.leftAxis].upper,&a)
        let target = try mapped(scope,to:rightFrame,permutation:p,gains:g,offsets:o,limits:limits,&a)
        try validate(r,scope:target,limits:limits,&a)
        try boundarySide(target,axis:d.rightAxis,value:d.rightSide == .lower ? r.support[d.rightAxis].lower : r.support[d.rightAxis].upper,&a)
        let ring = l.polynomials
        try OriginalDomainAccess.storage(n,ExactPolynomial<F>.self,&a)
        var substitutions: [ExactPolynomial<F>] = []
        for i in p.indices { try a.consumeWork(1); substitutions.append(try ring.adding(ring.scaled(ring.variable(p[i],using:&a),by:g[i],using:&a),ring.constant(o[i],using:&a),using:&a)) }
        try OriginalDomainAccess.storage(4,ExactPolynomial<F>.self,&a)
        var right: [ExactPolynomial<F>] = []
        for polynomial in r.homogeneous {
            try a.consumeWork(1)
            let imported = try ring.polynomial(terms:polynomial.terms,using:&a)
            right.append(try ring.substituted(imported,with:substitutions,using:&a))
        }
        try OriginalDomainAccess.storage(3,ExactPolynomial<F>.self,&a)
        var residuals: [ExactPolynomial<F>] = []
        for axis in 0..<3 {
            try a.consumeWork(1)
            let residual = try ring.subtracting(ring.multiplying(l.homogeneous[axis],right[3],using:&a),ring.multiplying(right[axis],l.denominator,using:&a),using:&a)
            guard try zero(residual,on:scope,ring:ring,limits:limits,&a) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            residuals.append(residual)
        }
        // Retain both original law depths; importing terms alone loses ring history.
        try OriginalDomainAccess.storage(15,ExactPolynomial<F>.self,&a)
        var proofLaws: [ExactPolynomial<F>] = []; proofLaws.reserveCapacity(15)
        proofLaws.append(contentsOf:l.homogeneous); proofLaws.append(contentsOf:r.homogeneous)
        proofLaws.append(contentsOf:right); proofLaws.append(contentsOf:residuals)
        try OriginalDomainAccess.storage(1,OriginalSourceBoundaryDeclaration<S>.self,&a)
        return try make(kind:kind,left:scope,right:target,permutation:p,gains:g,offsets:o,laws:proofLaws,boundaries:[d],using:&a,limits:limits)
    }
    public func declaredBoundary<A: ExactScalarAdmission & ~Copyable>(declaration: OriginalSourceBoundaryDeclaration<S>,
        left: borrowing OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,right: borrowing OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,
        scope: borrowing OriginalParameterSelection<S,F>,rightFrame: borrowing OriginalParameterFrame<S,F>,permutation: [Int],gains: [F.Value],offsets: [F.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let l = copy left,r = copy right,s = copy scope,f = copy rightFrame
        return try OriginalDomainAccess.run(&admission) { a in
            try boundary(declaration:declaration,left:l,right:r,scope:s,rightFrame:f,permutation:permutation,gains:gains,offsets:offsets,kind:.declaredSharedBoundary,limits:limits,&a)
        }
    }
    public func chartBoundary<A: ExactScalarAdmission & ~Copyable>(declaration: OriginalSourceBoundaryDeclaration<S>,
        left: borrowing OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,right: borrowing OriginalRationalChartReceipt<S,OriginalBSplineChartSelection,F>,
        scope: borrowing OriginalParameterSelection<S,F>,rightFrame: borrowing OriginalParameterFrame<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let l = copy left,r = copy right,s = copy scope,f = copy rightFrame
        return try OriginalDomainAccess.run(&admission) { a in
            guard l.source.owns(r.chart) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let n = s.arity,field = l.field
            try OriginalDomainAccess.storage(n,Int.self,&a); try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            var p: [Int] = [],g: [F.Value] = [],o: [F.Value] = []
            for i in 0..<n { try a.consumeWork(1); p.append(i); g.append(try field.integer(1,using:&a)); o.append(try field.integer(0,using:&a)) }
            return try boundary(declaration:declaration,left:l,right:r,scope:s,rightFrame:f,permutation:p,gains:g,offsets:o,kind:.chartBoundary,limits:limits,&a)
        }
    }
}
