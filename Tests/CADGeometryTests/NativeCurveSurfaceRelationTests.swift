import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Public original native curve-surface whole relations", .serialized)
struct NativeCurveSurfaceRelationTests {
    private let tolerance = ModelingTolerance.standard
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
    }
    private func number(_ value: Double) throws -> ExactRationalCoefficient {
        var admission = usage(); return try .originalDouble(value, usage: &admission)
    }
    private func curve(constant: Bool = false) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0), .init(x: constant ? 0 : 1,y: 0.5,z: 0)])
    }
    private func plane(collapsed: Bool = false) -> BSplineSurface3D {
        .init(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],controlPoints: [
            [.init(x: 0,y: collapsed ? 0.5 : 0,z: 0),.init(x: 1,y: collapsed ? 0.5 : 0,z: 0)],
            [.init(x: 0,y: collapsed ? 0.5 : 1,z: 0),.init(x: 1,y: collapsed ? 0.5 : 1,z: 0)]])
    }
    @Test(.timeLimit(.minutes(2)))
    func completeGraphProjectionMembershipAndDiscreteFailure() throws {
        let solver = DefaultCurveSurfaceIntersector(), c = curve(), s = plane()
        let result = try solver.intersectionResult(curve: .bSpline(c),surface: .bSpline(s),tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(result.points.isEmpty && result.overlaps.isEmpty && result.hasPositiveDimensionalSolutions)
        #expect(relation.components.count == 1 && relation.components[0].parameterDimension == 1)
        #expect(relation.components[0].imageDimension == 1)
        let projection = try #require(relation.components[0].curveParameterProjections.first)
        #expect(projection.includesLower && projection.includesUpper)
        #expect(try projection.lower.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()).lower == number(0))
        #expect(try projection.upper.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()).upper == number(1))
        #expect(try relation.contains(rationalParameters: [number(0.25),number(0.25),number(0.5)],maximumDepth: 32,usage: usage()))
        #expect(try !relation.contains(rationalParameters: [number(0.25),number(0.5),number(0.5)],maximumDepth: 32,usage: usage()))
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(0.25),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.cells.count == 1 && fiber.components.count == 1 && fiber.cells[0].dimension == 0)
        #expect(try fiber.contains(rationalPoint: [number(0.25),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        #expect(throws: KernelError.self) { try solver.intersections(curve: .bSpline(c),surface: .bSpline(s),options: .init(),tolerance: tolerance) }
        let foreign = try #require(solver.intersectionResult(curve: .bSpline(c),surface: .bSpline(s),tolerance: tolerance).originalNativeRelations)
        #expect(throws: GeometryConversionError.self) {
            try relation.contains(rationalParameters: [number(0),number(0),number(0.5)],
                inCell: foreign.cells[0].identifier,maximumDepth: 32,usage: usage())
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func collapsedImageAndSurfaceFibersKeepDifferentDimensions() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let constant = try #require(solver.intersectionResult(curve: .bSpline(curve(constant: true)),
            surface: .bSpline(plane()),tolerance: tolerance).originalNativeRelations)
        #expect(constant.components[0].parameterDimension == 1 && constant.components[0].imageDimension == 0)
        #expect(constant.cells.contains { $0.parameterDimension == 1 && $0.curveParameterDimension == 1
            && $0.surfaceParameterFiberDimension == 0 && $0.imageFiberDimension == 1 })
        let collapsed = try #require(solver.intersectionResult(curve: .bSpline(curve()),
            surface: .bSpline(plane(collapsed: true)),tolerance: tolerance).originalNativeRelations)
        #expect(collapsed.components[0].parameterDimension == 2 && collapsed.components[0].imageDimension == 1)
        #expect(collapsed.cells.contains { $0.parameterDimension == 2 && $0.surfaceParameterFiberDimension == 1 })
        let fiber = try collapsed.surfaceParameterFiber(at: .rational(number(0.5),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.components.count == 1 && fiber.components[0].dimension == 1)
        #expect(try fiber.contains(rationalPoint: [number(0.5),number(0)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        #expect(try fiber.contains(rationalPoint: [number(0.5),number(1)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
    }
    @Test(.timeLimit(.minutes(1)))
    func fullCollapsedProductRetainsThreeParameterDimensions() throws {
        let c = BSplineCurve3D(degree: 1,knots: [0,0,1,1],controlPoints: [
            .init(x: 0,y: 0,z: 0),.init(x: 0,y: 0,z: 0)])
        let s = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],controlPoints: [
            [.init(x: 0,y: 0,z: 0),.init(x: 0,y: 0,z: 0)],
            [.init(x: 0,y: 0,z: 0),.init(x: 0,y: 0,z: 0)]])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(c),surface: .bSpline(s),tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(result.points.isEmpty && relation.components.count == 1)
        #expect(relation.components[0].parameterDimension == 3 && relation.components[0].imageDimension == 0)
        #expect(relation.cells.contains { $0.parameterDimension == 3 && $0.surfaceParameterFiberDimension == 2 && $0.imageFiberDimension == 3 })
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(0.5),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.components.count == 1 && fiber.components[0].dimension == 2)
        for u in [0.0,1.0] {
            for v in [0.0,1.0] {
                #expect(try fiber.contains(rationalPoint: [number(u),number(v)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
            }
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func mixedComponentKeepsIsolatedPointAndWholeGraph() throws {
        let c = BSplineCurve3D(degree: 1,knots: [0,0,1,1],controlPoints: [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0)])
        let s = BSplineSurface3D(uDegree: 1,vDegree: 2,uKnots: [0,0,1,1],vKnots: [0,0,0,1,1,1],controlPoints: [
            [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0)],
            [.init(x: 0,y: -0.5,z: 0),.init(x: 1,y: -0.5,z: 0.5)],
            [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 1)]])
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(c),surface: .bSpline(s),tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(relation.components.count == 2)
        #expect(relation.components.contains { $0.parameterDimension == 0 })
        #expect(relation.components.contains { $0.parameterDimension == 1 })
        #expect(result.points.count == 1 && result.points[0].curveParameter == 0 && result.points[0].surfaceV == 1)
        #expect(relation.attachments.count > 0)
    }
    @Test(.timeLimit(.minutes(2)))
    func multivaluedConstantSourceFiberRetainsEveryPreimage() throws {
        let c = BSplineCurve3D(degree: 1,knots: [0,0,1,1],controlPoints: [
            .init(x: 0.25,y: 0.5,z: 0),.init(x: 0.25,y: 0.5,z: 0)])
        let s = BSplineSurface3D(uDegree: 2,vDegree: 1,uKnots: [-1,-1,-1,1,1,1],vKnots: [0,0,1,1],controlPoints: [
            [.init(x: 1,y: 0,z: 0),.init(x: -1,y: 0,z: 0),.init(x: 1,y: 0,z: 0)],
            [.init(x: 1,y: 1,z: 0),.init(x: -1,y: 1,z: 0),.init(x: 1,y: 1,z: 0)]])
        let relation = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(c),
            surface: .bSpline(s),tolerance: tolerance).originalNativeRelations)
        #expect(relation.components.count == 2 && relation.components.allSatisfy { $0.imageDimension == 0 })
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(0.25),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.cells.count == 2 && fiber.components.count == 2)
        for u in [-0.5,0.5] {
            #expect(try fiber.contains(rationalPoint: [number(u),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func exactAlgebraicStationRetainsItsSourceScalar() throws {
        let source = BSplineCurve3D(degree: 2,knots: [0,0,0,1,1,1],controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1),.init(x: 0.5,y: 0.5,z: -1),.init(x: 0.5,y: 0.5,z: 1)])
        let solver = DefaultCurveSurfaceIntersector()
        let pointReceipt = try #require(solver.intersectionResult(curve: .bSpline(source),surface: .bSpline(plane()),
            tolerance: tolerance).originalNativePoints)
        let station = try pointReceipt.point(at: 0).parameter(axis: 0,in: pointReceipt)
        let relation = try #require(solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),
            tolerance: tolerance).originalNativeRelations)
        let fiber = try relation.surfaceParameterFiber(at: station,maximumDepth: 32,maximumCoefficientDepth: 32,usage: usage())
        #expect(fiber.cells.count == 1 && fiber.components[0].dimension == 0)
        let value = try fiber.cells[0].sample[0].enclosed(maximumDepth: 32,maximumCoefficientDepth: 32,usage: usage())
        let originalDepth = try station.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()).sourceDepth
        #expect(value.sourceDepth >= originalDepth)
        #expect(throws: (any Error).self) {
            try relation.surfaceParameterFiber(at: station,maximumDepth: 0,maximumCoefficientDepth: 0,usage: usage())
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func completeEmptyAndSingletonRichCoverage() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let empty = try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),
            options: .init(curveRange: .init(lower: 2,upper: 3)),tolerance: tolerance)
        let receipt = try #require(empty.originalNativeRelations)
        #expect(receipt.cells.isEmpty && receipt.components.isEmpty && receipt.effectiveDomains == nil)
        let singleton = try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),
            options: .init(curveRange: .init(lower: 0,upper: 0)),tolerance: tolerance)
        #expect(singleton.points.count == 1 && !singleton.hasPositiveDimensionalSolutions)
        #expect(singleton.originalNativeRelations?.components.count == 1)
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),
                options: .init(maximumCandidateCount: 1),tolerance: tolerance)
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func multivaluedFoldFiberAndExactOutsideExclusion() throws {
        let surface = BSplineSurface3D(uDegree: 2,vDegree: 1,uKnots: [-1,-1,-1,1,1,1],vKnots: [0,0,1,1],controlPoints: [
            [.init(x: 1,y: 0,z: 0),.init(x: -1,y: 0,z: 0),.init(x: 1,y: 0,z: 0)],
            [.init(x: 1,y: 1,z: 0),.init(x: -1,y: 1,z: 0),.init(x: 1,y: 1,z: 0)]])
        let relation = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve()),
            surface: .bSpline(surface),tolerance: tolerance).originalNativeRelations)
        #expect(relation.components.count == 1)
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(0.25),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(fiber.cells.count == 2 && fiber.components.count == 2)
        for u in [-0.5,0.5] {
            #expect(try fiber.contains(rationalPoint: [number(u),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        }
        let outside = try relation.surfaceParameterFiber(at: .rational(number(2),usage: usage()),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(outside.cells.isEmpty && outside.components.isEmpty)
    }
    @Test(.timeLimit(.minutes(2)), arguments: [0,1,2])
    func singularCrossingContactAndCuspAttachments(mode: Int) throws {
        let c: BSplineCurve3D, s: BSplineSurface3D
        if mode < 2 {
            let degree = mode == 0 ? 2 : 4
            let knots = Array(repeating: -1.0,count: degree + 1) + Array(repeating: 1.0,count: degree + 1)
            c = .init(degree: degree,knots: knots,controlPoints: (0...degree).map {
                .init(x: $0 % 2 == 0 ? 1 : -1,y: 0.5,z: 0)
            })
            s = .init(uDegree: 2,vDegree: 1,uKnots: [-1,-1,-1,1,1,1],vKnots: [0,0,1,1],controlPoints: [
                [.init(x: 1,y: 0,z: 0),.init(x: -1,y: 0,z: 0),.init(x: 1,y: 0,z: 0)],
                [.init(x: 1,y: 1,z: 0),.init(x: -1,y: 1,z: 0),.init(x: 1,y: 1,z: 0)]])
        } else {
            c = .init(degree: 1,knots: [0,0,1,1],controlPoints: [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0)])
            s = .init(uDegree: 2,vDegree: 3,uKnots: [-1,-1,-1,1,1,1],vKnots: [0,0,0,0,1,1,1,1],controlPoints: (0...3).map { row in
                [1.0,-1.0,1.0].map { x in .init(x: x,y: (row == 3 ? 1 : 0) - x,z: 0) }
            })
        }
        let relation = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(c),
            surface: .bSpline(s),tolerance: tolerance).originalNativeRelations)
        #expect(relation.components.count == 1 && relation.components[0].parameterDimension == 1)
        let singular = try relation.cells.filter { cell in
            guard cell.parameterDimension == 0 else { return false }
            return try relation.contains(rationalParameters: [number(0),number(0),number(mode == 2 ? 0 : 0.5)],
                inCell: cell.identifier,maximumDepth: 32,usage: usage())
        }
        let junction = try #require(singular.first)
        #expect(junction.originalJacobianRank < 2)
        let incoming = relation.attachments.filter { $0.target == junction.identifier && $0.source != junction.identifier }
        #expect(incoming.count >= 2)
        let projection = try #require(relation.components[0].curveParameterProjections.first)
        #expect(projection.includesLower && projection.includesUpper)
    }
    @Test(.timeLimit(.minutes(1)))
    func retainedSourceAndFiberSurviveInputMutationAndRelease() throws {
        var retained: OriginalNativeCurveSurfaceRelation?
        do {
            var source = curve(), target = plane()
            retained = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source),
                surface: .bSpline(target),tolerance: tolerance).originalNativeRelations)
            source.controlPoints[0] = .init(x: 100,y: 100,z: 100)
            target.controlPoints[0][0] = .init(x: -100,y: -100,z: -100)
            #expect(retained?.curve == curve() && retained?.surface == plane())
        }
        let fiber: OriginalRealRelation
        do {
            let receipt = try #require(retained)
            #expect(try receipt.contains(rationalParameters: [number(0.25),number(0.25),number(0.5)],maximumDepth: 32,usage: usage()))
            fiber = try receipt.surfaceParameterFiber(at: .rational(number(0.25),usage: usage()),
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        }
        retained = nil
        #expect(fiber.cells.count == 1 && fiber.components[0].dimension == 0)
        #expect(try fiber.contains(rationalPoint: [number(0.25),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        #expect(try !fiber.contains(rationalPoint: [number(0.5),number(0.5)],maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
    }
    @Test(.timeLimit(.minutes(1)))
    func cancellationAtFinalPositiveRelationAdmissionIsAtomic() async throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(curve()), s = Surface3D.bSpline(plane())
        let tolerance = tolerance
        @Sendable func query(_ storage: @escaping @Sendable (Int) throws -> Void) throws -> CurveSurfaceIntersectionResult {
            try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance,
                maximumSpanCount: 1,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { _ in },consumeStorage: storage,maximumAlgebraicDepth: 32)
        }
        let calls = Mutex(0)
        let complete = try query { _ in calls.withLock { $0 += 1 } }
        #expect(complete.hasPositiveDimensionalSolutions && complete.originalNativeRelations?.components.count == 1)
        let finalCall = calls.withLock { $0 }, visits = Mutex(0)
        #expect(finalCall > 0)
        let operation = Task {
            try query { _ in
                if visits.withLock({ $0 += 1; return $0 }) == finalCall {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await operation.value
            Issue.record("Cancellation at final positive-dimensional relation admission published success.")
        } catch is CancellationError {
            #expect(visits.withLock { $0 } == finalCall)
        }
    }
    @Test(.timeLimit(.minutes(2)))
    func admittedRichRelationAndIndependentFailureAreAtomic() throws {
        let solver = DefaultCurveSurfaceIntersector(), work = Mutex(0), bytes = Mutex(0)
        let result = try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),tolerance: tolerance,
            maximumSpanCount: 1,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
            consumeWork: { _ in work.withLock { $0 += 1 } },
            consumeStorage: { count in bytes.withLock { $0 += count } },maximumAlgebraicDepth: 32)
        #expect(result.originalNativeRelations?.components.count == 1)
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),tolerance: tolerance,
                maximumSpanCount: 1,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { _ in throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Independent work refusal.") })
        }
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(curve()),surface: .bSpline(plane()),tolerance: tolerance,
                maximumSpanCount: 1,maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { _ in },consumeStorage: { _ in throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Independent storage refusal.") })
        }
    }
}
