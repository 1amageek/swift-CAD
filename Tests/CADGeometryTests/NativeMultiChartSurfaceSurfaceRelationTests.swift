import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Complete public multi-chart Native SSI", .serialized)
struct NativeMultiChartSurfaceSurfaceRelationTests {
    private let tolerance = ModelingTolerance.standard
    private func usage() throws -> OriginalQueryExecution {
        try .independentGeometry()
    }
    private func strip(xs: [Double] = [0,1,2], zs: [[Double]]? = nil,
        weights: [[Double]]? = nil, y: [Double] = [0,1]) -> BSplineSurface3D {
        let end = Double(xs.count - 1)
        return .init(uDegree: 1, vDegree: 1,
            uKnots: [0,0] + (1..<(xs.count - 1)).map(Double.init) + [end,end],
            vKnots: [0,0,1,1], controlPoints: (0..<2).map { v in xs.indices.map { u in
                .init(x: xs[u], y: y[v], z: zs?[v][u] ?? 0) } }, weights: weights)
    }
    private func plane(end: Double = 2, y: [Double] = [0,1], z: Double = 0) -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,end,end], vKnots: [0,0,1,1],
            controlPoints: y.map { value in [.init(x: 0,y: value,z: z), .init(x: end,y: value,z: z)] })
    }
    private func crossing() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,2,2], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0.5,z: -0.5), .init(x: 2,y: 0.5,z: -0.5)],
                [.init(x: 0,y: 0.5,z: 0.5), .init(x: 2,y: 0.5,z: 0.5)]])
    }
    private func finite(_ first: BSplineSurface3D, _ second: BSplineSurface3D,
        options: SurfaceSurfaceIntersectionOptions = .init(), spans: Int = 64, maximumAlgebraicDepth: Int = 32) throws -> SurfaceSurfaceIntersectionResult {
        let work = Mutex(80_000_000), bytes = Mutex(1_073_741_824)
        let result = try geometryTestWithQuery(maximumSpanCount: spans,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: maximumAlgebraicDepth,
            consumeWorkUnits: { units in for _ in 0..<units { try work.withLock { left in
                guard left > 0 else { throw GeometryConversionError.resourceLimitExceeded("Multi-chart SSI work exhausted.") }; left -= 1
            } } },
            consumeStorageBytes: { count in try bytes.withLock { left in
                guard count <= left else { throw GeometryConversionError.resourceLimitExceeded("Multi-chart SSI bytes exhausted.") }; left -= count
            } }) { queryExecution in
            try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(first),
            second: .bSpline(second),
            options: options,
            tolerance: tolerance,
            using: &queryExecution)
        }
        print("Multi-chart SSI work=\(80_000_000 - work.withLock { $0 }) bytes=\(1_073_741_824 - bytes.withLock { $0 })")
        return result
    }
    private func exact<A: ExactScalarAdmission & ~Copyable>(_ value: Double, _ budget: inout A) throws -> ExactRationalCoefficient {
        try .originalDouble(value, usage: &budget)
    }

    @Test(.timeLimit(.minutes(3)))
    func closedJoinAllPublicRoutesAndAtomicDiscreteRejection() throws {
        let first = strip(), second = crossing(), solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let ordinary = try solver.intersectionResult(first: .bSpline(first), second: .bSpline(second), options: .init(), tolerance: tolerance)
        let admitted = try finite(first, second)
        for result in [ordinary, admitted] {
            let receipt = try #require(result.originalNativeRelations)
            #expect(receipt.componentCount == 1 && receipt.sourceChartCount == 2 && result.intersections.isEmpty)
            #expect(try receipt.component(at: 0).imageDimension == 1)
            #expect(receipt.attachmentCount > 0)
            var budget = try usage(); let half = try exact(0.5, &budget)
            #expect(try receipt.contains(parameters: [.one,half,.one,half], maximumAlgebraicDepth: 32, usage: &budget))
            var seamOwners = 0
            for index in 0..<receipt.cellCount {
                let cell = try receipt.cell(at: index)
                if try receipt.contains(parameters: [.one,half,.one,half], inCell: cell.identifier, maximumAlgebraicDepth: 32, usage: &budget) {
                    #expect(cell.sourceChartIndex == 1); seamOwners += 1
                }
            }
            #expect(seamOwners == 1)
        }
        let whole = SurfaceParameterBox(u: try .init(lower: 0, upper: 2), v: try .init(lower: 0, upper: 1))
        let domain = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(first: .bSpline(first),
            over: whole,
            second: .bSpline(second),
            over: whole,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(domain.originalNativeRelations?.componentCount == 1)
        let session = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.prepareOriginalPair(first: .bSpline(first),
            second: .bSpline(second),
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(try session.intersectionResult(firstBox: whole, secondBox: whole, options: .init()).originalNativeRelations?.componentCount == 1)
        do { _ = try solver.intersections(first: .bSpline(first), second: .bSpline(second), options: .init(), tolerance: tolerance); Issue.record("Discrete ordinary exposed a positive subset.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        do { _ = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(first: .bSpline(first),
            second: .bSpline(second),
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }; Issue.record("Discrete admitted exposed a positive subset.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        do { _ = try session.intersections(firstBox: whole, secondBox: whole, options: .init()); Issue.record("Prepared discrete exposed a curve.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        do { _ = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersections(first: .bSpline(first),
            over: whole,
            second: .bSpline(second),
            over: whole,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }; Issue.record("Domain discrete exposed a curve.") }
        catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
            #expect(error.code == .nonDiscreteIntersection) }
        let singleton = SurfaceParameterBox(u: try .init(lower: 1, upper: 1), v: try .init(lower: 0.5, upper: 0.5))
        let point = try session.intersectionResult(firstBox: singleton, secondBox: singleton, options: .init())
        let owner = try #require(point.originalNativePoints), handle = try owner.point(at: 0)
        #expect(point.intersections.count == 1 && owner.count == 1 && owner.sourceChartCount == 2)
        #expect(try owner.sourceChartIndex(for: handle) == 1)
        #expect(try owner.sourceChart(at: 0).domains[0].upper == .one)
        #expect(try owner.sourceChart(at: 1).domains[0].lower == .one)
    }

    @Test(.timeLimit(.minutes(3)))
    func tensorRepeatedC0KnotsWeightedAndNonUnitDomains() throws {
        let weighted = strip(weights: [[1,2,1],[2,4,2]])
        let region = try #require(try finite(weighted, weighted).originalNativeRelations)
        #expect(region.sourceChartCount == 4 && region.componentCount == 1)
        #expect(try region.component(at: 0).parameterDimension == 2)
        #expect(try region.component(at: 0).imageDimension == 2)
        let knots = [2.0,2,2,3,3,4,4,4], coordinates = [2.0,2.5,3,3.5,4]
        let tensor = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots,
            controlPoints: coordinates.map { y in coordinates.map { x in .init(x: x,y: y,z: 0) } })
        let relation = try #require(try finite(tensor, tensor).originalNativeRelations)
        #expect(relation.sourceChartCount == 16 && relation.componentCount == 1)
        #expect(try relation.component(at: 0).imageDimension == 2)
        var budget = try usage(); let three = try exact(3, &budget)
        var owners = 0
        for index in 0..<relation.cellCount {
            let cell = try relation.cell(at: index)
            if try relation.contains(parameters: [three,three,three,three], inCell: cell.identifier, maximumAlgebraicDepth: 32, usage: &budget) {
                let chart = try relation.sourceChart(at: cell.sourceChartIndex)
                #expect(chart.firstUSpanIndex == 4 && chart.firstVSpanIndex == 4)
                #expect(chart.secondUSpanIndex == 4 && chart.secondVSpanIndex == 4); owners += 1
            }
        }
        #expect(owners == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func multipleUVFibersAndCollapsedImageKeepOriginalDimensions() throws {
        let folded = strip(xs: [0,1,0]), first = plane(end: 1)
        let relation = try #require(try finite(first, folded).originalNativeRelations)
        #expect(relation.componentCount == 1 && relation.sourceChartCount == 2)
        var budget = try usage(); let half = try exact(0.5, &budget), oneAndHalf = try exact(1.5, &budget)
        let fiber = try relation.fiber(surface: 0, u: half, v: half, maximumAlgebraicDepth: 32, usage: &budget)
        #expect(fiber.componentCount == 2)
        #expect(try fiber.contains(parameters: [half,half,half,half], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(try fiber.contains(parameters: [half,half,oneAndHalf,half], maximumAlgebraicDepth: 32, usage: &budget))
        for index in 0..<fiber.componentCount { #expect(try fiber.component(at: index).imageDimension == 0) }
        let constant = strip(xs: [0,0,0], y: [0,0])
        let collapsed = try #require(try finite(constant, constant).originalNativeRelations)
        let component = try collapsed.component(at: 0)
        #expect(component.parameterDimension == 4 && component.imageDimension == 0)
        #expect(collapsed.componentCount == 1)
        var largest = 0
        for index in 0..<collapsed.cellCount {
            for image in try collapsed.cell(at: index).imageStrata {
                #expect(image.imageDimension == 0 && image.fiberDimension == image.parameterDimension)
                largest = max(largest, image.fiberDimension)
            }
        }
        #expect(largest == 4)
    }

    @Test(.timeLimit(.minutes(3)))
    func regionCurveAndIsolatedPointRetainWholeMixedAuthority() throws {
        var target = strip(xs: [0,1,2,3,4,5], zs: [[0,0,1,0,1,0],[0,0,1,0,1,1]])
        let result = try finite(plane(end: 5), target), relation = try #require(result.originalNativeRelations)
        #expect(relation.componentCount == 3 && result.intersections.count == 1 && result.originalNativePoints?.count == 1)
        var dimensions: [Int] = []
        for index in 0..<relation.componentCount { dimensions.append(try relation.component(at: index).parameterDimension) }
        #expect(dimensions.sorted() == [0,1,2])
        var budget = try usage(); let three = try exact(3, &budget), five = try exact(5, &budget), half = try exact(0.5, &budget)
        #expect(try relation.contains(parameters: [three,half,three,half], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(try relation.contains(parameters: [five,.zero,five,.zero], maximumAlgebraicDepth: 32, usage: &budget))
        let owner = try #require(result.originalNativePoints), handle = try owner.point(at: 0)
        #expect(try handle.compareParameter(axis: 0, to: five, in: owner, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        #expect(try owner.sourceChartIndex(for: handle) == 4)
        let ordinary = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(plane(end: 5)), second: .bSpline(target), tolerance: tolerance)
        #expect(ordinary.originalNativeRelations?.componentCount == 3 && ordinary.intersections.count == 1)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try finite(plane(end: 5), target, options: .init(maximumSeedCount: 2)) }
        target = strip(xs: [10,11,12])
        #expect(try handle.compareParameter(axis: 0, to: five, in: owner, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        let foreign = try #require(try finite(plane(end: 5), strip(xs: [0,1,2,3,4,5], zs: [[0,0,1,0,1,0],[0,0,1,0,1,1]])).originalNativePoints)
        #expect(throws: GeometryConversionError.self) { try handle.compareParameter(axis: 0, to: five, in: foreign, maximumAlgebraicDepth: 32, usage: &budget) }
    }

    @Test(.timeLimit(.minutes(3)))
    func sourceLifetimeExactOrderedStationForeignHandlesAndExcludedSelection() throws {
        var readerExecution = try usage()
        var first = strip(), second = plane()
        let expected = first
        let relation = try #require(try finite(first, second).originalNativeRelations)
        first = strip(xs: [10,11,12]); second = plane(z: 4)
        #expect(relation.firstSurface == expected)
        var budget = try usage(); let half = try exact(0.5, &budget)
        #expect(try relation.contains(parameters: [.one,half,.one,half], maximumAlgebraicDepth: 32, usage: &budget))
        let singleton = try relation.fiber(surface: 0, u: .one, v: half, maximumAlgebraicDepth: 32, usage: &budget)
        let cell = try singleton.cell(at: 0)
        let ordered = try relation.fiber(surface: 0, u: cell.parameterSample[0], v: cell.parameterSample[1],
            maximumAlgebraicDepth: 32, maximumCoefficientDepth: 32, usage: &readerExecution)
        #expect(ordered.relation.components.count == 1 && ordered.imageDimension == 0)
        let foreign = try #require(try finite(strip(), plane()).originalNativeRelations)
        #expect(throws: GeometryConversionError.self) {
            try relation.contains(parameters: [.one,half,.one,half], inCell: foreign.cell(at: 0).identifier, maximumAlgebraicDepth: 32, usage: &budget)
        }
        let outside = try exact(3, &budget)
        #expect(throws: GeometryConversionError.self) { try relation.fiber(surface: 0, u: outside, v: half, maximumAlgebraicDepth: 32, usage: &budget) }
        #expect(try relation.contains(parameters: [.one,half,.one,half], maximumAlgebraicDepth: 0, usage: &budget))
        let absent = try finite(strip(), plane(z: 1))
        #expect(absent.intersections.isEmpty && absent.originalNativePoints?.count == 0 && absent.originalNativeRelations?.cellCount == 0)
        let box = SurfaceParameterBox(u: try .init(lower: 3, upper: 4), v: try .init(lower: 0, upper: 1))
        let exclusion = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(strip()),
            over: box,
            second: .bSpline(plane()),
            over: box,
            options: .init(),
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(exclusion.originalNativeRelations?.effectiveDomains == nil && exclusion.originalNativeRelations?.cellCount == 0)
    }

    @Test(.timeLimit(.minutes(3)))
    func irrationalIsolatedTuplePublicationAndRefinementLimit() throws {
        var readerExecution = try usage()
        // Original z=3(2u^2-1)^2+3v^2 has only the two real tuples u=+/-sqrt(1/2),v=0.
        // The first Native source's selected x>=0 product retains exactly the positive tuple.
        let x = [-1.0,-0.5,0,0.5,1], y = [-1.0,0,1]
        let quartic = [3.0,-9,19,-9,3], square = [3.0,-3,3]
        let target = BSplineSurface3D(uDegree: 4, vDegree: 2,
            uKnots: [-1,-1,-1,-1,-1,1,1,1,1,1], vKnots: [-1,-1,-1,1,1,1],
            controlPoints: (0..<3).map { v in (0..<5).map { u in .init(x: x[u],y: y[v],z: quartic[u] + square[v]) } })
        let first = strip(y: [-1,1]), result = try finite(first, target)
        let owner = try #require(result.originalNativePoints), handle = try owner.point(at: 0)
        #expect(owner.count == 1 && result.intersections.count == 1)
        let u = try handle.parameter(axis: 0, in: owner)
        let enclosure = try u.enclosed(maximumDepth: 32, maximumCoefficientDepth: 32, usage: &readerExecution)
        #expect(enclosure.lower != enclosure.upper)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try finite(first, target, maximumAlgebraicDepth: 0) }
        let relation = try #require(result.originalNativeRelations), cell = try relation.cell(at: 0)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            try relation.fiber(surface: 0, u: cell.parameterSample[0], v: cell.parameterSample[1],
                maximumAlgebraicDepth: 0, maximumCoefficientDepth: 32, usage: &readerExecution)
        }
        do {
            _ = try finite(first, target, options: .init(maximumIterations: 1))
            Issue.record("One refinement iteration published an insufficient irrational enclosure.")
        } catch let caught where geometryTestKernelFailure(caught) != nil {
            let error = geometryTestKernelFailure(caught)!
           
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.message == "Native exact-root publication exhausted refinement iterations.")
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func independentAdmissionAndFinalCancellationAreAtomic() async throws {
        let first = Surface3D.bSpline(strip()), second = Surface3D.bSpline(crossing()), solver = DefaultSurfaceSurfaceIntersector()
        #expect(throws: GeometryConversionError.self) { try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units { throw GeometryConversionError.resourceLimitExceeded("Denied work.") } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        } }
        #expect(throws: GeometryConversionError.self) { try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in throw GeometryConversionError.resourceLimitExceeded("Denied storage.") }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        } }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try finite(strip(), crossing(), spans: 1) }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try solver.intersectionResult(first: first, second: second, options: .init(maximumSubdivisionCells: 1), tolerance: tolerance) }
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 0,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        } }
        let rationalDepthZero = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 0,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        }
        #expect(rationalDepthZero.originalNativeRelations?.componentCount == 1)
        #expect(rationalDepthZero.originalNativeRelations?.hasPositiveDimensionalParameters == true)
        let storageCalls = Mutex(0)
        _ = try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in storageCalls.withLock { $0 += 1 } }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        }
        let final = storageCalls.withLock { $0 }, current = Mutex(0), denied = Mutex(false)
        #expect(throws: GeometryConversionError.self) { try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in
                if current.withLock({ $0 += 1; return $0 }) == final { denied.withLock { $0 = true }; throw GeometryConversionError.resourceLimitExceeded("Denied final storage.") }
            }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        } }
        #expect(denied.withLock { $0 })
        let cancellationCalls = Mutex(0)
        let task = Task {
            try geometryTestWithQuery(maximumSpanCount: 2,
            maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1,
            maximumAlgebraicDepth: 32,
            consumeWorkUnits: { units in for _ in 0..<units {  } },
            consumeStorageBytes: { _ in
                    if cancellationCalls.withLock({ $0 += 1; return $0 }) == final { withUnsafeCurrentTask { $0?.cancel() } }
                }) { queryExecution in
            try solver.intersectionResult(first: first,
            second: second,
            tolerance: tolerance,
            using: &queryExecution)
        }
        }
        do { _ = try await task.value; Issue.record("Final cancellation exposed partial Native SSI success.") }
        catch where geometryTestIsCancelled(error) {}
    }
}
