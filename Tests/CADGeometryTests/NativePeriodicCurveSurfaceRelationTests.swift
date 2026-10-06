import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Finite exact periodic original native curve-surface relations", .serialized)
struct NativePeriodicCurveSurfaceRelationTests {
    private let tolerance = ModelingTolerance.standard
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in },retainStorage: { _ in },visitCell: { _ in },visitCoefficientCell: { _ in })
    }
    private func number(_ value: Double) throws -> ExactRationalCoefficient {
        var admission = usage(); return try .originalDouble(value,usage: &admission)
    }
    private func periodicCurve(overlap: Bool = false, seam: Bool = false, constant: Bool = false) -> BSplineCurve3D {
        .init(degree: 1,knots: [-1,0,1,2,3],controlPoints: (0...2).map {
            .init(x: constant ? 0.25 : overlap ? ($0 == 1 ? 1 : 0) : seam ? 0 : 0.5,
                y: seam ? 0 : 0.5,z: overlap || constant ? 0 : seam ? ($0 == 1 ? 1 : 0) : ($0 == 1 ? 1 : -1))
        },isPeriodic: true)
    }
    private func openCurve(overlap: Bool = false) -> BSplineCurve3D {
        .init(degree: 1,knots: [0,0,1,1],controlPoints: (0...1).map {
            .init(x: overlap ? Double($0) : 0.5,y: 0.5,z: overlap ? 0 : ($0 == 0 ? -1 : 1))
        })
    }
    private func surface(periodicU: Bool = false, periodicV: Bool = false, collapsed: Bool = false) -> BSplineSurface3D {
        let xs = periodicU ? [0.0,1.0,0.0] : [0.0,1.0]
        let ys = periodicV ? [0.0,1.0,0.0] : [0.0,1.0]
        return .init(uDegree: 1,vDegree: 1,uKnots: periodicU ? [-1,0,1,2,3] : [0,0,1,1],
            vKnots: periodicV ? [-1,0,1,2,3] : [0,0,1,1],
            controlPoints: ys.map { y in xs.map { .init(x: $0,y: collapsed ? 0.5 : y,z: 0) } },
            isUPeriodic: periodicU,isVPeriodic: periodicV)
    }
    @Test(.timeLimit(.minutes(1)),arguments: ["curve","surface","both"])
    func publicDefaultDomainsKeepEveryIndependentTupleAndAllRoutes(mode: String) throws {
        var source = mode == "surface" ? openCurve() : periodicCurve()
        var target = surface(periodicU: mode != "curve",periodicV: mode != "curve")
        if source.isPeriodic { source.periodicOrigin = 20 }
        if target.isUPeriodic { target.uPeriodicOrigin = 20; target.vPeriodicOrigin = -12 }
        let c = Curve3D.bSpline(source), s = Surface3D.bSpline(target), solver = DefaultCurveSurfaceIntersector()
        let ordinary = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance)
        let expected = (source.isPeriodic ? 2 : 1) * (target.isUPeriodic ? 4 : 1)
        #expect(ordinary.points.count == expected && !ordinary.hasPositiveDimensionalSolutions)
        let receipt = try #require(ordinary.originalNativePoints)
        #expect(receipt.nativeDomains[0].lower == nil ? source.isPeriodic : !source.isPeriodic)
        #expect(receipt.nativeDomains[1].lower == nil ? target.isUPeriodic : !target.isUPeriodic)
        #expect(try receipt.requestedDomains[0].lower == number(0))
        #expect(try receipt.requestedDomains[0].upper == number(source.isPeriodic ? 2 : 1))
        #expect(try receipt.requestedDomains[1].upper == number(target.isUPeriodic ? 2 : 1))
        for t in source.isPeriodic ? [0.5,1.5] : [0.5] {
            for u in target.isUPeriodic ? [0.5,1.5] : [0.5] {
                for v in target.isVPeriodic ? [0.5,1.5] : [0.5] {
                    #expect(ordinary.points.contains { $0.curveParameter == t && $0.surfaceU == u && $0.surfaceV == v })
                }
            }
        }
        let selected = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
            maximumSpanCount: 64,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in },consumeStorage: { _ in },maximumAlgebraicDepth: 32)
        #expect(selected.points == ordinary.points && selected.originalNativeRelations?.components.count == expected)
        #expect(try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance) == ordinary.points)
        #expect(try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance,
            maximumSpanCount: 64,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in },consumeStorage: { _ in },maximumAlgebraicDepth: 32) == ordinary.points)
    }
    @Test(.timeLimit(.minutes(1)))
    func negativeAndMultipleCyclesRetainAllTranslatedTuples() throws {
        let options = try CurveSurfaceIntersectionOptions(curveRange: .init(lower: -2,upper: 4),
            surfaceURange: .init(lower: -2,upper: 4))
        var source = periodicCurve(), target = surface(periodicU: true)
        source.weights = Array(repeating: 2,count: source.controlPointCount)
        target.weights = target.weights.map { Array(repeating: 3,count: $0.count) }
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(source), s = Surface3D.bSpline(target)
        let result = try solver.intersectionResult(curve: c,surface: s,options: options,tolerance: tolerance)
        let receipt = try #require(result.originalNativePoints), relation = try #require(result.originalNativeRelations)
        #expect(result.points.count == 36 && relation.components.count == 36)
        let stations = [-1.5,-0.5,0.5,1.5,2.5,3.5]
        for t in stations { for u in stations {
            #expect(result.points.contains { $0.curveParameter == t && $0.surfaceU == u && $0.surfaceV == 0.5 })
        } }
        let work = Mutex(0)
        let admitted = try solver.intersectionResult(curve: c,surface: s,options: options,tolerance: tolerance,
            maximumSpanCount: 64,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in work.withLock { $0 += 1 } },maximumAlgebraicDepth: 32)
        #expect(admitted.points == result.points)
        #expect(work.withLock { $0 } <= 262_144 * 32)
        print("Weighted periodic 36-tuple rich admitted work=\(work.withLock { $0 })")
        #expect(try solver.intersections(curve: c,surface: s,options: options,tolerance: tolerance) == result.points)
        #expect(try solver.intersections(curve: c,surface: s,options: options,tolerance: tolerance,
            maximumSpanCount: 64,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in },maximumAlgebraicDepth: 32) == result.points)
        for index in result.points.indices {
            let point = result.points[index], original = try receipt.point(at: index)
            let chart = try original.sourceChart(in: receipt)
            let tCycle = Int((point.curveParameter / 2).rounded(.down)), uCycle = Int((point.surfaceU / 2).rounded(.down))
            #expect(chart.curveCycle == tCycle && chart.surfaceUCycle == uCycle && chart.surfaceVCycle == 0)
            #expect(chart.curveTranslation == Double(tCycle) * 2 && chart.surfaceUTranslation == Double(uCycle) * 2)
            let scalar = try original.parameter(axis: 0,in: receipt)
            #expect(try scalar.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()).lower == number(point.curveParameter))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func closedSeamsAndSingletonsSelectTheRightUnwrappedOwners() throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(periodicCurve(seam: true))
        let s = Surface3D.bSpline(surface(periodicU: true,periodicV: true))
        let whole = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance)
        #expect(whole.points.count == 8)
        let receipt = try #require(whole.originalNativePoints)
        for index in whole.points.indices {
            let point = whole.points[index], chart = try receipt.point(at: index).sourceChart(in: receipt)
            #expect(chart.curveCycle == Int(point.curveParameter / 2))
            #expect(chart.surfaceUCycle == Int(point.surfaceU / 2) && chart.surfaceVCycle == Int(point.surfaceV / 2))
        }
        let cut = try solver.intersectionResult(curve: c,surface: s,options: .init(
            curveRange: .init(lower: 2,upper: 2),surfaceURange: .init(lower: 2,upper: 2),
            surfaceVRange: .init(lower: 2,upper: 2)),tolerance: tolerance)
        #expect(cut.points.count == 1 && cut.originalNativeRelations?.components.count == 1)
        let selected = try #require(cut.originalNativePoints), chart = try selected.point(at: 0).sourceChart(in: selected)
        #expect(chart.curveCycle == 1 && chart.surfaceUCycle == 1 && chart.surfaceVCycle == 1)
        for domain in chart.nativeDomains { #expect(try domain.lower == number(2)); #expect(try domain.upper == number(3)) }
    }
    @Test(.timeLimit(.minutes(1)),arguments: ["curve","surface","both"])
    func positiveRelationsAndAllExactUVFibersPreserveFiniteCoverage(mode: String) throws {
        let c = Curve3D.bSpline(mode == "surface" ? openCurve(overlap: true) : periodicCurve(overlap: true))
        let s = Surface3D.bSpline(surface(periodicU: mode != "curve"))
        let solver = DefaultCurveSurfaceIntersector(), result = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(result.points.isEmpty && result.hasPositiveDimensionalSolutions && relation.components.count == 1)
        let projection = try #require(relation.components[0].curveParameterProjections.first)
        #expect(projection.includesLower && projection.includesUpper)
        let station = try OriginalAlgebraicCoordinate.rational(number(0.25),usage: usage())
        let fiber = try relation.surfaceParameterFiber(at: station,maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.components.count == (mode == "curve" ? 1 : 2))
        #expect(try fiber.contains(rationalPoint: [number(0.25),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        if mode != "curve" {
            #expect(try fiber.contains(rationalPoint: [number(1.75),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        }
        let selected = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
            maximumSpanCount: 16,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in },consumeStorage: { _ in },maximumAlgebraicDepth: 32)
        #expect(selected.originalNativeRelations?.components.count == 1)
        for admitted in [false,true] {
            do {
                if admitted { _ = try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance,
                    maximumSpanCount: 16,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                    consumeWork: { _ in },consumeStorage: { _ in },maximumAlgebraicDepth: 32) }
                else { _ = try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance) }
                Issue.record("A periodic positive relation yielded a discrete subset.")
            } catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
        }
        let outside = try relation.surfaceParameterFiber(at: .rational(number(3),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(outside.cells.isEmpty)
    }
    @Test(.timeLimit(.minutes(1)))
    func collapsedImageKeepsIndependentPeriodicUVFibers() throws {
        let relation = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(periodicCurve(constant: true)),
            surface: .bSpline(surface(periodicU: true,collapsed: true)),tolerance: tolerance).originalNativeRelations)
        #expect(relation.components.count == 2 && relation.components.allSatisfy { $0.parameterDimension == 2 && $0.imageDimension == 0 })
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(2),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.components.count == 2 && fiber.components.allSatisfy { $0.dimension == 1 })
        for u in [0.25,1.75] { for v in [0.0,1.0] {
            #expect(try fiber.contains(rationalPoint: [number(u),number(v)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        } }
    }
    @Test(.timeLimit(.minutes(1)))
    func mixedPeriodicComponentsRetainOnlyDetachedPointsAndSourceLifetime() throws {
        let receipt: OriginalNativeCurveSurfacePoints, relation: OriginalNativeCurveSurfaceRelation
        do {
            var source = BSplineCurve3D(degree: 1,knots: [-1,0,1,2,3,4,5,6,7],
                controlPoints: [0.0,0.25,0.5,0.75,0.5,0.25,0.0].enumerated().map {
                    .init(x: $0.element,y: 0.5,z: [0.0,0,1,0,1,1,0][$0.offset])
                },isPeriodic: true)
            var target = surface()
            let solver = DefaultCurveSurfaceIntersector()
            let options = try CurveSurfaceIntersectionOptions(curveRange: .init(lower: 0,upper: 5))
            let result = try solver.intersectionResult(curve: .bSpline(source),surface: .bSpline(target),options: options,tolerance: tolerance)
            receipt = try #require(result.originalNativePoints); relation = try #require(result.originalNativeRelations)
            #expect(result.points.count == 1 && result.points[0].curveParameter == 3 && relation.components.count == 2)
            let admitted = try solver.intersectionResult(curve: .bSpline(source),surface: .bSpline(target),options: options,tolerance: tolerance,
                maximumSpanCount: 7,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { _ in },consumeStorage: { _ in },maximumAlgebraicDepth: 32)
            #expect(admitted.points == result.points && admitted.originalNativeRelations?.components.count == 2)
            #expect(throws: KernelError.self) { try solver.intersections(curve: .bSpline(source),surface: .bSpline(target),options: options,tolerance: tolerance) }
            #expect(throws: KernelError.self) {
                try solver.intersections(curve: .bSpline(source),surface: .bSpline(target),options: options,tolerance: tolerance,
                    maximumSpanCount: 7,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: { _ in })
            }
            source.controlPoints[3].z = 100; target.controlPoints[0][0].z = 100
        }
        let station = try receipt.point(at: 0).parameter(axis: 0,in: receipt)
        #expect(try station.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()).lower == number(3))
        let fiber = try relation.surfaceParameterFiber(at: station,maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.cells.count == 1)
        #expect(try fiber.contains(rationalPoint: [number(0.75),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
    }
    @Test(.timeLimit(.minutes(1)))
    func completeEmptyAndOriginalIssuerFailuresPropagate() throws {
        var source = periodicCurve(); for index in source.controlPoints.indices { source.controlPoints[index].z = 1 }
        let solver = DefaultCurveSurfaceIntersector(), target = Surface3D.bSpline(surface(periodicU: true))
        let empty = try solver.intersectionResult(curve: .bSpline(source),surface: target,tolerance: tolerance)
        #expect(empty.points.isEmpty && empty.originalNativeRelations?.cells.isEmpty == true)
        let admitted = try solver.intersectionResult(curve: .bSpline(source),surface: target,tolerance: tolerance,
            maximumSpanCount: 16,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: { _ in },maximumAlgebraicDepth: 32)
        #expect(admitted.originalNativeRelations?.cells.isEmpty == true)
        #expect(try solver.intersections(curve: .bSpline(source),surface: target,options: .init(),tolerance: tolerance).isEmpty)
        #expect(try solver.intersections(curve: .bSpline(source),surface: target,options: .init(),tolerance: tolerance,
            maximumSpanCount: 16,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: { _ in }).isEmpty)
        let excluded = try #require(solver.intersectionResult(curve: .bSpline(openCurve()),surface: target,
            options: .init(curveRange: .init(lower: 2,upper: 3)),tolerance: tolerance).originalNativeRelations)
        #expect(excluded.effectiveDomains == nil)
        let fiber = try excluded.surfaceParameterFiber(at: .rational(number(2),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.cells.isEmpty && fiber.original.domains == Array(excluded.requestedDomains[1...2]))
        var approximate = periodicCurve(); approximate.knots[0] = approximate.knots[0].nextUp
        do { _ = try solver.intersectionResult(curve: .bSpline(approximate),surface: target,tolerance: tolerance); Issue.record("Approximate transport used a legacy fallback.") }
        catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        do { _ = try solver.intersectionResult(curve: .bSpline(periodicCurve()),surface: target,
            options: .init(curveRange: .init(lower: 1e20,upper: 1e20)),tolerance: tolerance); Issue.record("Unrepresentable cycle yielded success.") }
        catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
        do { _ = try solver.intersectionResult(curve: .bSpline(periodicCurve()),surface: target,tolerance: tolerance,
            maximumSpanCount: 15,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: { _ in }); Issue.record("Aggregate chart products escaped their ceiling.") }
        catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }
    @Test(.timeLimit(.minutes(1)))
    func independentWorkAndStorageRefusalsRemainAtomic() throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(periodicCurve()), s = Surface3D.bSpline(surface())
        for storage in [false,true] {
            #expect(throws: KernelError.self) {
                try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
                    maximumSpanCount: 4,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                    consumeWork: { _ in if !storage { throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Work refused.") } },
                    consumeStorage: { _ in if storage { throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Storage refused.") } })
            }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func finalPeriodicPublicationCancellationIsAtomic() async throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(periodicCurve(overlap: true)), s = Surface3D.bSpline(surface())
        let visits = Mutex(0)
        _ = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
            maximumSpanCount: 4,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in },consumeStorage: { _ in visits.withLock { $0 += 1 } })
        let count = visits.withLock { $0 }, observed = Mutex(0)
        let operation = Task {
            try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
                maximumSpanCount: 4,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { _ in },consumeStorage: { _ in
                    let visit = observed.withLock { $0 += 1; return $0 }
                    if visit == count { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        do { _ = try await operation.value; Issue.record("Cancelled periodic publication yielded success.") }
        catch is CancellationError { #expect(observed.withLock { $0 } == count) }
    }
}
