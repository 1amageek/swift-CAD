import CADCore
@testable import CADGeometry
import Testing

@Suite("Exact periodic tensor editing")
struct PeriodicBSplineSurfaceEditingTests {
    private let tolerance = ModelingTolerance.standard

    private func surface(degree: Int = 3, uPeriodic: Bool = true, vPeriodic: Bool = true,
                         rational: Bool = true, repeated: Bool = false) throws -> BSplineSurface3D {
        let count = repeated ? 5 : 4
        let uCount = uPeriodic ? count : degree + 1
        let vCount = vPeriodic ? count : degree + 1
        let points = (0..<vCount).map { j in
            (0..<uCount).map { i in Point3D(x: Double(i * i - j), y: Double(j * j + i),
                z: Double(i * j + i - j) * 0.3) }
        }
        let weights = (0..<vCount).map { j in
            (0..<uCount).map { i in rational ? 1 + Double(i + j + i * j) * 0.1 : 1 }
        }
        let cycle: [Double] = repeated ? [0, 0, 1, 2, 3, 4] : [0, 0.5, 2, 3, 4]
        let open = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
        return try .periodic(uDegree: degree, vDegree: degree,
            uKnots: uPeriodic ? cycle : open, vKnots: vPeriodic ? cycle : open,
            controlPoints: points, weights: weights, isUPeriodic: uPeriodic,
            isVPeriodic: vPeriodic, tolerance: tolerance)
    }

