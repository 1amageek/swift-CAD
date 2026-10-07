import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Original closed Native corner zero identity", .serialized)
struct NativeSurfaceSourceCornerZeroSetTests {
    private enum Refusal: Error { case work, storage }
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in },retainStorage: { _ in },visitCell: { _ in },visitCoefficientCell: { _ in })
    }
    private func chart(values: [Double] = [1,0,1,1], sign: Double = 1, constant: Double = 2,
        higherDegree: Bool = false, usage budget: inout OriginalRelationUsage) throws -> NativeSurfaceSurfaceSourceChart {
        let first = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,5,5],vKnots: [0,0,1,1],
            controlPoints: [0.0,1].map { y in [0.0,5].map { x in .init(x: x,y: y,z: constant) } })
        let x = higherDegree ? [4.0,4.5,5] : [4.0,5]
        let y = [-2.0,3]
        let second = BSplineSurface3D(uDegree: higherDegree ? 2 : 1,vDegree: 1,
            uKnots: higherDegree ? [4,4,4,5,5,5] : [4,4,5,5],vKnots: [-2,-2,3,3],
            controlPoints: (0..<2).map { row in x.indices.map { column in
                let value = higherDegree && column == 1 ? -2 : values[row * 2 + (column == 0 ? 0 : 1)]
                return .init(x: x[column],y: y[row],z: constant + sign * value)
            } }, weights: higherDegree ? [[1,1,1],[1,1,1]] : [[1,2],[3,4]])
        func owner(_ source: BSplineSurface3D) throws -> PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan {
            let box = SurfaceParameterBox(u: try .init(lower: source.uKnots[source.uDegree],upper: source.uKnots[source.uControlPointCount]),
                v: try .init(lower: source.vKnots[source.vDegree],upper: source.vKnots[source.vControlPointCount]))
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,tolerance: .standard)
            return try #require(try prepared.originalIntersectionNativeSpans(over: box,tolerance: .standard,consumeWork: {}).first)
        }
        let a = try owner(first), b = try owner(second)
        let firstLaw = try OriginalRationalSurfacePolynomial(source: first,native: a,
            domain: .init(u: a.uBounds,v: a.vBounds),view: .init(x: 0,y: 0,z: 1),tolerance: .standard,usage: &budget)
        let secondLaw = try OriginalRationalSurfacePolynomial(source: second,native: b,
            domain: .init(u: b.uBounds,v: b.vBounds),view: .init(x: 0,y: 0,z: 1),tolerance: .standard,usage: &budget)
        let system = try OriginalRationalIntersectionSystem(first: firstLaw,second: secondLaw,usage: &budget)
        let domains = try [OriginalRationalParameterDomain(a.uBounds,usage: &budget),.init(a.vBounds,usage: &budget),
            .init(b.uBounds,usage: &budget),.init(b.vBounds,usage: &budget)]
        return .init(firstOwner: a,secondOwner: b,first: firstLaw,second: secondLaw,system: system,nativeDomains: domains)
    }
    @Test(.timeLimit(.minutes(1)))
    func closedCornerIdentityAndNegativeOrientation() throws {
        for zero in 0..<4 { for sign in [-1.0,1] {
            var values = [1.0,2,3,4];values[zero] = 0
            var budget = usage();let original = try chart(values: values,sign: sign,usage: &budget)
            let proof = try #require(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &budget))
            try proof.validate(chart: original,usage: &budget)
            #expect(proof.equationIndex == 2 && proof.targetRole == 1 && proof.zeroCorner == zero)
            #expect(proof.orientation == (sign < 0 ? -1 : 1))
            #expect(proof.cornerValues.filter { $0.isZero }.count == 1)
            #expect(proof.cornerValues.allSatisfy { !$0.isNegative })
            #expect(try proof.orientedNumerator.subtracting(proof.reconstruction,usage: &budget).isZero)
            #expect(try proof.rawEquationIdentity.matches(original.system.equations[2],usage: &budget))
            var basisSum = ExactBivariatePolynomial.zero
            for basis in proof.basis { basisSum = try basisSum.adding(basis,usage: &budget) }
            #expect(try basisSum.subtracting(.constant(.one,usage: &budget),usage: &budget).isZero)
            let cornerU = proof.nativeBounds[zero % 2],cornerV = proof.nativeBounds[2 + zero / 2]
            for factor in proof.factors { #expect(try factor.evaluated(atU: cornerU,v: cornerV,usage: &budget).isZero) }
            for u in [4.0,4.5,5] { for v in [-2.0,0.5,3] {
                let exactU = try ExactRationalCoefficient.originalDouble(u,usage: &budget)
                let exactV = try ExactRationalCoefficient.originalDouble(v,usage: &budget)
                let n = try proof.orientedNumerator.evaluated(atU: exactU,v: exactV,usage: &budget)
                let firstZero = try proof.factors[0].evaluated(atU: exactU,v: exactV,usage: &budget).isZero
                let secondZero = try proof.factors[1].evaluated(atU: exactU,v: exactV,usage: &budget).isZero
                #expect(!n.isNegative && n.isZero == (firstZero && secondZero))
                #expect(try original.second.homogeneous[3].evaluated(atU: exactU,v: exactV,usage: &budget).isPositive)
                for basis in proof.basis { #expect(try !basis.evaluated(atU: exactU,v: exactV,usage: &budget).isNegative) }
            } }
        } }
    }
    @Test(.timeLimit(.minutes(1)))
    func higherDegreeRemainderDeclinesFullIdentity() throws {
        var budget = usage();let original = try chart(higherDegree: true,usage: &budget)
        // The same four corner values propose a bilinear identity, but the original interior coefficient refutes it.
        #expect(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &budget) == nil)
    }
    @Test(.timeLimit(.minutes(1)))
    func extraZeroCornerAndOppositeSignDecline() throws {
        var budget = usage()
        for values in [[1.0,0,0,1],[1.0,0,-1,1]] {
            let original = try chart(values: values,usage: &budget)
            #expect(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &budget) == nil)
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func retainedOriginalOwnerAndDomainRejectForeignBinding() throws {
        var budget = usage()
        let proof = try {
            let temporary = try chart(usage: &budget)
            return try #require(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: temporary,usage: &budget))
        }()
        let original = try chart(usage: &budget),foreign = try chart(constant: 3,usage: &budget)
        try proof.validate(chart: original,usage: &budget)
        do { try proof.validate(chart: foreign,usage: &budget);Issue.record("Foreign source replaced closed-chart corner authority.") }
        catch let error as KernelError { #expect(error.code == .intersectionFailure) }
        let changedOwner = NativeSurfaceSurfaceSourceChart(firstOwner: foreign.firstOwner,secondOwner: original.secondOwner,
            first: original.first,second: original.second,system: original.system,nativeDomains: original.nativeDomains)
        do { try proof.validate(chart: changedOwner,usage: &budget);Issue.record("Foreign Native owner replaced corner evidence.") }
        catch let error as KernelError { #expect(error.code == .invalidInput) }
        var domains = original.nativeDomains
        domains[2] = try .init(lower: .originalDouble(4,usage: &budget),upper: .originalDouble(4.5,usage: &budget),usage: &budget)
        let changed = NativeSurfaceSurfaceSourceChart(firstOwner: original.firstOwner,secondOwner: original.secondOwner,
            first: original.first,second: original.second,system: original.system,nativeDomains: domains)
        do { try proof.validate(chart: changed,usage: &budget);Issue.record("A requested subdomain replaced the retained full Native chart.") }
        catch let error as KernelError { #expect(error.code == .intersectionFailure) }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentAdmissionAndFinalDeclineCancellationPropagate() async throws {
        var budget = usage();let original = try chart(usage: &budget)
        var noWork = OriginalRelationUsage(consumeWork: { _ in throw Refusal.work },retainStorage: { _ in },visitCell: { _ in },visitCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &noWork);Issue.record("Work refusal became corner-proof absence.") }
        catch Refusal.work {}
        var noStorage = OriginalRelationUsage(consumeWork: { _ in },retainStorage: { _ in throw Refusal.storage },visitCell: { _ in },visitCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &noStorage);Issue.record("Storage refusal became corner-proof absence.") }
        catch Refusal.storage {}
        let outside = try chart(higherDegree: true,usage: &budget),count = Mutex(0)
        var measured = OriginalRelationUsage(consumeWork: { _ in count.withLock { $0 += 1 } },retainStorage: { _ in },visitCell: { _ in },visitCoefficientCell: { _ in })
        #expect(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: outside,usage: &measured) == nil)
        let last = count.withLock { $0 };#expect(last > 0)
        let current = Mutex(0),cancelledAtFinal = Mutex(false)
        let task = Task {
            var cancelling = OriginalRelationUsage(consumeWork: { _ in
                if current.withLock({ $0 += 1;return $0 }) == last {
                    cancelledAtFinal.withLock { $0 = true };withUnsafeCurrentTask { $0?.cancel() }
                }
            },retainStorage: { _ in },visitCell: { _ in },visitCoefficientCell: { _ in })
            return try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: outside,usage: &cancelling)
        }
        do { _ = try await task.value;Issue.record("Final callback cancellation became normal corner-proof decline.") }
        catch is CancellationError {}
        #expect(cancelledAtFinal.withLock { $0 } && current.withLock { $0 } == last)
        #expect(try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: original,usage: &budget) != nil)
    }
}
