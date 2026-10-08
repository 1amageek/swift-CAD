import L0
@testable import L1
@testable import L1Fixtures

extension KernelFixtures {
    static func issued<P: ExactPolynomialSubresultantProducing, A: ExactScalarAdmission & ~Copyable>(
        _ producer: P, _ first: P.Polynomial, _ second: P.Polynomial, axis: Int, _ a: inout A
    ) throws -> P.Subresultants {
        try producer.principalSubresultants(first, second, eliminating: axis, using: &a)
    }
    static func laplace<F: ExactScalarArithmetic & ExactScalarOrdering>(_ d: ExactPolynomialDomain<F>,
        _ matrix: [ExactPolynomial<F>], _ size: Int, _ a: inout ExactScalarLedger
    ) throws -> ExactPolynomial<F> {
        if size == 0 { return try d.constant(d.context.one, using: &a) }
        if size == 1 { return matrix[0] }
        var sum = try d.zero(using: &a)
        for column in 0..<size {
            if matrix[column].terms.isEmpty { continue }
            var minor: [ExactPolynomial<F>] = []
            for row in 1..<size { for j in 0..<size where j != column { minor.append(matrix[row*size+j]) } }
            let product = try d.multiplying(matrix[column], laplace(d,minor,size-1,&a), using: &a)
            sum = try column % 2 == 0 ? d.adding(sum,product,using:&a) : d.subtracting(sum,product,using:&a)
        }
        return sum
    }
    static func independentPSC<F: ExactScalarArithmetic & ExactScalarOrdering>(_ d: ExactPolynomialDomain<F>,
        _ first: ExactPolynomial<F>, _ second: ExactPolynomial<F>, axis: Int, index: Int,
        _ a: inout ExactScalarLedger) throws -> ExactPolynomial<F> {
        let m = try d.degree(of:first,in:axis,using:&a)!, n = try d.degree(of:second,in:axis,using:&a)!
        let size = m+n-2*index, highest = m+n-index-1
        var matrix: [ExactPolynomial<F>] = []
        for row in 0..<size {
            let law = row < n-index ? first : second
            let shift = row < n-index ? n-index-1-row : m-index-1-(row-n+index)
            for col in 0..<size {
                let exponent = highest-col-shift
                var terms: [ExactPolynomialTerm<F.Value>] = []
                for term in law.terms where term.powers[axis] == exponent {
                    var powers = term.powers; powers[axis] = 0
                    terms.append(.init(powers:powers,coefficient:term.coefficient))
                }
                matrix.append(try d.polynomial(terms:terms,using:&a))
            }
        }
        return try laplace(d,matrix,size,&a)
    }
    static func compare<F: ExactScalarArithmetic & ExactScalarOrdering>(_ d: ExactPolynomialDomain<F>,
        _ p: ExactPolynomial<F>, _ q: ExactPolynomial<F>, axis: Int, independent: Bool,
        _ a: inout ExactScalarLedger) throws {
        let actual = try d.principalSubresultants(p,q,eliminating:axis,algorithm:.prs,using:&a)
        let reference = try d.principalSubresultants(p,q,eliminating:axis,algorithm:.determinant,using:&a)
        let publicResult = try issued(d,p,q,axis:axis,&a)
        try check(actual.values.count == reference.values.count && publicResult.values.count == reference.values.count)
        for index in actual.values.indices {
            try check(try d.equals(actual.values[index],reference.values[index],using:&a))
            try check(try d.equals(publicResult.values[index],reference.values[index],using:&a))
            try check(actual.values[index].depth == actual.depth)
            if independent { try check(try d.equals(actual.values[index],independentPSC(d,p,q,axis:axis,index:index,&a),using:&a)) }
        }
        let swapped = try d.principalSubresultants(q,p,eliminating:axis,algorithm:.prs,using:&a)
        let m = try d.degree(of:p,in:axis,using:&a) ?? 0, n = try d.degree(of:q,in:axis,using:&a) ?? 0
        for j in swapped.values.indices {
            let expected = try (m-j)%2 == 1 && (n-j)%2 == 1 ? d.negated(actual.values[j],using:&a) : actual.values[j]
            try check(try d.equals(swapped.values[j],expected,using:&a))
        }
    }
    public static func psc() throws {
        for mode in 0..<18 {
            var a = try ledger()
            let f = Field(), d = try Domain(field:f,variableCount:2,using:&a)
            let m = 1+mode%5, n = 1+(mode/3)%4, axis = mode%2, other = 1-axis
            var left: [ExactPolynomialTerm<Field.Value>] = [], right: [ExactPolynomialTerm<Field.Value>] = []
            for degree in 0...m {
                var powers = [0,0]; powers[axis] = degree
                left.append(.init(powers:powers,coefficient:try f.integer(degree == m ? 2 : (degree+mode)%5-2,using:&a)))
            }
            for degree in 0...n {
                var powers = [0,0]; powers[axis] = degree
                right.append(.init(powers:powers,coefficient:try f.integer(degree == n ? 3 : (2*degree+mode)%7-3,using:&a)))
            }
            var p = try d.polynomial(terms:left,using:&a), q = try d.polynomial(terms:right,using:&a)
            if mode%3 == 0 {
                let content = try d.adding(d.variable(other,using:&a),d.constant(f.integer(1,using:&a),using:&a),using:&a)
                p = try d.multiplying(p,content,using:&a); q = try d.multiplying(q,content,using:&a)
            }
            try compare(d,p,q,axis:axis,independent:m+n<=5,&a)
        }
        var a = try ledger(); let f = Field(), d = try Domain(field:f,variableCount:1,using:&a)
        let one = try f.integer(1,using:&a), x = try d.variable(0,using:&a)
        let cubic = try d.polynomial(terms:[.init(powers:[3],coefficient:one),.init(powers:[0],coefficient:one)],using:&a)
        let quadratic = try d.polynomial(terms:[.init(powers:[2],coefficient:try f.integer(2,using:&a))],using:&a)
        let defect = try d.principalSubresultants(cubic,quadratic,eliminating:0,algorithm:.prs,using:&a)
        try check(try d.equals(defect.values[0],d.constant(f.integer(8,using:&a),using:&a),using:&a))
        try check(defect.values.count == 2 && defect.values[1].terms.isEmpty)
        try compare(d,cubic,quadratic,axis:0,independent:true,&a)
        let factor = try d.adding(x,d.constant(one,using:&a),using:&a)
        try compare(d,d.multiplying(cubic,factor,using:&a),d.multiplying(quadratic,factor,using:&a),axis:0,independent:false,&a)
        // Brown's abnormal sequence has consecutive degree drops: 8, 6, 4, 2, 1, 0.
        let brownFirst = try d.polynomial(terms:[(8,1),(6,1),(4,-3),(3,-3),(2,8),(1,2),(0,-5)].map {
            .init(powers:[$0.0],coefficient:try f.integer($0.1,using:&a)) },using:&a)
        let brownSecond = try d.polynomial(terms:[(6,3),(4,5),(2,-4),(1,-9),(0,21)].map {
            .init(powers:[$0.0],coefficient:try f.integer($0.1,using:&a)) },using:&a)
        try compare(d,brownFirst,brownSecond,axis:0,independent:false,&a)
        let brown = try d.principalSubresultants(brownFirst,brownSecond,eliminating:0,using:&a)
        try check(brown.values.count == 6 && brown.values[5].terms.isEmpty && brown.values[3].terms.isEmpty)
        let zero = try d.zero(using:&a), constant = try d.constant(one,using:&a)
        for p in [zero,constant] {
            let result = try d.principalSubresultants(p,cubic,eliminating:0,using:&a)
            try check(result.values.isEmpty && result.second.termCount == cubic.termCount)
            try check(try d.equals(result.first,p,using:&a))
        }
        let foreign = try Domain(field:f,variableCount:1,using:&a)
        do { _ = try d.principalSubresultants(zero,foreign.zero(using:&a),eliminating:0,using:&a); throw ExactPolynomialFailure.invalidCertificate }
        catch ExactPolynomialFailure.incompatibleDomain { }
        for axis in [-1,1] {
            do { _ = try d.principalSubresultants(zero,zero,eliminating:axis,using:&a); throw ExactPolynomialFailure.invalidCertificate }
            catch ExactPolynomialFailure.invalidVariable { }
        }
        for method: ExactPolynomialSubresultantAlgorithm in [.prs,.determinant] {
            for workLimit in [true,false] {
                var limited = ExactScalarLedger(limits:try .init(work:workLimit ? 0 : 100_000,storageBytes:workLimit ? 100_000 : 0,valueDepth:400,coefficientDepth:400))
                do { _ = try d.principalSubresultants(cubic,quadratic,eliminating:0,algorithm:method,using:&limited); throw ExactPolynomialFailure.invalidCertificate }
                catch ExactPolynomialFailure.scalar(.resourceLimit(let axis)) { try check(axis == (workLimit ? .work : .storage)) }
            }
            var trace = try L1PrimitiveFixtures.CallbackAdmission()
            _ = try d.principalSubresultants(cubic,quadratic,eliminating:0,algorithm:method,using:&trace)
            var cancel = try L1PrimitiveFixtures.CallbackAdmission(); cancel.cancelCheckpoint = trace.checkpoints
            do { _ = try d.principalSubresultants(cubic,quadratic,eliminating:0,algorithm:method,using:&cancel); throw ExactPolynomialFailure.invalidCertificate }
            catch ExactPolynomialFailure.scalar(.cancelled) { }
        }
        for axis: ExactScalarRootAxis in [.value,.coefficient] {
            let field = try L1PrimitiveFixtures.scalarField(axis:axis)
            let p = try ExactPolynomialDomain(field:field,variableCount:1,using:&a)
            let root = try field.generator(using:&a), unit = try field.integer(1,using:&a)
            let left = try p.polynomial(terms:[.init(powers:[2],coefficient:unit),.init(powers:[0],coefficient:root)],using:&a)
            let right = try p.polynomial(terms:[.init(powers:[2],coefficient:root),.init(powers:[0],coefficient:unit)],using:&a)
            try compare(p,left,right,axis:0,independent:true,&a)
            let retained = try p.principalSubresultants(left,p.zero(using:&a),eliminating:0,using:&a)
            var shallow = ExactScalarLedger(limits:try .init(work:100_000,storageBytes:100_000,valueDepth:axis == .value ? 0 : 400,coefficientDepth:axis == .coefficient ? 0 : 400))
            do { _ = try p.principalSubresultants(retained.first,retained.second,eliminating:0,using:&shallow); throw ExactPolynomialFailure.invalidCertificate }
            catch ExactPolynomialFailure.scalar(.resourceLimit(let rejectedAxis)) {
                try check(rejectedAxis == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
        let deferred: ExactPrincipalSubresultantSequence<OriginalExactScalarDomain> = try {
            var local = try ledger(); let field = try L1PrimitiveFixtures.scalarField()
            let domain = try ExactPolynomialDomain(field:field,variableCount:1,using:&local)
            let unit = try field.integer(1,using:&local), root = try field.generator(using:&local)
            let first = try domain.polynomial(terms:[.init(powers:[2],coefficient:unit),.init(powers:[0],coefficient:root)],using:&local)
            let second = try domain.polynomial(terms:[.init(powers:[2],coefficient:unit),.init(powers:[0],coefficient:try field.negated(root,using:&local))],using:&local)
            return try domain.principalSubresultants(first,second,eliminating:0,using:&local)
        }()
        let recovered = try ExactPolynomialDomain(retaining:deferred.first,using:&a)
        try check(try recovered.equals(deferred.values[0],recovered.constant(recovered.field.integer(8,using:&a),using:&a),using:&a))
        try check(deferred.values[1].terms.isEmpty && deferred.values[1].depth == deferred.depth)
        print("PASS complete PSC values, determinants, defects, contents, swap signs, axis/owner/depth and terminal failure")
    }
}
