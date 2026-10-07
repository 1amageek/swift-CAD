import L0
import L1

public enum L1AlgebraFixtures {
    static func check(_ condition: Bool) { precondition(condition, "L1 algebra assertion failed") }
    static func powered<F: ExactScalarArithmetic & ExactScalarOrdering>(
        _ domain: ExactPolynomialDomain<F>, _ p: ExactPolynomial<F>, _ n: Int,
        _ one: F.Value, _ budget: inout ExactScalarLedger) throws -> ExactPolynomial<F> {
        var result = try domain.constant(one, using: &budget)
        for _ in 0..<n { result = try domain.multiplying(result, p, using: &budget) }
        return result
    }
    public static func rational() throws {
        var a = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits())
        let f = ExactRationalScalarDomain()
        let d = try ExactPolynomialDomain(field: f, variableCount: 4, using: &a)
        let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let u = try d.constant(one, using: &a)
        let x = try d.variable(0, using: &a), y = try d.variable(1, using: &a)
        let z = try d.variable(2, using: &a), w = try d.variable(3, using: &a)
        let common = try d.adding(d.multiplying(x,y,using:&a),u,using:&a)
        let left = try d.adding(z,u,using:&a), right = try d.adding(w,u,using:&a)
        let p = try d.multiplying(common,left,using:&a), q = try d.multiplying(common,right,using:&a)
        let g = try d.greatestCommonDivisor(p,q,using:&a)
        check(try d.equals(g,common,using:&a))
        check(try d.equals(d.greatestCommonDivisor(q,p,using:&a),g,using:&a))
        check(try d.equals(d.dividedExactly(p,by:g,using:&a),left,using:&a))
        let division = try d.divided(d.adding(p,w,using:&a),by:common,using:&a)
        check(try d.equals(d.adding(d.multiplying(division.quotient,common,using:&a),division.remainder,using:&a),d.adding(p,w,using:&a),using:&a))
        check(try d.equals(division.remainder,w,using:&a))
        try L1PrimitiveFixtures.rejected("remainder") { _ = try d.dividedExactly(w,by:common,using:&a) }
        try L1PrimitiveFixtures.rejected("zeroDivisor") { _ = try d.divided(p,by:d.zero(using:&a),using:&a) }
        check(try d.isZero(d.greatestCommonDivisor(d.zero(using:&a),d.zero(using:&a),using:&a),using:&a))
        check(try d.equals(d.greatestCommonDivisor(p,d.zero(using:&a),using:&a),d.normalized(p,using:&a),using:&a))
        check(try d.equals(d.greatestCommonDivisor(x,y,using:&a),u,using:&a))

        // Sparse powers need no traversal through all absent degrees.
        let sparse = try d.polynomial(terms: [.init(powers:[0,0,0,1000],coefficient:one),.init(powers:[0,0,0,0],coefficient:one)],using:&a)
        check(try d.equals(d.greatestCommonDivisor(sparse,u,using:&a),u,using:&a))
        let c = try d.adding(x,y,using:&a), b = try d.subtracting(x,u,using:&a)
        let repeated = try d.scaled(d.multiplying(powered(d,c,2,one,&a),powered(d,b,3,one,&a),using:&a),by:two,using:&a)
        let decomposition = try d.squareFreeDecomposition(repeated,using:&a)
        check(decomposition.unit == two)
        check(decomposition.factors.map(\.multiplicity) == [2,3])
        check(try d.equals(decomposition.factors[0].polynomial,c,using:&a))
        check(try d.equals(decomposition.factors[1].polynomial,b,using:&a))
        var rebuilt = try d.constant(decomposition.unit,using:&a)
        for factor in decomposition.factors {
            rebuilt = try d.multiplying(rebuilt,powered(d,factor.polynomial,factor.multiplicity,one,&a),using:&a)
            var repeatedFactor = factor.polynomial
            for axis in 0..<4 {
                repeatedFactor = try d.greatestCommonDivisor(repeatedFactor,d.differentiated(factor.polynomial,in:axis,using:&a),using:&a)
            }
            check(try d.equals(repeatedFactor,u,using:&a))
        }
        check(try d.equals(rebuilt,repeated,using:&a))
        check(try d.equals(d.greatestCommonDivisor(decomposition.factors[0].polynomial,decomposition.factors[1].polynomial,using:&a),u,using:&a))
        check(try d.squareFreeDecomposition(d.constant(two,using:&a),using:&a).factors.isEmpty)
        try L1PrimitiveFixtures.rejected("multiplicity") { _ = try d.squareFreeDecomposition(d.zero(using:&a),using:&a) }