    private func check(_ actual: BSplineSurface3D, _ source: BSplineSurface3D,
                       u: Double, v: Double, second: Bool = true,
                       using execution: inout OriginalQueryExecution) throws {
        let a = try actual.surfaceDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        let b = try source.surfaceDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
        #expect((a.position - b.position).length < 2e-10)
        #expect((a.tangentU - b.tangentU).length < 2e-9)
        #expect((a.tangentV - b.tangentV).length < 2e-9)
        #expect((a.secondDerivativeUV - b.secondDerivativeUV).length < 2e-8)
        if second {
            #expect((a.secondDerivativeUU - b.secondDerivativeUU).length < 2e-8)
            #expect((a.secondDerivativeVV - b.secondDerivativeVV).length < 2e-8)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func seamCrossingAndMultiplePeriodsRetainTheTensorLocusAndMixedJets() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        for rational in [false, true] {
            let source = try surface(rational: rational)
                .changingPeriodicOrigin(direction: .u, to: 3.25, tolerance: tolerance)
                .changingPeriodicOrigin(direction: .v, to: -1.25, tolerance: tolerance)
            for (u0, u1, v0, v1) in [(3.25, 4.75, 3.5, 4.5), (-4.25, 8.75, -0.25, 8.25), (0, 4, 0, 4)] {
                let trimmed = try source.trimmed(uFrom: u0, uTo: u1, vFrom: v0, vTo: v1, tolerance: tolerance)
                #expect(!trimmed.isUPeriodic && !trimmed.isVPeriodic)
                #expect(trimmed.uPeriodicOrigin == nil && trimmed.vPeriodicOrigin == nil)
                #expect(trimmed.uDomain == .closed(u0, u1) && trimmed.vDomain == .closed(v0, v1))
                #expect(trimmed.uKnots.prefix(4).allSatisfy { $0 == u0 })
                #expect(trimmed.vKnots.suffix(4).allSatisfy { $0 == v1 })
                for j in 0...12 {
                    for i in 0...12 {
                        try check(trimmed, source, u: u0 + (u1 - u0) * Double(i) / 12,
                            v: v0 + (v1 - v0) * Double(j) / 12, using: &execution)
                    }
                }
            }
            #expect(source.isUPeriodic && source.isVPeriodic && source.uPeriodicOrigin == 3.25)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bothRefinementDirectionsRetainCyclesOriginsAndTranslatedRepresentatives() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        for rational in [false, true] {
            let source = try surface(rational: rational).changingPeriodicOrigin(direction: .v, to: 3.25, tolerance: tolerance)
            for direction: SurfaceParameterDirection in [.u, .v] {
                for value in [0.0, 1.25, 4.0, -8.0, 9.25] {
                    let refined = try source.insertingKnot(direction: direction, value: value, tolerance: tolerance)
                    #expect(refined.isUPeriodic && refined.isVPeriodic)
                    #expect(refined.uPeriodicOrigin == source.uPeriodicOrigin && refined.vPeriodicOrigin == 3.25)
                    #expect(refined.uDomain == source.uDomain && refined.vDomain == source.vDomain)
                    #expect(refined.uControlPointCount == source.uControlPointCount + (direction == .u ? 1 : 0))
                    #expect(refined.vControlPointCount == source.vControlPointCount + (direction == .v ? 1 : 0))
                    for j in 0...8 {
                        for i in 0...8 {
                            try check(refined, source, u: -3.75 + Double(i), v: 0.25 + Double(j), using: &execution)
                        }
                    }
                }
                let a = try source.insertingKnot(direction: direction, value: 1.25, tolerance: tolerance)
                let b = try source.insertingKnot(direction: direction, value: 9.25, tolerance: tolerance)
                #expect(a == b)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func onePeriodicAxisAndNonClampedOpenAxisRestrictExactly() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        for (uPeriodic, vPeriodic) in [(true, false), (false, true)] {
            var source = try surface(uPeriodic: uPeriodic, vPeriodic: vPeriodic)
            let nonClamped: [Double] = [-2, -1, -0.5, 0, 1, 1.5, 2, 3]
            if uPeriodic { source.vKnots = nonClamped } else { source.uKnots = nonClamped }
            try source.validate(tolerance: tolerance)
            let u0 = uPeriodic ? 3.25 : 0.0, u1 = uPeriodic ? 4.75 : 1.0
            let v0 = vPeriodic ? 3.25 : 0.0, v1 = vPeriodic ? 4.75 : 1.0
            let trimmed = try source.trimmed(uFrom: u0, uTo: u1, vFrom: v0, vTo: v1, tolerance: tolerance)
            for j in 0...8 {
                for i in 0...8 {
                    try check(trimmed, source, u: u0 + (u1 - u0) * Double(i) / 8,
                        v: v0 + (v1 - v0) * Double(j) / 8, using: &execution)
                }
            }
            let refined = try source.insertingKnot(direction: uPeriodic ? .v : .u, value: 0.4, tolerance: tolerance)
            try check(refined, source, u: uPeriodic ? 4.25 : 0.4, v: vPeriodic ? 4.25 : 0.4, using: &execution)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedSeamsAndDegreeGreaterThanCycleCountRemainExact() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        for source in [try surface(repeated: true), try surface(degree: 5)] {
            let trimmed = try source.trimmed(uFrom: 3.25, uTo: 4.75, vFrom: -0.25, vTo: 0.75, tolerance: tolerance)
            for (u, v) in [(3.25, -0.25), (3.9, -0.1), (4, 0), (4.1, 0.1), (4.75, 0.75)] {
                try check(trimmed, source, u: u, v: v, using: &execution)
            }
            let refined = try source.insertingKnot(direction: .u, value: 0, tolerance: tolerance)
                .insertingKnot(direction: .v, value: 4, tolerance: tolerance)
            try check(refined, source, u: 4.25, v: -0.25, using: &execution)
            if source.uDegree == 3 {
                #expect(refined.periodicSeamContinuityOrder(direction: .u) == 0)
                #expect(throws: KernelError.self) { try refined.insertingKnot(direction: .u, value: 8, tolerance: tolerance) }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func tensorBudgetsAccountForAllLinesAndSimultaneouslyOwnedNets() throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let source = try surface(degree: 2)
        // One line needs 37 controls and 231 work units. Six lines need 1,386
        // work units; the output and conservative transient slots need 338 controls.
        let refine = PeriodicBSplineExpansionOptions(maximumControlPointCount: 338, maximumKnotInsertionWork: 1_386)
        let refined = try source.insertingKnot(direction: .u, value: 1.25, expansionOptions: refine, tolerance: tolerance)
        try check(refined, source, u: 1.25, v: 1.25, using: &execution)
        for options in [PeriodicBSplineExpansionOptions(maximumControlPointCount: 337),
                        .init(maximumKnotInsertionWork: 1_385), .init(maximumKnotInsertionWork: 231)] {
            do {
                _ = try source.insertingKnot(direction: .v, value: 1.25, expansionOptions: options, tolerance: tolerance)
                Issue.record("A whole-tensor refinement budget was reduced to one line.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
        // A full-cycle restriction plans two 18-control line workspaces, 108
        // intermediate and 324 output slots; its peak allowance is 576 and work 1,488.
        let trim = PeriodicBSplineExpansionOptions(maximumControlPointCount: 576, maximumKnotInsertionWork: 1_488)
        let trimmed = try source.trimmed(uFrom: 0, uTo: 4, vFrom: 0, vTo: 4, expansionOptions: trim, tolerance: tolerance)
        try check(trimmed, source, u: 1.25, v: 1.25, using: &execution)
        for options in [PeriodicBSplineExpansionOptions(maximumControlPointCount: 575),
                        .init(maximumKnotInsertionWork: 1_487), .init(maximumControlPointCount: 36)] {
            do {
                _ = try source.trimmed(uFrom: 0, uTo: 4, vFrom: 0, vTo: 4, expansionOptions: options, tolerance: tolerance)
                Issue.record("A restriction ignored total generated storage or insertion work.")
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        }
        #expect(source.uControlPointCount == 6 && source.vControlPointCount == 6)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedBoundsAndOverflowFailWithoutReturningAnEditedSurface() throws {
        let source = try surface()
        let malformed: [(Double, Double, Double, Double)] = [
            (1, 1, 0, 1), (2, 1, 0, 1), (0, 1, 2, 1), (.nan, 1, 0, 1), (0, 1, 0, .infinity),
        ]
        for (a, b, c, d) in malformed {
            do {
                _ = try source.trimmed(uFrom: a, uTo: b, vFrom: c, vTo: d, tolerance: tolerance)
                Issue.record("A malformed tensor interval produced a surface.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
        #expect(throws: KernelError.self) {
            try source.trimmed(uFrom: -1e100, uTo: 1e100, vFrom: 0, vTo: 4,
                expansionOptions: .init(maximumControlPointCount: Int.max, maximumKnotInsertionWork: Int.max), tolerance: tolerance)
        }
        let mixed = try surface(uPeriodic: false, vPeriodic: true)
        #expect(throws: KernelError.self) { try mixed.trimmed(uFrom: -0.1, uTo: 0.5, vFrom: 3.5, vTo: 4.5, tolerance: tolerance) }
        #expect(throws: KernelError.self) { try source.insertingKnot(direction: .u, value: .nan, tolerance: tolerance) }
        #expect(throws: KernelError.self) {
            try source.insertingKnot(direction: .u, value: 1.25,
                expansionOptions: .init(maximumControlPointCount: 0), tolerance: tolerance)
        }
    }
}
