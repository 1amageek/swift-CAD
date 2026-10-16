import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Original closed Native chart injection", .serialized)
struct NativeSurfaceChartInjectionTests {
    private enum Refusal: Error { case work, storage }
    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }
    private func strip(reversed: Bool = false, shiftedV: Bool = false,
        weights: [[Double]] = [[1,2,1],[2,4,2]]) -> BSplineSurface3D {
        let xs = reversed ? [2.0,1,0] : [0.0,1,2]
        let ys = shiftedV ? [2.0,3] : [0.0,1]
        return .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,2,2],
            vKnots: [ys[0],ys[0],ys[1],ys[1]],
            controlPoints: ys.map { y in xs.map { x in .init(x: x,y: y,z: 0) } }, weights: weights)
    }
    private func charts<A: ExactScalarAdmission & ~Copyable>(_ surface: BSplineSurface3D, usage budget: inout A) throws -> [NativeSurfaceSurfaceSourceChart] {
        let box = SurfaceParameterBox(u: try .init(lower: surface.uKnots[surface.uDegree], upper: surface.uKnots[surface.uControlPointCount]),
            v: try .init(lower: surface.vKnots[surface.vDegree], upper: surface.vKnots[surface.vControlPointCount]))
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: .standard, using: &budget)
        let owners = try prepared.originalIntersectionNativeSpans(over: box, tolerance: .standard, using: &budget)
        var result: [NativeSurfaceSurfaceSourceChart] = []
        for owner in owners {
            let domain = SurfaceParameterBox(u: owner.uBounds, v: owner.vBounds)
            let law = try OriginalRationalSurfacePolynomial(source: surface, native: owner,
                domain: domain, view: .init(x: 0,y: 0,z: 1), tolerance: .standard, usage: &budget)
            let system = try OriginalRationalIntersectionSystem(first: law, second: law, usage: &budget)
            let native = try [OriginalRationalParameterDomain(owner.uBounds, usage: &budget),
                .init(owner.vBounds, usage: &budget), .init(owner.uBounds, usage: &budget), .init(owner.vBounds, usage: &budget)]
            result.append(.init(firstOwner: owner, secondOwner: owner, first: law, second: law,
                system: system, nativeDomains: native))
        }
        return result
    }
    private func value<A: ExactScalarAdmission & ~Copyable>(_ polynomial: ExactBivariatePolynomial, u: Double, v: Double,
        usage budget: inout A) throws -> ExactRationalCoefficient {
        try polynomial.evaluated(atU: .originalDouble(u, usage: &budget),
            v: .originalDouble(v, usage: &budget), usage: &budget)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactWeightedClosedEndpointsAndReversedNegativeDenominators() throws {
        for reversed in [false,true] {
            var budget = try usage()
            let original = try charts(strip(reversed: reversed, shiftedV: true), usage: &budget)
            let proof = try geometryTestRequire(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original, usage: &budget))
            try proof.validate(charts: original, usage: &budget)
            #expect(proof.maps.count == 2)
            for index in original.indices {
                let chart = original[index], map = proof.maps[index].first
                #expect(map.u.xyzAxis != map.v.xyzAxis)
                #expect(map.u.lowerDenominator.isNegative && map.u.upperDenominator.isNegative)
                #expect(!map.u.determinant.isZero && !map.v.determinant.isZero)
                #expect(try map.u.leftIdentity.subtracting(map.u.rightIdentity, usage: &budget).isZero)
                #expect(try map.v.leftIdentity.subtracting(map.v.rightIdentity, usage: &budget).isZero)
                for u in [chart.first.domain.u.lower, chart.first.domain.u.upper] {
                    for v in [chart.first.domain.v.lower, chart.first.domain.v.upper] {
                        let w = try value(chart.first.homogeneous[3], u: u,v: v,usage: &budget)
                        #expect(w.isPositive)
                        for coordinate in [map.u,map.v] {
                            let x = try value(chart.first.homogeneous[coordinate.xyzAxis], u: u,v: v,usage: &budget).divided(by: w, usage: &budget)
                            let n = try value(coordinate.numerator,u: u,v: v,usage: &budget)
                            let d = try value(coordinate.denominator,u: u,v: v,usage: &budget)
                            #expect(!d.isZero)
                            #expect(try n.divided(by: d,usage: &budget) == x)
                        }
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func noninjectiveDegenerateAndNonseparableMapsDeclineProof() throws {
        let folded = BSplineSurface3D(uDegree: 2,vDegree: 1,uKnots: [0,0,0,1,1,1],vKnots: [0,0,1,1],
            controlPoints: [0.0,1].map { y in [0.0,0.5,0].map { x in .init(x: x,y: y,z: 0) } })
        let collapsed = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],
            controlPoints: [0.0,1].map { y in [.init(x: 0,y: y,z: 0),.init(x: 0,y: y,z: 0)] })
        let coupled = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0),.init(x: 1,y: 1,z: 0)]], weights: [[1,2],[3,5]])
        for source in [folded,collapsed,coupled] {
            var budget = try usage(); let original = try charts(source, usage: &budget)
            #expect(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original, usage: &budget) == nil)
            let regular = try charts(strip(), usage: &budget)[0], opposite = original[0]
            let system = try OriginalRationalIntersectionSystem(first: regular.first, second: opposite.second, usage: &budget)
            let mixedDomains = [regular.nativeDomains[0],regular.nativeDomains[1],opposite.nativeDomains[2],opposite.nativeDomains[3]]
            let mixed = NativeSurfaceSurfaceSourceChart(firstOwner: regular.firstOwner, secondOwner: opposite.secondOwner,
                first: regular.first, second: opposite.second, system: system, nativeDomains: mixedDomains)
            #expect(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: [regular,mixed], usage: &budget) == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func retainedProofRejectsForeignSourceOwnerAndDomainAfterInputRelease() throws {
        var budget = try usage()
        var input = strip()
        let proof: NativeSurfaceSurfaceChartInjectionProof = try {
            let temporary = try charts(input,usage: &budget)
            return try geometryTestRequire(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: temporary,usage: &budget))
        }()
        input = strip(reversed: true)
        let original = try charts(strip(),usage: &budget)
        let foreign = try charts(input,usage: &budget)
        try proof.validate(charts: original,usage: &budget)
        do { try proof.validate(charts: foreign,usage: &budget); Issue.record("Foreign source replaced the retained chart map.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .intersectionFailure) }
        let chart = original[0]
        let foreignOwner = NativeSurfaceSurfaceSourceChart(firstOwner: foreign[0].firstOwner,
            secondOwner: chart.secondOwner,first: chart.first,second: chart.second,
            system: chart.system,nativeDomains: chart.nativeDomains)
        do { try proof.validate(charts: [foreignOwner,original[1]],usage: &budget); Issue.record("Foreign source owner replaced the retained native owner.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .invalidInput) }
        var domains = chart.nativeDomains
        domains[0] = try .init(lower: .zero,upper: .zero,usage: &budget)
        let changed = NativeSurfaceSurfaceSourceChart(firstOwner: chart.firstOwner,secondOwner: chart.secondOwner,
            first: chart.first,second: chart.second,system: chart.system,nativeDomains: domains)
        do { try proof.validate(charts: [changed,original[1]],usage: &budget); Issue.record("A singleton silently replaced the full native proof domain.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .intersectionFailure) }
        let kept = proof.maps[1].first
        #expect(try value(kept.u.denominator,u: 2,v: 1,usage: &budget).canonicalSign != 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalZeroDenominatorSourceFailsBeforeEligibility() throws {
        var budget = try usage()
        do {
            let original = try charts(strip(weights: [[0,0,0],[0,0,0]]),usage: &budget)
            _ = try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original,usage: &budget)
            Issue.record("Original zero denominator source was admitted as eligibility or absence.")
        } catch let error as GeometryError {
            guard case .invalidDistance(let value) = error else { throw error }
            #expect(value == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proofWorkStorageAndCancellationPropagateAtomically() async throws {
        var budget = try usage(); let original = try charts(strip(),usage: &budget)
        var noWork = GeometryTestScalarRecorder(observeWork: { _ in throw Refusal.work },observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original,usage: &noWork); Issue.record("Work refusal became proof absence.") }
        catch Refusal.work {}
        var noStorage = GeometryTestScalarRecorder(observeWork: { _ in },observeStorageWords: { _ in throw Refusal.storage },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        do { _ = try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original,usage: &noStorage); Issue.record("Storage refusal became proof absence.") }
        catch Refusal.storage {}
        let charged = Mutex(0)
        let task = Task {
            var cancelled = GeometryTestScalarRecorder(observeWork: { _ in },observeStorageWords: { _ in
                charged.withLock { $0 += 1 }; withUnsafeCurrentTask { $0?.cancel() }
            },observeValueCell: { _ in },observeCoefficientCell: { _ in })
            return try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original,usage: &cancelled)
        }
        do { _ = try await task.value; Issue.record("Cancelled proof admission returned eligibility or absence.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(charged.withLock { $0 } > 0)

        // A valid collapsed source declines after its last exact-work callback.
        let collapsed = BSplineSurface3D(uDegree: 1,vDegree: 1,
            uKnots: [0,0,1,1],vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: 0),.init(x: 0,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0),.init(x: 0,y: 1,z: 0)]])
        let collapsedCharts = try charts(collapsed,usage: &budget)
        let callbackCount = Mutex(0)
        var measured = GeometryTestScalarRecorder(observeWork: { _ in callbackCount.withLock { $0 += 1 } },
            observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
        #expect(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: collapsedCharts,usage: &measured) == nil)
        let finalCallback = callbackCount.withLock { $0 }
        #expect(finalCallback > 0)
        let currentCallback = Mutex(0), cancelledAtDecline = Mutex(false)
        let decliningTask = Task {
            var declining = GeometryTestScalarRecorder(observeWork: { _ in
                if currentCallback.withLock({ $0 += 1; return $0 }) == finalCallback {
                    cancelledAtDecline.withLock { $0 = true }
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            },observeStorageWords: { _ in },observeValueCell: { _ in },observeCoefficientCell: { _ in })
            return try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: collapsedCharts,usage: &declining)
        }
        do { _ = try await decliningTask.value; Issue.record("Final work cancellation became normal proof decline.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancelledAtDecline.withLock { $0 })
        #expect(currentCallback.withLock { $0 } == finalCallback)
        let proof = try geometryTestRequire(try NativeSurfaceSurfaceChartInjectionProof.prepare(charts: original,usage: &budget))
        try proof.validate(charts: original,usage: &budget)
    }
}
