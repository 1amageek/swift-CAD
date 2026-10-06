import CADCore
import CADGeometry
import Synchronization
import Testing

@Suite("Public original native surface-surface relations", .serialized)
struct NativeSurfaceSurfaceRelationTests {
    private let tolerance = ModelingTolerance.standard

    private func surface(uDegree: Int = 1, vDegree: Int = 1,
        point: (Int, Int) -> Point3D) -> BSplineSurface3D {
        .init(uDegree: uDegree, vDegree: vDegree,
            uKnots: Array(repeating: -1.0, count: uDegree + 1) + Array(repeating: 1.0, count: uDegree + 1),
            vKnots: Array(repeating: -1.0, count: vDegree + 1) + Array(repeating: 1.0, count: vDegree + 1),
            controlPoints: (0...vDegree).map { v in (0...uDegree).map { u in point(u,v) } })
    }
    private func plane() -> BSplineSurface3D {
        surface { u,v in .init(x: u == 0 ? -1 : 1, y: v == 0 ? -1 : 1,z: 0) }
    }
    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
    }
    private func finiteUsage(workLimit: Int = 80_000_000) -> OriginalRelationUsage {
        let work = Mutex(workLimit), bytes = Mutex(1_073_741_824), cells = Mutex(262_144)
        return .init(consumeWork: { count in try work.withLock { remaining in
            guard count <= remaining else { throw GeometryConversionError.resourceLimitExceeded("SSI fiber work exhausted.") }
            remaining -= count
        } }, retainStorage: { words in try bytes.withLock { remaining in
            guard words <= remaining / 4 else { throw GeometryConversionError.resourceLimitExceeded("SSI fiber bytes exhausted.") }
            remaining -= words * 4
        } }, visitCell: { _ in try cells.withLock { remaining in
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("SSI fiber cells exhausted.") }
            remaining -= 1
        } }, visitCoefficientCell: { _ in try cells.withLock { remaining in
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("SSI fiber coefficient cells exhausted.") }
            remaining -= 1
        } })
    }
    private func rich(_ first: BSplineSurface3D, _ second: BSplineSurface3D) throws -> SurfaceSurfaceIntersectionResult {
        let work = Mutex(80_000_000), bytes = Mutex(1_073_741_824)
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(first), second: .bSpline(second),
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { try work.withLock { remaining in
                guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("SSI relation caller work exhausted.") }
                remaining -= 1
            } }, consumeStorage: { count in try bytes.withLock { remaining in
                guard count <= remaining else { throw GeometryConversionError.resourceLimitExceeded("SSI relation caller storage exhausted.") }
                remaining -= count
            } }, maximumAlgebraicDepth: 32)
        return result
    }
    private func dimensions(_ receipt: OriginalNativeSurfaceSurfaceRelations) throws -> [(Int,Int)] {
        try (0..<receipt.componentCount).map { index in
            let component = try receipt.component(at: index)
            return (component.parameterDimension, component.imageDimension)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func transverseCurveRetainsBothUVsAndAllRichRoutes() throws {
        let first = plane(), second = surface { u,v in .init(x: u == 0 ? -1 : 1,y: 0,z: v == 0 ? -1 : 1) }
        let result = try rich(first, second), receipt = try #require(result.originalNativeRelations)
        #expect(result.intersections.isEmpty && result.originalNativePoints == nil)
        let component = try receipt.component(at: 0)
        #expect(receipt.componentCount == 1 && component.parameterDimension == 1 && component.imageDimension == 1)
        #expect(receipt.attachmentCount > 0 && receipt.nativeDomains.count == 4)
        var budget = usage()
        #expect(try receipt.contains(parameters: [.zero,.zero,.zero,.zero], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(try receipt.contains(parameters: [.one,.zero,.one,.zero], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(!(try receipt.contains(parameters: [.zero,.one,.zero,.zero], maximumAlgebraicDepth: 32, usage: &budget)))
        let solver: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let ordinary = try solver.intersectionResult(first: .bSpline(first), second: .bSpline(second), options: .init(), tolerance: tolerance)
        #expect(ordinary.originalNativeRelations?.componentCount == 1)
        let box = SurfaceParameterBox(u: try .init(lower: -0.5,upper: 0.5), v: try .init(lower: -0.5,upper: 0.5))
        let domain = try solver.intersectionResult(first: .bSpline(first), over: box, second: .bSpline(second), over: box,
            options: .init(), tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1, consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        #expect(domain.originalNativeRelations?.componentCount == 1)
        let session = try solver.prepareOriginalPair(first: .bSpline(first), second: .bSpline(second), tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: {}, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        let prepared = try session.intersectionResult(firstBox: box, secondBox: box, options: .init())
        #expect(prepared.originalNativeRelations?.componentCount == 1)
        do { _ = try session.intersections(firstBox: box, secondBox: box, options: .init()); Issue.record("Legacy session exposed a non-discrete subset.") }
        catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
        do { _ = try solver.intersections(first: .bSpline(first), second: .bSpline(second), options: .init(), tolerance: tolerance); Issue.record("Legacy array exposed a curve as empty.") }
        catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
        let foreign = try #require(try rich(first,second).originalNativeRelations)
        do { _ = try receipt.contains(parameters: [.zero,.zero,.zero,.zero], inCell: foreign.cell(at: 0).identifier,
            maximumAlgebraicDepth: 32, usage: &budget); Issue.record("Foreign SSI cell was accepted.") }
        catch let error as GeometryConversionError { guard case .invalidInput = error else { throw error } }
    }

    @Test(.timeLimit(.minutes(2)))
    func contactAndCrossingKeepSingularAttachments() throws {
        let first = plane()
        let tangent = surface(uDegree: 1,vDegree: 2) { u,v in
            .init(x: u == 0 ? -1 : 1,y: Double(v - 1),z: v == 1 ? -1 : 1)
        }
        let contact = try #require(try rich(first,tangent).originalNativeRelations)
        #expect(contact.componentCount == 1)
        #expect(try contact.component(at: 0).imageDimension == 1)
        var hasContact = false
        for ordinal in 0..<contact.cellCount { if try contact.cell(at: ordinal).originalJacobianRank == 2 { hasContact = true } }
        #expect(hasContact)
        let crossing = surface { u,v in
            let a = u == 0 ? -1.0 : 1.0, b = v == 0 ? -1.0 : 1.0
            return .init(x: a,y: b,z: a * b)
        }
        let branch = try #require(try rich(first,crossing).originalNativeRelations)
        #expect(branch.componentCount == 1)
        #expect(try branch.component(at: 0).imageDimension == 1)
        var budget = usage()
        #expect(try branch.contains(parameters: [.zero,.one,.zero,.one], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(try branch.contains(parameters: [.one,.zero,.one,.zero], maximumAlgebraicDepth: 32, usage: &budget))
        #expect(!(try branch.contains(parameters: [.one,.one,.one,.one], maximumAlgebraicDepth: 32, usage: &budget)))
        var singularAttachments = 0
        for ordinal in 0..<branch.attachmentCount {
            let attachment = try branch.attachment(at: ordinal)
            if try branch.cell(at: attachment.source.ordinal).parameterDimension == 1,
                try branch.cell(at: attachment.target.ordinal).parameterDimension == 0 { singularAttachments += 1 }
        }
        #expect(singularAttachments >= 4)
    }

    @Test(.timeLimit(.minutes(3)))
    func coincidentRegionAndMultipleExactUVFibers() throws {
        let first = plane()
        let region = try #require(try rich(first,first).originalNativeRelations)
        #expect(region.componentCount == 1)
        #expect(try region.component(at: 0).parameterDimension == 2)
        #expect(try region.component(at: 0).imageDimension == 2)
        let folded = surface(uDegree: 2,vDegree: 1) { u,v in
            .init(x: u == 1 ? -1 : 1,y: v == 0 ? -1 : 1,z: 0)
        }
        let relation = try #require(try rich(first,folded).originalNativeRelations)
        #expect(try relation.component(at: 0).imageDimension == 2)
        var budget = usage()
        let quarter = try ExactRationalCoefficient.originalDouble(0.25, usage: &budget)
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &budget)
        let fiber = try relation.fiber(surface: 0,u: quarter,v: .zero,maximumAlgebraicDepth: 32,usage: &budget)
        #expect(fiber.componentCount == 2)
        #expect(try fiber.contains(parameters: [quarter,.zero,half,.zero],maximumAlgebraicDepth: 32,usage: &budget))
        #expect(try fiber.contains(parameters: [quarter,.zero,half.negated,.zero],maximumAlgebraicDepth: 32,usage: &budget))
        for ordinal in 0..<fiber.componentCount {
            let component = try fiber.component(at: ordinal)
            #expect(component.parameterDimension == 0 && component.imageDimension == 0)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func collapsedImageRetainsParameterProductAndExceptionalFibers() throws {
        let constant = surface { _,_ in .init(x: 0,y: 0,z: 0) }
        let receipt = try #require(try rich(constant,constant).originalNativeRelations)
        let component = try receipt.component(at: 0)
        #expect(receipt.componentCount == 1 && component.parameterDimension == 4 && component.imageDimension == 0)
        var maximumFiber = 0
        for ordinal in 0..<receipt.cellCount {
            for image in try receipt.cell(at: ordinal).imageStrata {
                #expect(image.imageDimension == 0 && image.fiberDimension == image.parameterDimension)
                maximumFiber = max(maximumFiber,image.fiberDimension)
            }
        }
        var graphBudget = finiteUsage()
        let ownedCell = try receipt.cell(at: 0), stratum = try #require(ownedCell.imageStrata.first)
        var parameters: [ExactRationalCoefficient] = []
        for coordinate in ownedCell.parameterSample {
            let enclosure = try coordinate.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
            #expect(enclosure.lower == enclosure.upper)
            parameters.append(enclosure.lower)
        }
        #expect(try receipt.contains(position: [.zero,.zero,.zero],parameters: parameters,inCell: ownedCell.identifier,
            imageStratumOrdinal: stratum.ordinal,maximumAlgebraicDepth: 32,usage: &graphBudget))
        #expect(!(try receipt.contains(position: [.one,.zero,.zero],parameters: parameters,inCell: ownedCell.identifier,
            imageStratumOrdinal: stratum.ordinal,maximumAlgebraicDepth: 32,usage: &graphBudget)))
        #expect(maximumFiber == 4)
        var budget = usage()
        let fiber = try receipt.fiber(surface: 0,u: .zero,v: .zero,maximumAlgebraicDepth: 32,usage: &budget)
        #expect(fiber.componentCount == 1)
        #expect(try fiber.component(at: 0).parameterDimension == 2)
        #expect(try fiber.component(at: 0).imageDimension == 0)
    }
    @Test(.timeLimit(.minutes(3)))
    func curveAndIsolatedComponentsArePublishedTogether() throws {
        let square = [1.0,-1,1], linear = [-1.0,-0.5,0,0.5,1]
        let remainder = [-27.0,4.5,4,-4.5,3]
        // Original z = 12 v (u^2 + (v - 1/2)^2): a whole v=0 curve and one disjoint tuple.
        let target = surface(uDegree: 2,vDegree: 4) { u,v in
            .init(x: Double(u - 1),y: linear[v],z: 12 * linear[v] * square[u] + remainder[v])
        }
        let result = try rich(plane(),target), receipt = try #require(result.originalNativeRelations)
        #expect(receipt.componentCount == 2 && result.intersections.count == 1)
        #expect(result.originalNativePoints?.count == 1)
        let classified = try dimensions(receipt)
        #expect(classified.contains { $0.0 == 1 && $0.1 == 1 })
        #expect(classified.contains { $0.0 == 0 && $0.1 == 0 })
        var budget = usage()
        let half = try ExactRationalCoefficient.originalDouble(0.5,usage: &budget)
        #expect(try receipt.contains(parameters: [.zero,half,.zero,half],maximumAlgebraicDepth: 32,usage: &budget))
        #expect(try receipt.contains(parameters: [.one,.zero,.one,.zero],maximumAlgebraicDepth: 32,usage: &budget))
        #expect(!(try receipt.contains(parameters: [.zero,.one,.zero,.one],maximumAlgebraicDepth: 32,usage: &budget)))
    }

    @Test(.timeLimit(.minutes(3)))
    func retainedAlgebraicStationKeepsWholeOppositeFiber() throws {
        let folded = surface(uDegree: 2,vDegree: 1) { u,v in
            .init(x: u == 1 ? -1 : 1,y: v == 0 ? -1 : 1,z: 0)
        }
        let square = [1.0,-1,1]
        let bowl = surface(uDegree: 2,vDegree: 2) { u,v in
            .init(x: Double(u - 1) + 0.5,y: Double(v - 1),z: square[u] + square[v])
        }
        let points = try #require(try rich(folded,bowl).originalNativePoints)
        let station = try points.point(at: 1).parameter(axis: 0,in: points)
        let constant = surface { _,_ in .init(x: 0,y: 0,z: 0) }
        let receipt = try #require(try rich(constant,constant).originalNativeRelations)
        let zero = try OriginalAlgebraicCoordinate.rational(.zero,usage: usage())
        let fiber = try receipt.fiber(surface: 0,u: station,v: zero,maximumAlgebraicDepth: 32,
            maximumCoefficientDepth: 32,usage: finiteUsage())
        #expect(fiber.source === receipt && fiber.surfaceRole == 0 && fiber.imageDimension == 0)
        #expect(fiber.relation.components.count == 1 && fiber.relation.components[0].dimension == 2)
        #expect(throws: KernelError.self) {
            try receipt.fiber(surface: 0,u: station,v: zero,maximumAlgebraicDepth: 32,
                maximumCoefficientDepth: 0,usage: usage())
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func positivePublicationIsAtomicUnderIndependentFailureAndCancellation() async throws {
        let first = Surface3D.bSpline(plane())
        let second = Surface3D.bSpline(surface { u,v in .init(x: u == 0 ? -1 : 1,y: 0,z: v == 0 ? -1 : 1) })
        let solver = DefaultSurfaceSurfaceIntersector()
        #expect(throws: GeometryConversionError.self) {
            try solver.intersectionResult(first: first,second: second,tolerance: tolerance,maximumSpanCount: 1,
                maximumSubdivisionDepth: 0,remainingSourceDepth: 1,
                consumeWork: { throw GeometryConversionError.resourceLimitExceeded("Denied SSI work.") },
                consumeStorage: { _ in },maximumAlgebraicDepth: 32)
        }
        #expect(throws: GeometryConversionError.self) {
            try solver.intersectionResult(first: first,second: second,tolerance: tolerance,maximumSpanCount: 1,
                maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: {},
                consumeStorage: { _ in throw GeometryConversionError.resourceLimitExceeded("Denied SSI bytes.") },maximumAlgebraicDepth: 32)
        }
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(first: first,second: second,options: .init(maximumSubdivisionCells: 1),tolerance: tolerance)
        }
        let calls = Mutex(0), finalStorage = Mutex(0)
        let retained = try solver.intersectionResult(first: first,second: second,tolerance: tolerance,maximumSpanCount: 1,
            maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: {},
            consumeStorage: { count in calls.withLock { $0 += 1 }; finalStorage.withLock { $0 = count } },maximumAlgebraicDepth: 32)
        let final = calls.withLock { $0 }, current = Mutex(0)
        let refused = Mutex(false), storageCalls = Mutex(0)
        do {
            _ = try solver.intersectionResult(first: first,second: second,tolerance: tolerance,maximumSpanCount: 1,
                maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: {},consumeStorage: { count in
                    if storageCalls.withLock({ $0 += 1; return $0 }) == final {
                        #expect(count == finalStorage.withLock { $0 } && count > 0)
                        refused.withLock { $0 = true }
                        throw GeometryConversionError.resourceLimitExceeded("Denied final SSI publication storage.")
                    }
                },maximumAlgebraicDepth: 32)
            Issue.record("Storage refusal at final publication exposed a partial result.")
        } catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else { throw error }
        }
        #expect(refused.withLock { $0 })
        var retainedBudget = finiteUsage()
        #expect(try #require(retained.originalNativeRelations).contains(parameters: [.zero,.zero,.zero,.zero],
            maximumAlgebraicDepth: 32,usage: &retainedBudget))
        let task = Task {
            try solver.intersectionResult(first: first,second: second,tolerance: tolerance,maximumSpanCount: 1,
                maximumSubdivisionDepth: 0,remainingSourceDepth: 1,consumeWork: {},consumeStorage: { _ in
                    if current.withLock({ $0 += 1; return $0 }) == final { withUnsafeCurrentTask { $0?.cancel() } }
                },maximumAlgebraicDepth: 32)
        }
        do { _ = try await task.value; Issue.record("Cancellation after final relation storage exposed a partial result.") }
        catch is CancellationError {}
        let near = plane()
        let offset = surface { u,v in .init(x: u == 0 ? -1 : 1,y: v == 0 ? -1 : 1,z: 1.0 / 1_048_576) }
        let absence = try rich(near,offset)
        #expect(absence.intersections.isEmpty && absence.originalNativePoints?.count == 0)
        #expect(absence.originalNativeRelations == nil)
    }

}
