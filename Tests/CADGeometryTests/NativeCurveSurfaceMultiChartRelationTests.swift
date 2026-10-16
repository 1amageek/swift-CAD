import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Complete original native multi-chart curve-surface relations", .serialized)
struct NativeCurveSurfaceMultiChartRelationTests {
    private let tolerance = ModelingTolerance.standard
    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }
    private func number(_ value: Double) throws -> ExactRationalCoefficient {
        var admission = try usage(); return try .originalDouble(value, usage: &admission)
    }
    private func source(constant: Bool = false) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,2,2], controlPoints: [0.0,0.5,1.0].map {
            .init(x: constant ? 0.25 : $0,y: 0.5,z: 0)
        })
    }
    private func surface(folded: Bool = false, collapsed: Bool = false) -> BSplineSurface3D {
        .init(uDegree: 1,vDegree: 1,uKnots: folded ? [-1,-1,0,1,1] : [0,0,0.5,1,1],vKnots: [0,0,1,1],
            controlPoints: [0.0,1.0].map { y in (folded ? [1.0,0.0,1.0] : [0.0,0.5,1.0]).map {
                .init(x: $0,y: collapsed ? 0.5 : y,z: 0)
            } })
    }
    @Test(.timeLimit(.minutes(1)))
    func wholeGraphCrossesCurveAndSurfaceJoins() throws {
        var readerExecution = try usage()
        let c = Curve3D.bSpline(source()), s = Surface3D.bSpline(surface()), solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(result.points.isEmpty && result.hasPositiveDimensionalSolutions)
        #expect(result.originalNativePoints?.coverageChartCount == 4)
        #expect(relation.components.count == 1 && relation.components[0].parameterDimension == 1)
        let projections = relation.components[0].curveParameterProjections
        #expect(projections.count == 1 && projections[0].includesLower && projections[0].includesUpper)
        #expect(try projections[0].lower.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).lower == number(0))
        #expect(try projections[0].upper.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).upper == number(2))
        var junctions = 0
        for cell in relation.cells {
            if try relation.contains(rationalParameters: [number(1),number(0.5),number(0.5)],inCell: cell.identifier,
                maximumDepth: 32,usage: &readerExecution) {
                junctions += 1
                #expect(cell.parameterDimension == 0 && cell.originalJacobianRank == 2)
                #expect(try relation.sourceChartDomains[cell.sourceChartIndex][0].lower == number(1))
                #expect(try relation.sourceChartDomains[cell.sourceChartIndex][1].lower == number(0.5))
                #expect(relation.attachments.filter { $0.target == cell.identifier && $0.source != cell.identifier }.count >= 2)
            }
        }
        #expect(junctions == 1)
        let selected = try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: c,
            surface: s,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(selected.points.isEmpty && selected.originalNativeRelations?.components.count == 1)
        for admitted in [false,true] {
            do {
                if admitted {
                    _ = try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: c,
            surface: s,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
                } else { _ = try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance) }
                Issue.record("A positive multi-chart relation yielded a discrete subset.")
            } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func repeatedKnotsAndTensorCornerKeepClosedOwner() throws {
        var readerExecution = try usage()
        let c = BSplineCurve3D(degree: 2,knots: [0,0,0,1,1,2,2,2],controlPoints: [0.0,0.25,0.5,0.75,1.0].map {
            .init(x: $0,y: 0.5,z: 0)
        })
        let knots = [0.0,0,0,0.5,0.5,1,1,1]
        let grid = [0.0,0.25,0.5,0.75,1.0]
        let s = BSplineSurface3D(uDegree: 2,vDegree: 2,uKnots: knots,vKnots: knots,
            controlPoints: grid.map { y in grid.map { .init(x: $0,y: y,z: 0) } })
        let solver = DefaultCurveSurfaceIntersector()
        let whole = try solver.intersectionResult(curve: .bSpline(c),surface: .bSpline(s),tolerance: tolerance)
        #expect(whole.points.isEmpty && whole.originalNativePoints?.coverageChartCount == 8)
        #expect(whole.originalNativeRelations?.components.count == 1)
        let cut = try solver.intersectionResult(curve: .bSpline(c),surface: .bSpline(s),options: .init(
            curveRange: .init(lower: 1,upper: 1),surfaceURange: .init(lower: 0.5,upper: 0.5),
            surfaceVRange: .init(lower: 0.5,upper: 0.5)),tolerance: tolerance)
        #expect(cut.points.count == 1 && !cut.hasPositiveDimensionalSolutions)
        #expect(cut.originalNativeRelations?.cells.count == 1 && cut.originalNativeRelations?.components.count == 1)
        let receipt = try #require(cut.originalNativePoints)
        let scalar = try receipt.point(at: 0).parameter(axis: 0,in: receipt)
        #expect(try scalar.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).lower == number(1))
        let partial = try solver.intersectionResult(curve: .bSpline(c),surface: .bSpline(s),
            options: .init(curveRange: .init(lower: 0,upper: 1)),tolerance: tolerance)
        let projection = try #require(partial.originalNativeRelations?.components.first?.curveParameterProjections.first)
        #expect(projection.includesUpper)
        #expect(try projection.upper.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).upper == number(1))
    }
    @Test(.timeLimit(.minutes(1)))
    func allPreimagesAndCollapsedFibersSurviveChartComposition() throws {
        var readerExecution = try usage()
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source(constant: true)),
            surface: .bSpline(surface(folded: true,collapsed: true)),tolerance: tolerance)
        let relation = try #require(result.originalNativeRelations)
        #expect(result.points.isEmpty && relation.components.count == 2)
        #expect(relation.components.allSatisfy { $0.parameterDimension == 2 && $0.imageDimension == 0 })
        #expect(relation.cells.contains { $0.surfaceParameterFiberDimension == 1 && $0.imageFiberDimension == 2 })
        for station in [0.0,1.0,2.0] {
            let fiber = try relation.surfaceParameterFiber(at: .rational(number(station),usage: &readerExecution),
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution)
            #expect(fiber.components.count == 2 && fiber.components.allSatisfy { $0.dimension == 1 })
            for u in [-0.25,0.25] {
                for v in [0.0,1.0] {
                    #expect(try fiber.contains(rationalPoint: [number(u),number(v)],maximumDepth: 32,
                        maximumCoefficientDepth: 0,usage: &readerExecution))
                }
            }
        }
        let outside = try relation.surfaceParameterFiber(at: .rational(number(3),usage: &readerExecution),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution)
        #expect(outside.cells.isEmpty && outside.components.isEmpty)
    }
    @Test(.timeLimit(.minutes(1)))
    func joinedFoldKeepsAllBranchesAndExactStationFiber() throws {
        var readerExecution = try usage()
        let relation = try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(source()),
            surface: .bSpline(surface(folded: true)),tolerance: tolerance).originalNativeRelations)
        #expect(relation.components.count == 1 && relation.components[0].parameterDimension == 1)
        let fiber = try relation.surfaceParameterFiber(at: .rational(number(1),usage: &readerExecution),
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution)
        #expect(fiber.cells.count == 2 && fiber.components.count == 2)
        for u in [-0.5,0.5] {
            #expect(try fiber.contains(rationalPoint: [number(u),number(0.5)],maximumDepth: 32,
                maximumCoefficientDepth: 0,usage: &readerExecution))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func multiChartCompleteEmptyAndIndependentLimits() throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(source()), s = Surface3D.bSpline(surface())
        let empty = try solver.intersectionResult(curve: c,surface: s,options: .init(curveRange: .init(lower: 3,upper: 4)),tolerance: tolerance)
        #expect(empty.originalNativeRelations?.cells.isEmpty == true && empty.originalNativeRelations?.effectiveDomains == nil)
        let nonlinear = Surface3D.bSpline(BSplineSurface3D(uDegree: 2,vDegree: 1,uKnots: [-1,-1,-1,1,1,1],
            vKnots: [0,0,1,1],controlPoints: [0.0,1.0].map { y in [1.0,-1.0,1.0].map { .init(x: $0,y: y,z: 0) } }))
        for mode in 0..<4 {
            do {
                _ = try geometryTestWithQuery(maximumSpanCount: mode == 0 ? 3 : 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: mode == 3 ? 0 : 32,
            consumeWorkUnits: { _ in if mode == 1 { throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Work refused.") } },
            consumeStorageBytes: { _ in if mode == 2 { throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,message: "Storage refused.") } }) { queryExecution in
            try solver.intersectionResult(curve: c,
            surface: mode == 3 ? nonlinear : s,
            tolerance: tolerance,
            using: &queryExecution)
        }
                Issue.record("An independently exhausted multi-chart allowance yielded success in mode \(mode).")
            } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .resourceLimitExceeded) }
        }
        do {
            _ = try solver.intersectionResult(curve: .bSpline(source()),surface: .bSpline(surface()),
                options: .init(maximumCandidateCount: 4),tolerance: tolerance)
            Issue.record("The common refinement ignored its all-cell candidate ceiling.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .resourceLimitExceeded) }
    }
    @Test(.timeLimit(.minutes(1)))
    func globalMixedComponentsPreserveOnlyTheDetachedIsolatedPoint() throws {
        var readerExecution = try usage()
        let solver = DefaultCurveSurfaceIntersector()
        let retainedPoints: OriginalNativeCurveSurfacePoints
        let retainedRelation: OriginalNativeCurveSurfaceRelation
        do {
            let c = Curve3D.bSpline(BSplineCurve3D(degree: 1,knots: [0,0,1,2,3,3],controlPoints: [
                .init(x: 0,y: 0.5,z: 0),.init(x: 0.25,y: 0.5,z: 0),
                .init(x: 0.5,y: 0.5,z: 1),.init(x: 1,y: 0.5,z: 0)]))
            let s = Surface3D.bSpline(BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],
                controlPoints: [0.0,1.0].map { y in [0.0,1.0].map { .init(x: $0,y: y,z: 0) } }))
            let result = try solver.intersectionResult(curve: c,surface: s,tolerance: tolerance)
            retainedPoints = try #require(result.originalNativePoints)
            retainedRelation = try #require(result.originalNativeRelations)
            #expect(result.points.count == 1 && result.points[0].curveParameter == 3)
            #expect(retainedRelation.components.count == 2)
            #expect(retainedRelation.components.contains { $0.parameterDimension == 0 })
            #expect(retainedRelation.components.contains { $0.parameterDimension == 1 })
            #expect(try retainedRelation.contains(rationalParameters: [number(1),number(0.25),number(0.5)],
                maximumDepth: 32,usage: &readerExecution))
            let positive = try #require(retainedRelation.components.first { $0.parameterDimension == 1 })
            let projection = try #require(positive.curveParameterProjections.first)
            #expect(projection.includesLower && projection.includesUpper)
            #expect(try projection.upper.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).upper == number(1))
            let admitted = try geometryTestWithQuery(maximumSpanCount: 3,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(curve: c,
            surface: s,
            tolerance: tolerance,
            using: &queryExecution)
        }
            #expect(admitted.points == result.points && admitted.originalNativeRelations?.components.count == 2)
            for selected in [false,true] {
                do {
                    if selected {
                        _ = try geometryTestWithQuery(maximumSpanCount: 3,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(curve: c,
            surface: s,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
                    } else { _ = try solver.intersections(curve: c,surface: s,options: .init(),tolerance: tolerance) }
                    Issue.record("A mixed global relation published a discrete isolated subset.")
                } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
            }
        }
        #expect(retainedPoints.count == 1 && retainedPoints.coverageChartCount == 3)
        let point = try retainedPoints.point(at: 0)
        let station = try point.parameter(axis: 0,in: retainedPoints)
        #expect(try station.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).lower == number(3))
        let u = try point.parameter(axis: 1,in: retainedPoints)
        #expect(try u.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution).lower == number(1))
        let fiber = try retainedRelation.surfaceParameterFiber(at: station,
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: &readerExecution)
        #expect(fiber.cells.count == 1 && fiber.components.count == 1)
        #expect(try fiber.contains(rationalPoint: [number(1),number(0.5)],maximumDepth: 32,
            maximumCoefficientDepth: 0,usage: &readerExecution))
    }
    @Test(.timeLimit(.minutes(1)))
    func finalMultiChartPublicationCancellationIsAtomic() async throws {
        let solver = DefaultCurveSurfaceIntersector(), c = Curve3D.bSpline(source()), s = Surface3D.bSpline(surface())
        let visits = Mutex(0)
        _ = try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in visits.withLock { $0 += 1 } }) { queryExecution in
            try solver.intersectionResult(curve: c,
            surface: s,
            tolerance: tolerance,
            using: &queryExecution)
        }
        let total = visits.withLock { $0 }, observed = Mutex(0)
        let operation = Task {
            try geometryTestWithQuery(maximumSpanCount: 4,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { _ in },
            consumeStorageBytes: { _ in
                    let count = observed.withLock { $0 += 1; return $0 }
                    if count == total { withUnsafeCurrentTask { $0?.cancel() } }
                }) { queryExecution in
            try solver.intersectionResult(curve: c,
            surface: s,
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        do { _ = try await operation.value; Issue.record("Cancelled common-refinement publication yielded success.") }
        catch where geometryTestIsCancelled(error) { #expect(observed.withLock { $0 } == total) }
    }
}
