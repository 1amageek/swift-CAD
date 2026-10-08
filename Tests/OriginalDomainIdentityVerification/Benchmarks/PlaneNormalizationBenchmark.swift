import L0
import L1
import L2
import DI0
import DI
import SourceIssuer

struct BenchmarkPlane: OriginalPlaneSourceReading {
    let origin: [Double]
    let normal: [Double]
    func originCoordinate(in axis: Int) -> Double { origin[axis] }
    func normalCoordinate(in axis: Int) -> Double { normal[axis] }
}
struct BenchmarkPlaneProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing BenchmarkPlane,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<BenchmarkPlane> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard input.origin.count == 3,input.normal.count == 3 else { throw OriginalSourceIssuanceFailure.invalidSource }
            var nonzero = false
            for i in 0..<3 {
                try a.consumeWork(1)
                guard input.origin[i].isFinite,input.normal[i].isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
                nonzero = nonzero || input.normal[i] != 0
            }
            guard nonzero else { throw OriginalSourceIssuanceFailure.invalidSource }
            return .init(original:copy input,sourceDepth:0)
        } catch let error as OriginalSourceIssuanceFailure { throw error }
        catch let error as ExactScalarFailure { throw .scalar(error) }
        catch { throw .sourceRejected(error) }
    }
}

func benchmarkAdmission() throws -> ExactScalarLedger {
    .init(limits: try .init(work: 10_000_000, storageBytes: 100_000_000, valueDepth: 128, coefficientDepth: 32))
}
func benchmark<F: ExactScalarArithmetic & ExactScalarOrdering>(_ name: String, field: F,
    normal: [Double], first: F.Value, length: F.Value, count: Int) throws {
    var preparation = try benchmarkAdmission()
    let limits = try OriginalDomainIdentityLimits(source: .init(remainingSourceDepth: 0),
        maximumTransportDepth: 16, maximumCharts: 64, maximumFamilies: 8, maximumIdentityProofs: 64)
    let source = try DefaultOriginalSourceBindingIssuer(provider: BenchmarkPlaneProvider()).bind(
        BenchmarkPlane(origin: [2,3,4], normal: normal), limits: limits.source, using: &preparation)
    let issuer = DefaultOriginalPlaneBasisIssuer<BenchmarkPlane,F>()
    for _ in 0..<10 {
        var a = try benchmarkAdmission()
        _ = try issuer.issue(source: source, field: field, firstLength: first, normalLength: length,
            limits: limits.source, using: &a)
    }
    var last: OriginalPlaneBasisReceipt<BenchmarkPlane,F>?, work = 0, storage = 0
    let clock = ContinuousClock(), start = clock.now
    for _ in 0..<count {
        var a = try benchmarkAdmission()
        last = try issuer.issue(source: source, field: field, firstLength: first, normalLength: length,
            limits: limits.source, using: &a)
        work += a.work; storage += a.storageBytes
    }
    let duration = start.duration(to: clock.now).components
    let microseconds = (Double(duration.seconds) + Double(duration.attoseconds)/1e18) * 1e6 / Double(count)
    guard let basis = last else { throw ExactScalarFailure.invalidEvidence }
    let zero = try field.integer(0, using: &preparation)
    let expectedU = [zero, try field.dividing(basis.normal[2],first,using:&preparation),
        try field.negated(field.dividing(basis.normal[1],first,using:&preparation),using:&preparation)]
    for i in 0..<3 {
        guard try field.compare(expectedU[i],basis.u[i],using:&preparation) == .equal else { throw ExactScalarFailure.invalidEvidence }
    }
    let x = try field.integer(3, using: &preparation), y = try field.integer(4, using: &preparation)
    let uv = try basis.parameters(of: basis.position(u: x, v: y, limits: limits, using: &preparation),
        limits: limits, using: &preparation)
    guard try field.compare(uv[0], x, using: &preparation) == .equal,
        try field.compare(uv[1], y, using: &preparation) == .equal else { throw ExactScalarFailure.invalidEvidence }
    print("{\"case\":\"\(name)\",\"iterations\":\(count),\"microseconds\":\(microseconds),\"work\":\(work/count),\"generated_bytes\":\(storage/count),\"exact\":true}")
}
@main struct PlaneNormalizationBenchmark {
    static func main() throws {
        var a = try benchmarkAdmission()
        let kind = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sqrt2"
        if kind == "rational" {
            let f = ExactRationalScalarDomain()
            try benchmark(kind, field: f, normal: [3,4,0], first: f.integer(4,using:&a),
                length: f.integer(5,using:&a), count: 5000)
        } else {
            typealias F = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
            let base = try F.base(field:.init(),maximumExtensionLevel:2,using:&a)
            let roots = try ExactRealRootDomain(field:base,using:&a),p = roots.polynomials
            let equation = try p.polynomial(terms:[.init(powers:[2],coefficient:base.integer(1,using:&a)),
                .init(powers:[0],coefficient:base.integer(-2,using:&a))],using:&a)
            let law = try roots.bind(equation,refinementAxis:.coefficient,using:&a)
            let interval = try roots.domain(lower:.finite(base.integer(1,using:&a)),upper:.finite(base.integer(2,using:&a)),using:&a)
            let isolated = try roots.isolate(law,in:interval,limits:.init(maximumRoots:1),using:&a).roots[0]
            let refined = try roots.refine(isolated,maximumWidth:base.dividing(base.integer(1,using:&a),base.integer(16,using:&a),using:&a),using:&a)
            let extensionField = try base.adjoin(refined,using:&a)
            try benchmark(kind, field: extensionField.domain, normal: [0,1,1], first: extensionField.generator,
                length: extensionField.generator, count: 500)
        }
    }
}
