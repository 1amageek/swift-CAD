import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Original Native source square identity", .serialized)
struct NativeSurfaceSourceZeroSetTests {
    private enum Refusal: Error { case work, storage }
    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }
    private func charts<A: ExactScalarAdmission & ~Copyable>(sign: Double = 1,constant: Double = 0,extraConstant: Double = 0,
        quadraticSign: Double = 1,mixed: Bool = false,usage budget: inout A) throws -> [NativeSurfaceSurfaceSourceChart] {
        let first = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,2,2],vKnots: [0,0,1,1],
            controlPoints: [-1.0,1].map { y in [0.0,1,2].map { x in .init(x: x,y: y,z: constant) } })
        let x = [-1.0,-0.5,0,0.5,1],y = [-1.0,0,1]
        let quartic = [3.0,-9,19,-9,3],square = [3.0,-3,3]
        let second = BSplineSurface3D(uDegree: 4,vDegree: 2,
            uKnots: [-1,-1,-1,-1,-1,1,1,1,1,1],vKnots: [-1,-1,-1,1,1,1],
            controlPoints: y.indices.map { v in x.indices.map { u in
                .init(x: x[u],y: y[v],z: constant + sign * (quartic[u] + quadraticSign * square[v])
                    + extraConstant + (mixed ? x[u] * y[v] : 0)) } },weights: Array(repeating: Array(repeating: 2.0,count: 5),count: 3))
        func owners(_ source: BSplineSurface3D) throws -> [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] {
            let box = SurfaceParameterBox(u: try .init(lower: source.uKnots[source.uDegree],upper: source.uKnots[source.uControlPointCount]),
                v: try .init(lower: source.vKnots[source.vDegree],upper: source.vKnots[source.vControlPointCount]))
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,tolerance: .standard,using: &budget)
            return try prepared.originalIntersectionNativeSpans(over: box,tolerance: .standard,using: &budget)
        }
        let firstOwners = try owners(first),secondOwner = try #require(try owners(second).first)
        let secondLaw = try OriginalRationalSurfacePolynomial(source: second,native: secondOwner,
            domain: .init(u: secondOwner.uBounds,v: secondOwner.vBounds),view: .init(x: 0,y: 0,z: 1),tolerance: .standard,usage: &budget)
        var result: [NativeSurfaceSurfaceSourceChart] = []
        for firstOwner in firstOwners {
            let firstLaw = try OriginalRationalSurfacePolynomial(source: first,native: firstOwner,
                domain: .init(u: firstOwner.uBounds,v: firstOwner.vBounds),view: .init(x: 0,y: 0,z: 1),tolerance: .standard,usage: &budget)
            let system = try OriginalRationalIntersectionSystem(first: firstLaw,second: secondLaw,usage: &budget)
            let domains = try [OriginalRationalParameterDomain(firstOwner.uBounds,usage: &budget),
                .init(firstOwner.vBounds,usage: &budget),.init(secondOwner.uBounds,usage: &budget),.init(secondOwner.vBounds,usage: &budget)]
            result.append(.init(firstOwner: firstOwner,secondOwner: secondOwner,first: firstLaw,second: secondLaw,system: system,nativeDomains: domains))
        }
        return result
    }
    @Test(.timeLimit(.minutes(1)))
    func bothOrientationsConstantCounterpartAndOriginalDenominators() throws {
        for sign in [-1.0,1] {
            var budget = try usage();let original = try charts(sign: sign,constant: 2,usage: &budget)
            for chart in original {
                let proof = try geometryTestRequire(try NativeSurfaceSourceZeroSetProof.prepare(chart: chart,usage: &budget))
                try proof.validate(chart: chart,usage: &budget)
                #expect(proof.equationIndex == 2 && proof.targetRole == 1)
                #expect(proof.orientation == (sign > 0 ? 1 : -1))
                #expect(proof.positiveCoefficients.count == 2 && proof.positiveCoefficients.allSatisfy { $0.isPositive })
                #expect(proof.consequences.count == 2)
                #expect(try proof.orientedNumerator.subtracting(proof.reconstruction,usage: &budget).isZero)
                #expect(try proof.rawEquationIdentity.matches(chart.system.equations[2],usage: &budget))
                for u in [-1.0,0,1] { for v in [-1.0,0,1] {
                    let exactU = try ExactRationalCoefficient.originalDouble(u,usage: &budget)
                    let exactV = try ExactRationalCoefficient.originalDouble(v,usage: &budget)
                    let originalN = try proof.orientedNumerator.evaluated(atU: exactU,v: exactV,usage: &budget)
                    let first = try proof.factors[0].evaluated(atU: exactU,v: exactV,usage: &budget)
                    let second = try proof.factors[1].evaluated(atU: exactU,v: exactV,usage: &budget)
                    let squares = try first.multiplied(by: first,usage: &budget).multiplied(by: proof.positiveCoefficients[0],usage: &budget)
                        .adding(second.multiplied(by: second,usage: &budget).multiplied(by: proof.positiveCoefficients[1],usage: &budget),usage: &budget)
                    #expect(originalN == squares && !originalN.isNegative)
                    #expect(try chart.second.homogeneous[3].evaluated(atU: exactU,v: exactV,usage: &budget).isPositive)
                } }
            }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func failedFullIdentityAndOppositeSignDecline() throws {
        var budget = try usage()
        for original in [try charts(extraConstant: 1,usage: &budget),try charts(quadraticSign: -1,usage: &budget),try charts(mixed: true,usage: &budget)] {
            for chart in original { #expect(try NativeSurfaceSourceZeroSetProof.prepare(chart: chart,usage: &budget) == nil) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func immutableOriginalBindingRejectsForeignSourceOwnerAndDomain() throws {
        var budget = try usage()
        let proof = try {
            let temporary = try charts(usage: &budget)
            return try geometryTestRequire(try NativeSurfaceSourceZeroSetProof.prepare(chart: temporary[0],usage: &budget))
        }()
        let original = try charts(usage: &budget),foreign = try charts(constant: 2,usage: &budget)
        try proof.validate(chart: original[0],usage: &budget)
        do { try proof.validate(chart: foreign[0],usage: &budget);Issue.record("Foreign source replaced retained real-zero authority.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .intersectionFailure) }
        let chart = original[0]
        let changedOwner = NativeSurfaceSurfaceSourceChart(firstOwner: foreign[0].firstOwner,secondOwner: chart.secondOwner,
            first: chart.first,second: chart.second,system: chart.system,nativeDomains: chart.nativeDomains)
        do { try proof.validate(chart: changedOwner,usage: &budget);Issue.record("Foreign Native owner replaced source-bound proof.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .invalidInput) }
        var domains = chart.nativeDomains;domains[2] = try .init(lower: .zero,upper: .one,usage: &budget)
        let changed = NativeSurfaceSurfaceSourceChart(firstOwner: chart.firstOwner,secondOwner: chart.secondOwner,
            first: chart.first,second: chart.second,system: chart.system,nativeDomains: domains)
        do { try proof.validate(chart: changed,usage: &budget);Issue.record("Changed source domain replaced full real-zero proof support.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .intersectionFailure) }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentAdmissionAndFinalDeclineCancellationPropagate() async throws {
        var budget = try usage();let original = try charts(usage: &budget)[0]
        var noWork = GeometryTestScalarRecorder(observeWork: { _ in throw Refusal.work },observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSourceZeroSetProof.prepare(chart: original,usage: &noWork);Issue.record("Work refusal became source-proof absence.") }
        catch Refusal.work {}
        var noStorage = GeometryTestScalarRecorder(observeWork: { _ in },observeStorageWords: { _ in throw Refusal.storage },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSourceZeroSetProof.prepare(chart: original,usage: &noStorage);Issue.record("Storage refusal became source-proof absence.") }
        catch Refusal.storage {}
        let outside = try charts(extraConstant: 1,usage: &budget)[0],count = Mutex(0)
        var measured = GeometryTestScalarRecorder(observeWork: { _ in count.withLock { $0 += 1 } },observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        #expect(try NativeSurfaceSourceZeroSetProof.prepare(chart: outside,usage: &measured) == nil)
        let last = count.withLock { $0 };#expect(last > 0)
        let current = Mutex(0),cancelledAtFinal = Mutex(false)
        let task = Task {
            var cancelling = GeometryTestScalarRecorder(observeWork: { _ in
                if current.withLock({ $0 += 1;return $0 }) == last {
                    cancelledAtFinal.withLock { $0 = true };withUnsafeCurrentTask { $0?.cancel() }
                }
            },observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
            return try NativeSurfaceSourceZeroSetProof.prepare(chart: outside,usage: &cancelling)
        }
        do { _ = try await task.value;Issue.record("Final callback cancellation became normal source-proof decline.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancelledAtFinal.withLock { $0 })
        #expect(current.withLock { $0 } == last)
        #expect(try NativeSurfaceSourceZeroSetProof.prepare(chart: original,usage: &budget) != nil)
    }
}
