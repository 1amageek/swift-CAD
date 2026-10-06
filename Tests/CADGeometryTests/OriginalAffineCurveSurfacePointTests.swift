import CADCore
@testable import CADGeometry
import Synchronization
import Testing

@Suite("Public original affine Native isolated points", .serialized)
struct OriginalAffineCurveSurfacePointTests {
    private let tolerance = ModelingTolerance.standard

    private func image(_ source: Surface3D, operations: [OriginalAffineOperation]? = nil) throws -> OriginalAffineWordSurface3D {
        var admission = usage()
        let identity = try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)
        let word = try OriginalAffineOperationWord(factors: operations ?? [.forward(identity)],
            tolerance: tolerance, maximumDepth: 32, usage: &admission)
        return try .init(source: source, operationWord: word, tolerance: tolerance,
            remainingSourceDepth: 2, maximumSubdivisionDepth: 8, maximumAlgebraicDepth: 32, usage: &admission)
    }

    private func plane(weighted: Bool = false) throws -> OriginalAffineWordSurface3D {
        try image(.bSpline(.init(uDegree: 1, vDegree: 1, uKnots: [2,2,4,4], vKnots: [3,3,5,5],
            controlPoints: [[.init(x:0,y:0,z:0), .init(x:1,y:0,z:0)],
                            [.init(x:0,y:1,z:0), .init(x:1,y:1,z:0)]],
            weights: weighted ? [[1,2],[1,2]] : [[1,1],[1,1]])))
    }

    private func vertical(weighted: Bool = false, x: Double = 0.5, y: Double = 0.5) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: x,y: y,z: -1), .init(x: x,y: y,z: 1)], weights: weighted ? [1,2] : [1,1])
    }

    private func fold() throws -> OriginalAffineWordSurface3D {
        try image(.bSpline(.init(uDegree: 2, vDegree: 1, uKnots: [-1,-1,-1,1,1,1], vKnots: [3,3,5,5],
            controlPoints: [[.init(x:1,y:0,z:0), .init(x:-1,y:0,z:0), .init(x:1,y:0,z:0)],
                            [.init(x:1,y:1,z:0), .init(x:-1,y:1,z:0), .init(x:1,y:1,z:0)]])))
    }

    private func usage() -> OriginalRelationUsage {
        .init(consumeWork: { _ in }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
    }

    private func admitted(curve: BSplineCurve3D, surface: OriginalAffineWordSurface3D,
        options: CurveSurfaceIntersectionOptions = .init()) throws -> CurveSurfaceIntersectionResult {
        let work = Mutex(0), bytes = Mutex(0)
        let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve),
            surface: .procedural(.originalAffineWord(surface)), options: options, tolerance: tolerance,
            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
            consumeWork: { _ in work.withLock { $0 += 1 } },
            consumeStorage: { amount in bytes.withLock { $0 += amount } }, maximumAlgebraicDepth: 32)
        #expect(work.withLock { $0 } > 0 && bytes.withLock { $0 } > 0)
        print("Original curve/affine admitted work=\(work.withLock { $0 }) bytes=\(bytes.withLock { $0 })")
        return result
    }

    @Test(.timeLimit(.minutes(2)))
    func weightedNonunitNativeDomainsUseAllPublicRoutes() throws {
        let solver = DefaultCurveSurfaceIntersector(), surface = try plane(weighted: true)
        var curve = vertical(weighted: true); curve.knots = [-2,-2,4,4]
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalAffinePoints), point = try #require(result.points.first)
        #expect(result.points.count == 1 && receipt.count == 1 && result.originalNativePoints == nil)
        #expect(receipt.curve == curve && receipt.surface == surface && receipt.coverageCellCount > 0)
        #expect(abs(point.curveParameter) < 1e-9)
        #expect(abs(point.surfaceU - 8.0 / 3) < 1e-9 && point.surfaceV == 4)
        #expect(point.point == Point3D(x: 0.5,y: 0.5,z: 0) && point.kind == .transverse)
        #expect(point.residual <= tolerance.distance)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        #expect(try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)),
            options: .init(), tolerance: tolerance) == result.points)
        #expect(try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)),
            options: .init(), tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1, consumeWork: { _ in }, consumeStorage: { _ in }, maximumAlgebraicDepth: 32) == result.points)
        var budget = usage()
        let zero = ExactRationalCoefficient.zero
        let tuple = try receipt.point(at: 0)
        #expect(try tuple.compareParameter(axis: 0, to: zero, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        let u = try ExactRationalCoefficient.originalDouble(8, usage: &budget).divided(by: .originalDouble(3, usage: &budget), usage: &budget)
        #expect(try tuple.compareParameter(axis: 1, to: u, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
    }

    @Test(.timeLimit(.minutes(2)))
    func multipleUVPreimagesRemainSeparateInExactTupleOrder() throws {
        let curve = vertical(x: 0.25), surface = try fold(), solver = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)), tolerance: tolerance)
        let receipt = try #require(result.originalAffinePoints)
        #expect(result.points.count == 2 && receipt.count == 2)
        #expect(result.points[0].point == result.points[1].point)
        #expect(result.points[0].curveParameter == result.points[1].curveParameter)
        #expect(result.points[0].surfaceU == -0.5 && result.points[1].surfaceU == 0.5)
        #expect(try admitted(curve: curve, surface: surface).points == result.points)
        var budget = usage()
        for ordinal in 0..<2 {
            let station = try ExactRationalCoefficient.originalDouble(ordinal == 0 ? -0.5 : 0.5, usage: &budget)
            #expect(try receipt.point(at: ordinal).compareParameter(axis: 1, to: station,
                in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
        }
        #expect(throws: KernelError.self) {
            try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)),
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func repeatedTangentAndClosedCornerSingleton() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0.25), .init(x: 0.5,y: 0.5,z: -0.25), .init(x: 1,y: 0.5,z: 0.25)])
        let solver = DefaultCurveSurfaceIntersector()
        let tangent = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance)
        #expect(tangent.points.count == 1 && tangent.points.first?.kind == .tangent)
        let endpoint = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 0,y: 0,z: 1)])
        let selected = CurveSurfaceIntersectionOptions(curveRange: try .init(lower: 0,upper: 0),
            surfaceURange: try .init(lower: 2,upper: 2), surfaceVRange: try .init(lower: 3,upper: 3))
        let corner = try solver.intersectionResult(curve: .bSpline(endpoint), surface: .procedural(.originalAffineWord(plane())),
            options: selected, tolerance: tolerance)
        #expect(corner.points.count == 1 && corner.points.first?.curveParameter == 0)
        #expect(corner.points.first?.surfaceU == 2 && corner.points.first?.surfaceV == 3)
        #expect(try admitted(curve: endpoint, surface: plane(), options: selected).points == corner.points)
    }

    @Test(.timeLimit(.minutes(2)))
    func completeEmptyCoverageAndDomainExclusion() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let noRoot = BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: 1), .init(x: 0.5,y: 0.5,z: 2)])
        let empty = try solver.intersectionResult(curve: .bSpline(noRoot), surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance)
        let receipt = try #require(empty.originalAffinePoints)
        #expect(empty.points.isEmpty && receipt.count == 0 && receipt.coverageCellCount > 0 && receipt.effectiveDomains != nil)
        let outside = CurveSurfaceIntersectionOptions(surfaceURange: try .init(lower: 5,upper: 6))
        let excluded = try admitted(curve: vertical(), surface: plane(), options: outside)
        let proof = try #require(excluded.originalAffinePoints)
        #expect(excluded.points.isEmpty && proof.count == 0 && proof.effectiveDomains == nil)
        #expect(proof.requestedDomains.count == 3 && proof.nativeDomains.count == 3)
        #expect(try solver.intersections(curve: .bSpline(noRoot), surface: .procedural(.originalAffineWord(plane())), options: .init(), tolerance: tolerance).isEmpty)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func positiveAndMixedFailAtomically(discrete: Bool, admitted: Bool) throws {
        let mixed = try image(.bSpline(.init(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0)],
                           [.init(x:0,y:0,z:0),.init(x:1,y:1,z:0)]])))
        let curves = [
            BSplineCurve3D(degree: 1, knots: [0,0,1,1], controlPoints: [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)]),
            BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
                .init(x: 0,y: 0,z: 0), .init(x: 0.5,y: 0.25,z: -0.25), .init(x: 1,y: 0.5,z: 0.5)])]
        let solver = DefaultCurveSurfaceIntersector()
        for curve in curves {
            do {
                if discrete {
                    if admitted {
                        _ = try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(mixed)), options: .init(), tolerance: tolerance,
                            maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                            consumeWork: { _ in }, consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
                    } else { _ = try solver.intersections(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(mixed)), options: .init(), tolerance: tolerance) }
                } else if admitted { _ = try self.admitted(curve: curve, surface: mixed) }
                else { _ = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(mixed)), tolerance: tolerance) }
                Issue.record("A positive or mixed original relation escaped the bounded isolated contract.")
            } catch let error as KernelError { #expect(error.code == .nonDiscreteIntersection) }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func releasedInputsRetainOriginalTupleAndRejectForeignOwner() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let receipt = try { () throws -> OriginalAffineCurveSurfacePoints in
            var curve = vertical(), surface = try plane()
            let result = try solver.intersectionResult(curve: .bSpline(curve), surface: .procedural(.originalAffineWord(surface)), tolerance: tolerance)
            curve.controlPoints[0] = .init(x: 100,y: 100,z: 100)
            surface = try plane(weighted: true)
            return try #require(result.originalAffinePoints)
        }()
        let originalSurface = try plane()
        #expect(receipt.curve == vertical() && receipt.surface == originalSurface)
        let handle = try receipt.point(at: 0)
        let foreign = try #require(solver.intersectionResult(curve: .bSpline(vertical()), surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance).originalAffinePoints)
        #expect(receipt.owns(handle) && !foreign.owns(handle))
        #expect(throws: GeometryConversionError.self) { try handle.parameter(axis: 0, in: foreign) }
        let coordinate = try handle.parameter(axis: 1, in: receipt)
        let bounds = try coordinate.enclosed(maximumDepth: 32, maximumCoefficientDepth: 0, usage: usage())
        var budget = usage()
        let three = try ExactRationalCoefficient.originalDouble(3, usage: &budget)
        #expect(bounds.lower == three && bounds.upper == three)
        #expect(try handle.compareParameter(axis: 1, to: three, in: receipt, maximumAlgebraicDepth: 32, usage: &budget) == .zero)
    }

    @Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3])
    func independentCallerAdmissionFailuresPropagate(mode: Int) throws {
        let exhausted = KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Test admission exhausted.")
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        #expect(throws: (any Error).self) {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(mode == 3 ? irrational : vertical()),
                surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance, maximumSpanCount: 1,
                maximumSubdivisionDepth: 0, remainingSourceDepth: mode == 2 ? 0 : 1,
                consumeWork: { _ in if mode == 0 { throw exhausted } },
                consumeStorage: { _ in if mode == 1 { throw exhausted } }, maximumAlgebraicDepth: mode == 3 ? 0 : 32)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func sourceAndRefinementCeilingsRemainExplicit() throws {
        let solver = DefaultCurveSurfaceIntersector()
        let irrational = BSplineCurve3D(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)])
        for options in [CurveSurfaceIntersectionOptions(maximumSubdivisionCells: 1),
            CurveSurfaceIntersectionOptions(maximumPolynomialDegree: 1),
            CurveSurfaceIntersectionOptions(maximumIterations: 1)] {
            #expect(throws: KernelError.self) {
                try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.originalAffineWord(plane())),
                    options: options, tolerance: tolerance)
            }
        }
        let full = try solver.intersectionResult(curve: .bSpline(irrational), surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance)
        let receipt = try #require(full.originalAffinePoints)
        let handle = try receipt.point(at: 0)
        var rejected = OriginalRelationUsage(consumeWork: { _ in
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: "Exact query work exhausted.")
        }, retainStorage: { _ in }, visitCell: { _ in }, visitCoefficientCell: { _ in })
        #expect(throws: KernelError.self) {
            try handle.compareParameter(axis: 0, to: .zero, in: receipt, maximumAlgebraicDepth: 32, usage: &rejected)
        }
        #expect(throws: (any Error).self) {
            try handle.parameter(axis: 0, in: receipt).enclosed(maximumDepth: 0, maximumCoefficientDepth: 0, usage: usage())
        }
        let multi = BSplineCurve3D(degree: 1, knots: [0,0,0.5,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: -1), .init(x: 0.5,y: 0.5,z: 0), .init(x: 0.5,y: 0.5,z: 1)])
        do {
            _ = try solver.intersectionResult(curve: .bSpline(multi), surface: .procedural(.originalAffineWord(plane())), tolerance: tolerance)
            Issue.record("An uncomposed multiple-span curve escaped the bounded checkpoint.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true], [false,true])
    func finalStorageCancellationRejectsPointAndEmptyPublication(discrete: Bool, empty: Bool) async throws {
        let solver = DefaultCurveSurfaceIntersector(), curve = Curve3D.bSpline(vertical()), surface = try Surface3D.procedural(.originalAffineWord(plane()))
        let options = CurveSurfaceIntersectionOptions(surfaceURange: empty ? try .init(lower: 5,upper: 6) : nil)
        @Sendable func query(_ storage: @escaping @Sendable (Int) throws -> Void) throws -> [CurveSurfaceIntersection] {
            if discrete {
                return try solver.intersections(curve: curve, surface: surface, options: options, tolerance: tolerance,
                    maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                    consumeWork: { _ in }, consumeStorage: storage, maximumAlgebraicDepth: 32)
            }
            let result = try solver.intersectionResult(curve: curve, surface: surface, options: options, tolerance: tolerance,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { _ in }, consumeStorage: storage, maximumAlgebraicDepth: 32)
            #expect(result.originalAffinePoints?.count == (empty ? 0 : 1))
            return result.points
        }
        let baseline = Mutex(0)
        #expect(try query { _ in baseline.withLock { $0 += 1 } }.count == (empty ? 0 : 1))
        let finalCall = baseline.withLock { $0 }, visits = Mutex(0)
        let operation = Task {
            try query { _ in
                let ordinal = visits.withLock { $0 += 1; return $0 }
                if ordinal == finalCall { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await operation.value; Issue.record("Final cancellation returned a successful original affine receipt.") }
        catch is CancellationError { #expect(visits.withLock { $0 } == finalCall) }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [false,true])
    func originalForwardInverseShearReflectionAndDerivativeOrientation(inverse: Bool) throws {
        let original = try plane(weighted: true)
        let action = try AffineTransform3D(basisX:.init(x:2,y:0,z:0),basisY:.init(x:1,y:-2,z:0),
            basisZ:.init(x:0,y:0,z:2),translation:.init(x:5,y:7,z:11))
        let transformed = try image(original.source, operations:[inverse ? .inverse(action) : .forward(action)])
        // Independent exact dyadic authored coordinates, not numeric image getters.
        let point = inverse ? Point3D(x:-3.875,y:3.25,z:-5.5) : Point3D(x:6.5,y:6,z:11)
        let curve = BSplineCurve3D(degree:1,knots:[-2,-2,4,4],controlPoints:[
            .init(x:point.x,y:point.y,z:point.z-1),.init(x:point.x,y:point.y,z:point.z+1)],weights:[1,2])
        let solver = DefaultCurveSurfaceIntersector()
        let ordinary = try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(transformed)),tolerance:tolerance)
        let receipt = try #require(ordinary.originalAffinePoints), result = try #require(ordinary.points.first)
        #expect(receipt.count == 1 && result.point == point && result.kind == .transverse)
        #expect(result.curveParameter == 0 && abs(result.surfaceU - 8.0 / 3) < 1e-9 && result.surfaceV == 4)
        #expect(receipt.surface == transformed && receipt.source.affineSurface.image.operationWord == transformed.operationWord)
        #expect(try admitted(curve:curve,surface:transformed).points == ordinary.points)
        #expect(try solver.intersections(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(transformed)),
            options:.init(),tolerance:tolerance) == ordinary.points)
        #expect(try solver.intersections(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(transformed)),
            options:.init(),tolerance:tolerance,maximumSpanCount:1,maximumSubdivisionDepth:0,remainingSourceDepth:1,
            consumeWork:{ _ in },consumeStorage:{ _ in },maximumAlgebraicDepth:32) == ordinary.points)
        var admission = usage()
        let law = receipt.source.affineSurface
        let normal = try OriginalPolynomialCurveSurfaceNormal.prepare(homogeneous:law.homogeneous,usage:&admission)
        let orientation = try ExactRationalCoefficient.originalDouble(inverse ? -0.25 : -4,usage:&admission)
        let expected = try law.nativeLaw.normalNumerators[2].scaled(by:orientation,usage:&admission)
        #expect(normal[0].isZero && normal[1].isZero && normal[2] == expected)
        #expect(law.denominator == law.nativeLaw.homogeneous[3])
        let coordinate = try receipt.point(at:0).parameter(axis:0,in:receipt)
        let bounds = try coordinate.enclosed(maximumDepth:32,maximumCoefficientDepth:0,usage:usage())
        #expect(bounds.lower.isZero && bounds.upper.isZero)
    }

    @Test(.timeLimit(.minutes(2)))
    func invalidOriginalCurveCannotReturnEmptySuccess() throws {
        var curve = vertical(); curve.weights[0] = 0
        let surface = try plane()
        #expect(throws: GeometryError.self) {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve:.bSpline(curve),
                surface:.procedural(.originalAffineWord(surface)),tolerance:tolerance)
        }
    }

    @Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3])
    func unsupportedOriginalSourcesFailBeforeLegacyFallback(route: Int) throws {
        let baseline = try plane()
        let multi = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[2,2,3,4,4],vKnots:[3,3,5,5],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0.5,y:0,z:0),.init(x:1,y:0,z:0)],
                           [.init(x:0,y:1,z:0),.init(x:0.5,y:1,z:0),.init(x:1,y:1,z:0)]])
        let periodic = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3],vKnots:[3,3,5,5],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],
                           [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0),.init(x:0,y:1,z:0)]],isUPeriodic:true)
        let normalized = OriginalNormalizedAffineSource(family:.cartesian,location:.zero,
            axis1:.init(x:1,y:1,z:0),axis2:.init(x:-1,y:1,z:0),axis3:.unitZ,scale:1,lengthGain:.one,adjustments:[])
        let unsupported = try [image(.plane(.init(origin:.origin,normal:.unitZ))),image(.bSpline(multi)),
            image(.bSpline(periodic)),image(baseline.source,operations:[.normalizedForward(normalized)])]
        let periodicCurve = BSplineCurve3D(degree:1,knots:[-1,0,1,2,3],controlPoints:[
            .init(x:0.5,y:0.5,z:-1),.init(x:0.5,y:0.5,z:1),.init(x:0.5,y:0.5,z:-1)],isPeriodic:true)
        let inputs = unsupported.map { (vertical(),$0) } + [(periodicCurve,baseline)]
        let solver = DefaultCurveSurfaceIntersector()
        for (curve,surface) in inputs {
            do {
                switch route {
                case 0: _ = try solver.intersectionResult(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(surface)),tolerance:tolerance)
                case 1: _ = try admitted(curve:curve,surface:surface)
                case 2: _ = try solver.intersections(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(surface)),options:.init(),tolerance:tolerance)
                default: _ = try solver.intersections(curve:.bSpline(curve),surface:.procedural(.originalAffineWord(surface)),
                    options:.init(),tolerance:tolerance,maximumSpanCount:1,maximumSubdivisionDepth:0,remainingSourceDepth:1,
                    consumeWork:{ _ in },consumeStorage:{ _ in },maximumAlgebraicDepth:32)
                }
                Issue.record("Unsupported original affine source escaped its bounded issuer.")
            } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
        }
    }

}