        let p1 = try d.subtracting(x,y,using:&a), p2 = try d.subtracting(x,z,using:&a)
        // A nonzero primitive remainder must lose its content before the next PRS step.
        let common2 = try d.adding(x,y,using:&a)
        let cofA = try d.adding(d.multiplying(x,x,using:&a),u,using:&a)
        let cofB = try d.adding(x,u,using:&a)
        check(try d.equals(d.greatestCommonDivisor(d.multiplying(common2,cofA,using:&a),
            d.multiplying(common2,cofB,using:&a),using:&a),common2,using:&a))
        let res = try d.resultant(p1,p2,eliminating:0,using:&a)
        check(try d.equals(res,d.subtracting(y,z,using:&a),using:&a))
        check(try d.equals(d.resultant(p2,p1,eliminating:0,using:&a),d.negated(res,using:&a),using:&a))
        check(try d.isZero(d.resultant(p1,p1,eliminating:0,using:&a),using:&a))
        check(try d.equals(d.resultant(d.constant(two,using:&a),d.multiplying(x,x,using:&a),eliminating:0,using:&a),d.constant(f.integer(4,using:&a),using:&a),using:&a))
        check(try d.equals(d.resultant(u,u,eliminating:0,using:&a),u,using:&a))
        // First pivot is nonzero; a later zero pivot requires a row exchange.
        let cubic = try d.adding(powered(d,x,3,one,&a),u,using:&a)
        let quadratic = try d.multiplying(x,x,using:&a)
        check(try d.equals(d.resultant(cubic,quadratic,eliminating:0,using:&a),u,using:&a))
        let resParam = try d.resultant(d.subtracting(quadratic,y,using:&a),d.subtracting(quadratic,z,using:&a),eliminating:0,using:&a)
        check(try d.equals(resParam,powered(d,d.subtracting(y,z,using:&a),2,one,&a),using:&a))
        try L1PrimitiveFixtures.rejected("variable") { _ = try d.resultant(p,q,eliminating:4,using:&a) }
        let huge = try d.polynomial(terms:[.init(powers:[Int.max,0,0,0],coefficient:one)],using:&a)
        try L1PrimitiveFixtures.rejected("count") { _ = try d.resultant(huge,x,eliminating:0,using:&a) }
    }
    public static func algebraic() throws {
        var a = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits())
        let f = try L1PrimitiveFixtures.scalarField()
        let d = try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        let one = try f.integer(1,using:&a), two = try f.integer(2,using:&a), root = try f.generator(using:&a)
        let x = try d.variable(0,using:&a), y = try d.variable(1,using:&a)
        let common = try d.subtracting(x,d.constant(root,using:&a),using:&a)
        let p = try d.multiplying(common,d.adding(y,d.constant(one,using:&a),using:&a),using:&a)
        let q = try d.multiplying(common,d.adding(y,d.constant(two,using:&a),using:&a),using:&a)
        check(try d.equals(d.greatestCommonDivisor(p,q,using:&a),common,using:&a))
        let difference = try d.subtracting(d.multiplying(x,x,using:&a),d.constant(two,using:&a),using:&a)
        check(try d.isZero(d.resultant(common,difference,eliminating:0,using:&a),using:&a))
        let squared = try powered(d,common,2,one,&a)
        let sf = try d.squareFreeDecomposition(squared,using:&a)
        check(sf.factors.count == 1 && sf.factors[0].multiplicity == 2)
        check(try d.equals(sf.factors[0].polynomial,common,using:&a))
        check(sf.depth.coefficient > 0 && sf.depth.value == 0)
        let zero = try d.resultant(common,common,eliminating:0,using:&a)
        var shallow = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits(coefficientDepth:0))
        try L1PrimitiveFixtures.rejected("coefficientDepth") { _ = try d.isZero(zero,using:&shallow) }
    }
    public static func failures() throws {
        var a = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits())
        let f = ExactRationalScalarDomain(), one = ExactRationalCoefficient.one
        let d = try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        let x = try d.variable(0,using:&a), u = try d.constant(one,using:&a)
        let p = try d.subtracting(d.multiplying(x,x,using:&a),u,using:&a)
        let q = try d.subtracting(x,u,using:&a)
        for operation in 0..<4 {
            var noWork = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits(work:0))
            try L1PrimitiveFixtures.rejected("work") {
                switch operation {
                case 0: _ = try d.divided(p,by:q,using:&noWork)
                case 1: _ = try d.greatestCommonDivisor(p,q,using:&noWork)
                case 2: _ = try d.squareFreeDecomposition(p,using:&noWork)
                default: _ = try d.resultant(p,q,eliminating:0,using:&noWork)
                }
            }
            var noStorage = ExactScalarLedger(limits: try L1PrimitiveFixtures.limits(storage:0))
            try L1PrimitiveFixtures.rejected("storage") {
                switch operation {
                case 0: _ = try d.divided(p,by:q,using:&noStorage)
                case 1: _ = try d.greatestCommonDivisor(p,q,using:&noStorage)
                case 2: _ = try d.squareFreeDecomposition(p,using:&noStorage)
                default: _ = try d.resultant(p,q,eliminating:0,using:&noStorage)
                }
            }
            var baseline = try L1PrimitiveFixtures.CallbackAdmission()
            switch operation {
            case 0: _ = try d.divided(p,by:q,using:&baseline)
            case 1: _ = try d.greatestCommonDivisor(p,q,using:&baseline)
            case 2: _ = try d.squareFreeDecomposition(p,using:&baseline)
            default: _ = try d.resultant(p,q,eliminating:0,using:&baseline)
            }
            var final = try L1PrimitiveFixtures.CallbackAdmission(); final.cancelCheckpoint = baseline.checkpoints
            try L1PrimitiveFixtures.rejected("cancelled") {
                switch operation {
                case 0: _ = try d.divided(p,by:q,using:&final)
                case 1: _ = try d.greatestCommonDivisor(p,q,using:&final)
                case 2: _ = try d.squareFreeDecomposition(p,using:&final)
                default: _ = try d.resultant(p,q,eliminating:0,using:&final)
                }
            }
        }
        check(try d.equals(d.greatestCommonDivisor(p,q,using:&a),q,using:&a))
    }
}
