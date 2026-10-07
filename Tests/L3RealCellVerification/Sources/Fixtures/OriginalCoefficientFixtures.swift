import L0
import L1
import L2
import L3
public enum OriginalCoefficientFixtures {
    struct Preparation: RationalAlgebraAdmitting {
        var work = 0
        var storage = 0
        mutating func consumeExactWork(_ units: Int) throws {
            guard units >= 0, units <= 50_000_000 - work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += units
        }
        mutating func retainExactStorage(_ words: Int) throws {
            guard words >= 0, words <= 50_000_000 - storage else { throw ExactScalarFailure.resourceLimit(.storage) }
            storage += words
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...100).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...100).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    public static func run() throws {
        var preparation = Preparation()
        let two = try ExactRationalCoefficient.originalDouble(2, usage: &preparation)
        let law = try ExactBivariatePolynomial.monomial(u: 2, v: 0, coefficient: .one, usage: &preparation)
            .subtracting(.constant(two, usage: &preparation), usage: &preparation)
        let selected = try ExactUnivariateRootIsolator().isolate(law, lower: .one, upper: two, maximumDepth: 100, usage: &preparation)[0]
        let original = try ExactAlgebraicRealRoot(polynomial: law, isolation: selected, usage: &preparation)
            .refined(maximumWidth: .originalDouble(0.0625, usage: &preparation), maximumDepth: 100, usage: &preparation)
        var a = ExactScalarLedger(limits: try .init(work: 100_000_000, storageBytes: 200_000_000, valueDepth: 100, coefficientDepth: 100))
        let f = try OriginalExactScalarDomain(root: original, axis: .coefficient,
            maximumValueDepth: 100, maximumCoefficientDepth: 100, using: &a)
        let alpha = try f.generator(using: &a)

        let field=try ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:3,using:&a)
        let coefficient=try field.importingBase(alpha,using:&a)
        let d=try ExactRealCellDomain(field:field,variableCount:1,using:&a),p=d.polynomials
        let r=try ExactRealRootDomain(field:field,using:&a)
        let all=try r.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let source=try d.bind(polynomials:[p.subtracting(p.variable(0,using:&a),p.constant(coefficient,using:&a),using:&a)],domains:[all],using:&a)
        let result=try d.decompose(source,limits:.init(maximumStoredCells:30,maximumRootsPerStack:10),using:&a)
        try CellFixtures.require(result.depth.coefficient >= original.isolation.isolationDepth && result.depth.coefficient > 0)
        for cell in result.cells {
            let sample=try d.sample(of:cell,in:result,using:&a)
            try CellFixtures.require(try d.locate(sample,in:result,limits:.init(maximumRoots:10),using:&a) == cell)
        }
        var shallow=ExactScalarLedger(limits:try .init(work:10_000_000,storageBytes:30_000_000,valueDepth:100,coefficientDepth:result.depth.coefficient-1))
        do { _ = try d.sample(of:result.cells.first!,in:result,using:&shallow); throw ExactRealCellFailure.invalidCoverage } catch ExactRealCellFailure.scalar(.resourceLimit(.coefficientDepth)) { }
    }
}
