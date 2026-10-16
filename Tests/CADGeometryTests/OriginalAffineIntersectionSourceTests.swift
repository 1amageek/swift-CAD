import Testing
import Synchronization
import CADCore
@testable import CADGeometry

@Suite("Original affine Native intersection sources")
struct OriginalAffineIntersectionSourceTests {
    private final class Budget: Sendable {
        private struct State: Sendable { var work = 0; var storage = 0; var storageCalls = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumStorage: Int
        let cancelAtStorageCall: Int?
        init(work: Int = 10_000_000, storage: Int = 10_000_000, cancelAtStorageCall: Int? = nil) {
            maximumWork = work; maximumStorage = storage; self.cancelAtStorageCall = cancelAtStorageCall
        }
        var spent: (work: Int, storage: Int, storageCalls: Int) {
            state.withLock { ($0.work, $0.storage, $0.storageCalls) }
        }
        func makeExecution() throws -> OriginalQueryExecution {
                let budget = try OriginalQueryBudget(consumeWorkUnits: { count in
                    try self.state.withLock { state in
                        guard count <= self.maximumWork - state.work else { throw Self.exhausted() }
                        state.work += count
                    }
                }, consumeStorageBytes: { bytes in
                    let count = try geometryTestStorageWords(bytes)
                    let cancel = try self.state.withLock { state in
                        guard count <= self.maximumStorage - state.storage else { throw Self.exhausted() }
                        state.storage += count; state.storageCalls += 1
                        return self.cancelAtStorageCall == state.storageCalls
                    }
                    if cancel { withUnsafeCurrentTask { $0?.cancel() } }
                })
                return OriginalQueryExecution(budget: budget,
                    limits: try .init(maximumValueDepth: 24, maximumCoefficientDepth: 24))
        }
        private static func exhausted() -> KernelError {
            .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Affine source fixture exhausted caller admission.")
        }
    }
    private let tolerance = ModelingTolerance.standard
    private func surface() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [-2,-2,6,6], vKnots: [3,3,5,5],
            controlPoints: [[.init(x: -2,y: 1,z: 3), .init(x: 4,y: -1,z: 2)],
                            [.init(x: 1,y: 2,z: -2), .init(x: 3,y: 5,z: 1)]],
            weights: [[1,2],[3,4]])
    }
    private func box() throws -> SurfaceParameterBox {
        .init(u: try .init(lower: -2, upper: 6), v: try .init(lower: 3, upper: 5))
    }
    private func transform() throws -> AffineTransform3D {
        try .init(basisX: .init(x: 3,y: 0,z: 0), basisY: .init(x: 2,y: -2,z: 0),
            basisZ: .init(x: 0,y: 1,z: 1), translation: .init(x: 5,y: -7,z: 11))
    }
    private func span(_ source: BSplineSurface3D, over domain: SurfaceParameterBox,
        usage: inout OriginalQueryExecution) throws -> PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan {
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: tolerance,
            using: &usage)
        let spans = try prepared.originalNativeSpans(over: domain, tolerance: tolerance, maximumSpanCount: 1,
            using: &usage)
        return try #require(spans.first)
    }
    private func image(_ source: Surface3D, operations: [OriginalAffineOperation],
        usage: inout OriginalQueryExecution) throws -> OriginalAffineWordSurface3D {
        let word = try OriginalAffineOperationWord(factors: operations, tolerance: tolerance,
            maximumDepth: 24, usage: &usage)
        return try .init(source: source, operationWord: word, tolerance: tolerance,
            remainingSourceDepth: 4, maximumSubdivisionDepth: 8, maximumAlgebraicDepth: 24, usage: &usage)
    }
    private func checkpoint(_ image: OriginalAffineWordSurface3D,
        span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        domain: SurfaceParameterBox, depth: Int = 4, budget: Budget) throws -> OriginalAffineSurfaceIntersectionSource {
        var usage = try budget.makeExecution()
        return try .init(image: image, nativeSpan: span, domain: domain, tolerance: tolerance,
            remainingSourceDepth: depth, maximumAlgebraicDepth: 24, usage: &usage)
    }
    private func scalar(_ value: Double, usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        try .originalDouble(value, usage: &usage)
    }
    private func polynomial(_ a: Double, _ b: Double, _ c: Double, _ d: Double,
        s: ExactBivariatePolynomial, t: ExactBivariatePolynomial,
        usage: inout OriginalQueryExecution) throws -> ExactBivariatePolynomial {
        try .constant(scalar(a, usage: &usage), usage: &usage)
            .adding(s.scaled(by: scalar(b, usage: &usage), usage: &usage), usage: &usage)
            .adding(t.scaled(by: scalar(c, usage: &usage), usage: &usage), usage: &usage)
            .adding(s.multiplied(by: t, usage: &usage).scaled(by: scalar(d, usage: &usage), usage: &usage), usage: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactForwardInverseAndIdentityPreserveWeightedNativeLaw() throws {
        let preparation = Budget(); var usage = try preparation.makeExecution()
        let source = surface(), domain = try box(), native = try span(source, over: domain, usage: &usage)
        let action = try transform()
        let forward = try image(.bSpline(source), operations: [.forward(action)], usage: &usage)
        let inverse = try image(.bSpline(source), operations: [.inverse(action)], usage: &usage)
        let identity = try image(.bSpline(source), operations: [.forward(action), .inverse(action)], usage: &usage)
        let f = try checkpoint(forward, span: native, domain: domain, budget: Budget())
        let i = try checkpoint(inverse, span: native, domain: domain, budget: Budget())
        let unchanged = try checkpoint(identity, span: native, domain: domain, budget: Budget())
        // Independently authored Bernstein expansion in s=(u+2)/8 and t=(v-3)/2.
        let s = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .adding(.constant(scalar(2, usage: &usage), usage: &usage), usage: &usage)
            .scaled(by: scalar(1, usage: &usage).divided(by: scalar(8, usage: &usage), usage: &usage), usage: &usage)
        let t = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            .subtracting(.constant(scalar(3, usage: &usage), usage: &usage), usage: &usage)
            .scaled(by: scalar(1, usage: &usage).divided(by: scalar(2, usage: &usage), usage: &usage), usage: &usage)
        let hx = try polynomial(-2,10,5,-1,s:s,t:t,usage:&usage)
        let hy = try polynomial(1,-3,5,17,s:s,t:t,usage:&usage)
        let hz = try polynomial(3,1,-9,9,s:s,t:t,usage:&usage)
        let w = try polynomial(1,1,2,0,s:s,t:t,usage:&usage)
        #expect(unchanged.homogeneous == [hx,hy,hz,w])
        #expect(try f.homogeneous[0] == hx.scaled(by: scalar(3,usage:&usage),usage:&usage)
            .adding(hy.scaled(by: scalar(2,usage:&usage),usage:&usage),usage:&usage)
            .adding(w.scaled(by: scalar(5,usage:&usage),usage:&usage),usage:&usage))
        #expect(try f.homogeneous[1] == hy.scaled(by: scalar(-2,usage:&usage),usage:&usage)
            .adding(hz,usage:&usage).subtracting(w.scaled(by: scalar(7,usage:&usage),usage:&usage),usage:&usage))
        #expect(try f.homogeneous[2] == hz.adding(w.scaled(by: scalar(11,usage:&usage),usage:&usage),usage:&usage))
        let third = try scalar(1,usage:&usage).divided(by: scalar(3,usage:&usage),usage:&usage)
        #expect(try i.homogeneous[0] == hx.adding(hy,usage:&usage).subtracting(hz,usage:&usage)
            .adding(w.scaled(by: scalar(13,usage:&usage),usage:&usage),usage:&usage).scaled(by: third,usage:&usage))
        #expect(try i.homogeneous[1] == hz.subtracting(hy,usage:&usage).scaled(by: scalar(0.5,usage:&usage),usage:&usage)
            .subtracting(w.scaled(by: scalar(9,usage:&usage),usage:&usage),usage:&usage))
        #expect(try i.homogeneous[2] == hz.subtracting(w.scaled(by: scalar(11,usage:&usage),usage:&usage),usage:&usage))
        #expect(f.denominator == w && i.denominator == w)
        #expect(f.image == forward && f.preparedWord.source == forward.operationWord)
        #expect(f.nativeLaw.source == source && f.nativeSpan.uSpanIndex == 1 && f.nativeSpan.vSpanIndex == 1)
        #expect(f.nativeLaw.domain == domain)
        #expect(try f.uDomain.lower == scalar(-2,usage:&usage) && f.uDomain.upper == scalar(6,usage:&usage))
        #expect(try f.vDomain.lower == scalar(3,usage:&usage) && f.vDomain.upper == scalar(5,usage:&usage))
        #expect(f.image.uDomain == Surface3D.bSpline(source).uDomain && f.image.vDomain == Surface3D.bSpline(source).vDomain)
    }

    @Test(.timeLimit(.minutes(1)))
    func threeAndFourVariableAdaptersRetainExactEquationsAndGuards() throws {
        let budget = Budget(); var usage = try budget.makeExecution()
        let source = surface(), domain = try box(), native = try span(source,over:domain,usage:&usage)
        let image = try image(.bSpline(source),operations:[.forward(transform())],usage:&usage)
        let affine = try checkpoint(image,span:native,domain:domain,budget:budget)
        let point = Point3D(x:1,y:-6,z:14)
        let rawCurve = BSplineCurve3D(degree:1,knots:[-5,-5,-1,-1],controlPoints:[point,point],weights:[1,2])
        let curve = try OriginalRationalCurvePolynomial(source:rawCurve,spanIndex:1,tolerance:tolerance,usage:&usage)
        let cs = try OriginalAffineIntersectionEquations(curve:curve,surface:affine,usage:&usage)
        let csCoordinates = try [-3.0,-2,3].map { try scalar($0,usage:&usage) }
        for equation in cs.equations { #expect(try equation.evaluated(at:csCoordinates,usage:&usage).isZero) }
        for guardLaw in cs.denominatorGuards { #expect(try guardLaw.evaluated(at:csCoordinates,usage:&usage).isPositive) }
        let off = try [-3.0,6,3].map { try scalar($0,usage:&usage) }
        #expect(try !cs.equations[0].evaluated(at:off,usage:&usage).isZero)
        #expect(cs.variableCount == 3 && cs.curve?.source == rawCurve && cs.affineSurface.image == image)
        #expect(try cs.domains[0].lower == scalar(-5,usage:&usage) && cs.domains[1] == affine.uDomain && cs.domains[2] == affine.vDomain)
        // The Native surface validator requires positive degrees on both axes.
        // This regular patch has the exact original point at (11,-2).
        let other = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[10,10,12,12],vKnots:[-4,-4,0,0],
            controlPoints:[
                [.init(x:0,y:-7,z:14),.init(x:2,y:-7,z:14)],
                [.init(x:0,y:-5,z:14),.init(x:2,y:-5,z:14)]],weights:[[2,2],[2,2]])
        let otherDomain = SurfaceParameterBox(u:try .init(lower:10,upper:12),v:try .init(lower:-4,upper:0))
        let otherSpan = try span(other,over:otherDomain,usage:&usage)
        let otherLaw = try OriginalRationalSurfacePolynomial(source:other,native:otherSpan,domain:otherDomain,
            view:.unitZ,tolerance:tolerance,usage:&usage)
        let ssi = try OriginalAffineIntersectionEquations(first:affine,second:otherLaw,usage:&usage)
        let ssiCoordinates = try [-2.0,3,11,-2].map { try scalar($0,usage:&usage) }
        for equation in ssi.equations { #expect(try equation.evaluated(at:ssiCoordinates,usage:&usage).isZero) }
        for guardLaw in ssi.denominatorGuards { #expect(try guardLaw.evaluated(at:ssiCoordinates,usage:&usage).isPositive) }
        #expect(ssi.variableCount == 4 && ssi.otherSurface?.source == other)
        #expect(ssi.domains[0] == affine.uDomain && ssi.domains[1] == affine.vDomain)
        #expect(try ssi.domains[2].lower == scalar(10,usage:&usage) && ssi.domains[3].upper == .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func independentInvalidUnsupportedAndCallerBudgetFailures() throws {
        let budget = Budget(); var usage = try budget.makeExecution()
        let domain = try box(), source = surface(), native = try span(source,over:domain,usage:&usage)
        let original = try image(.bSpline(source),operations:[.forward(transform())],usage:&usage)
        let measured = Budget()
        _ = try checkpoint(original,span:native,domain:domain,budget:measured)
        let cost = measured.spent
        _ = try checkpoint(original,span:native,domain:domain,budget:Budget(work:cost.work,storage:cost.storage))
        for limits in [(0,cost.storage),(cost.work,cost.storage-1)] {
            #expect { _ = try checkpoint(original,span:native,domain:domain,budget:Budget(work:limits.0,storage:limits.1)) }
            throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }
        }
        #expect { _ = try checkpoint(original,span:native,domain:domain,depth:0,budget:Budget()) }
        throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }
        let outside = SurfaceParameterBox(u:try .init(lower:-3,upper:6),v:domain.v)
        #expect { _ = try checkpoint(original,span:native,domain:outside,budget:Budget()) }
        throws: { ($0 as? KernelError)?.code == .invalidInput }
        var changed = source; changed.controlPoints[0][0].x = 99
        let mismatched = try image(.bSpline(changed),operations:[.forward(transform())],usage:&usage)
        #expect { _ = try checkpoint(mismatched,span:native,domain:domain,budget:Budget()) }
        throws: { ($0 as? KernelError)?.code == .invalidInput }
        let plane = try image(.plane(.init(origin:.origin,normal:.unitZ)),operations:[.forward(transform())],usage:&usage)
        #expect { _ = try checkpoint(plane,span:native,domain:domain,budget:Budget()) }
        throws: { ($0 as? KernelError)?.code == .unsupportedCapability }
        let normalized = OriginalNormalizedAffineSource(family:.cartesian,location:.zero,
            axis1:.init(x:1,y:1,z:0),axis2:.init(x:-1,y:1,z:0),axis3:.unitZ,scale:1,
            lengthGain:.one,adjustments:[])
        let algebraic = try image(.bSpline(source),operations:[.normalizedForward(normalized)],usage:&usage)
        #expect { _ = try checkpoint(algebraic,span:native,domain:domain,budget:Budget()) }
        throws: { ($0 as? KernelError)?.code == .unsupportedCapability }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceOwnersOutliveInputReleaseAndFinalCancellationIsAtomic() async throws {
        func released() throws -> OriginalAffineSurfaceIntersectionSource {
            let budget = Budget(); var usage = try budget.makeExecution()
            var source = surface()
            let domain = try box(), native = try span(source,over:domain,usage:&usage)
            let original = try image(.bSpline(source),operations:[.inverse(transform())],usage:&usage)
            let issued = try checkpoint(original,span:native,domain:domain,budget:budget)
            source.controlPoints[0][0] = .init(x:999,y:999,z:999)
            return issued
        }
        let retained = try released()
        #expect(retained.nativeLaw.source == surface())
        #expect(retained.image.operationWord.factors.count == 1)
        let budget = Budget()
        _ = try checkpoint(retained.image,span:retained.nativeSpan,domain:retained.nativeLaw.domain,budget:budget)
        let cancel = Budget(cancelAtStorageCall:budget.spent.storageCalls)
        let task = Task {
            try checkpoint(retained.image,span:retained.nativeSpan,domain:retained.nativeLaw.domain,budget:cancel)
        }
        do { _ = try await task.value; Issue.record("Cancelled source publication must fail.") }
        catch where geometryTestIsCancelled(error) {}
        #expect(cancel.spent.storageCalls == budget.spent.storageCalls)
    }
}
