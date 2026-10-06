import CADCore
import CADGeometry
#if !hasFeature(Embedded)
import Foundation
#endif

@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
enum OriginalPointRelationProof {
    private enum ProofError: Error { case incorrectPublication, indirectValuePoint, indirectCodecSource, indirectCodecPoint }
    private static let tolerance = ModelingTolerance.standard

    private static func require(_ value: Bool) throws {
        guard value else { throw ProofError.incorrectPublication }
    }

    private static func plane(z: Double = 0) -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: z), .init(x: 1,y: 0,z: z)],
                [.init(x: 0,y: 1,z: z), .init(x: 1,y: 1,z: z)]])
    }

    private static func tilted() -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 1)],
                [.init(x: 0,y: 1,z: 1), .init(x: 1,y: 1,z: 2)]])
    }

    private static func curve(z0: Double = -1, z1: Double = 1) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0.5,y: 0.5,z: z0), .init(x: 0.5,y: 0.5,z: z1)])
    }

    private static func admittedCS(_ solver: any CurveSurfaceIntersectionResolving,
        curve: Curve3D, surface: Surface3D, allowance: OriginalPointRelationAllowance) throws -> CurveSurfaceIntersectionResult {
        try solver.intersectionResult(curve: curve, surface: surface, options: .init(),
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1, consumeWork: { _ in try allowance.consumeWork() },
            consumeStorage: { try allowance.consumeStorage($0) }, maximumAlgebraicDepth: 32)
    }

    private static func admittedSSI(_ solver: any SurfaceSurfaceIntersecting,
        first: Surface3D, second: Surface3D, allowance: OriginalPointRelationAllowance) throws -> SurfaceSurfaceIntersectionResult {
        try solver.intersectionResult(first: first, second: second, options: .init(),
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 1, consumeWork: { try allowance.consumeWork() },
            consumeStorage: { try allowance.consumeStorage($0) }, maximumAlgebraicDepth: 32)
    }

    private static func expectFailure(_ code: KernelErrorCode,
        _ operation: () throws -> Void) throws {
        do { try operation() }
        catch let error as KernelError {
            try require(error.code == code)
            return
        }
        throw ProofError.incorrectPublication
    }

    static nonisolated func run() throws {
        try planeDerivativeValueProof()
        try ruledPublicProof()
        let cs: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let discrete: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector()
        let c = Curve3D.bSpline(curve()), p = Surface3D.bSpline(plane())
        let ordinary = try cs.intersectionResult(curve: c, surface: p,
            options: .init(), tolerance: tolerance)
        let allowance = OriginalPointRelationAllowance()
        let admitted = try admittedCS(cs, curve: c, surface: p, allowance: allowance)
        try require(ordinary.points == admitted.points && ordinary.points.count == 1)
        try require(ordinary.points[0].point == Point3D(x: 0.5,y: 0.5,z: 0))
        try require(ordinary.points[0].curveParameter == 0.5 && ordinary.points[0].surfaceU == 0.5
            && ordinary.points[0].surfaceV == 0.5 && ordinary.originalNativePoints?.count == 1)
        guard let curveReceipt = ordinary.originalNativePoints else { throw ProofError.incorrectPublication }
        var originalUsage = OriginalRelationUsage(consumeWork: { _ in }, retainStorage: { _ in },
            visitCell: { _ in }, visitCoefficientCell: { _ in })
        let half = try ExactRationalCoefficient.originalDouble(0.5, usage: &originalUsage)
        let curveHandle = try curveReceipt.point(at: 0)
        try require(curveReceipt.owns(curveHandle))
        for axis in 0..<3 {
            try require(try curveHandle.compareParameter(axis: axis, to: half, in: curveReceipt,
                maximumAlgebraicDepth: 32, usage: &originalUsage) == .zero)
        }
        try require(allowance.counts.work > 0 && allowance.counts.storage > 0)
        try require(try discrete.intersections(curve: c, surface: p,
            options: .init(), tolerance: tolerance) == ordinary.points)
        let empty = try cs.intersectionResult(curve: .bSpline(curve(z0: 1,z1: 2)),
            surface: p, options: .init(), tolerance: tolerance)
        try require(empty.points.isEmpty && empty.originalNativePoints?.count == 0
            && empty.originalNativePoints?.effectiveDomains?.count == 3)
        try expectFailure(.nonDiscreteIntersection) {
            _ = try discrete.intersections(curve: .bSpline(.init(degree: 1, knots: [0,0,1,1], controlPoints: [
                    .init(x: 0,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 0)])),
                surface: p, options: .init(), tolerance: tolerance)
        }
        for budget in [OriginalPointRelationAllowance(work: 0), OriginalPointRelationAllowance(storage: 0)] {
            try expectFailure(.resourceLimitExceeded) { _ = try admittedCS(cs,curve: c,surface: p,allowance: budget) }
        }
        print("PORTABLE_CS_PUBLIC_POINT_EMPTY_ATOMIC_ADMISSION_OK")

        let ssi: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let second = Surface3D.bSpline(tilted())
        let normal = try ssi.intersectionResult(first: p,second: second,options: .init(),tolerance: tolerance)
        let ssiAllowance = OriginalPointRelationAllowance()
        let selected = try admittedSSI(ssi,first: p,second: second,allowance: ssiAllowance)
        try require(normal.intersections == selected.intersections && normal.intersections.count == 1
            && normal.originalNativePoints?.count == 1)
        guard case .point(let point) = normal.intersections[0] else { throw ProofError.incorrectPublication }
        try require(point.point == .origin && point.firstSurfaceParameter.u == 0
            && point.firstSurfaceParameter.v == 0 && point.secondSurfaceParameter.u == 0
            && point.secondSurfaceParameter.v == 0)
        guard let surfaceReceipt = normal.originalNativePoints, let surfaceHandle = point.originalNativePoint else {
            throw ProofError.incorrectPublication
        }
        try require(surfaceReceipt.owns(surfaceHandle))
        for axis in 0..<4 {
            try require(try surfaceHandle.compareParameter(axis: axis, to: .zero, in: surfaceReceipt,
                maximumAlgebraicDepth: 32, usage: &originalUsage) == .zero)
        }
        try require(ssiAllowance.counts.work > 0 && ssiAllowance.counts.storage > 0)
        try require(try ssi.intersections(first: p,second: second,options: .init(),
            tolerance: tolerance) == normal.intersections)
        let absent = try ssi.intersectionResult(first: .bSpline(plane(z: -1)),second: second,
            options: .init(),tolerance: tolerance)
        try require(absent.intersections.isEmpty && absent.originalNativePoints?.count == 0
            && absent.originalNativePoints?.effectiveDomains?.count == 4)
        try expectFailure(.nonDiscreteIntersection) {
            _ = try ssi.intersections(first: p,second: p,options: .init(),tolerance: tolerance)
        }
        for budget in [OriginalPointRelationAllowance(work: 0), OriginalPointRelationAllowance(storage: 0)] {
            try expectFailure(.resourceLimitExceeded) { _ = try admittedSSI(ssi,first: p,second: second,allowance: budget) }
        }
        print("PORTABLE_SSI_PUBLIC_POINT_EMPTY_ATOMIC_ADMISSION_OK")
#if !hasFeature(Embedded)
        let decodedCurve = try JSONDecoder().decode(Curve3D.self, from: JSONEncoder().encode(c))
        let decodedSurface = try JSONDecoder().decode(Surface3D.self, from: JSONEncoder().encode(p))
        try require(decodedCurve == c && decodedSurface == p)
        let decodedResult = try cs.intersectionResult(curve: decodedCurve, surface: decodedSurface,
            options: .init(), tolerance: tolerance)
        try require(decodedResult.points == ordinary.points && decodedResult.originalNativePoints?.count == 1)
        print("PORTABLE_NATIVE_CODEC_PUBLIC_SOURCE_ROUNDTRIP_OK")
#endif
    }

    private static func ruled(weighted: Bool = true, folded: Bool = false) -> RuledSurface3D {
        if folded {
            let lower = BSplineCurve3D(degree: 2, knots: [-1,-1,-1,1,1,1], controlPoints: [
                .init(x: 1,y: 0,z: 0), .init(x: -1,y: 0,z: 0), .init(x: 1,y: 0,z: 0)])
            let upper = BSplineCurve3D(degree: 2, knots: [-1,-1,-1,1,1,1], controlPoints: [
                .init(x: 1,y: 1,z: 0), .init(x: -1,y: 1,z: 0), .init(x: 1,y: 1,z: 0)])
            return .init(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper), uDomain: .closed(-1,1))
        }
        let lower = BSplineCurve3D(degree: 1, knots: [2,2,4,4], controlPoints: [
            .init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)], weights: weighted ? [1,2] : [1,1])
        let upper = BSplineCurve3D(degree: 1, knots: [2,2,4,4], controlPoints: [
            .init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0)], weights: weighted ? [3,6] : [1,1])
        return .init(startBoundary: .bSpline(lower), endBoundary: .bSpline(upper), uDomain: .closed(2,4))
    }

    private static func ruledCurve(weighted: Bool = true, x: Double = 0.5,
        z0: Double = -1, z1: Double = 1) -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: x,y: 0.5,z: z0), .init(x: x,y: 0.5,z: z1)], weights: weighted ? [1,2] : [1,1])
    }

    private static func admittedRuled(_ discrete: Bool, curve: Curve3D, surface: Surface3D,
        options: CurveSurfaceIntersectionOptions = .init(), allowance: OriginalPointRelationAllowance,
        sourceDepth: Int = 1, algebraDepth: Int = 32,
        cancelAtStorageOrdinal: Int? = nil) throws -> [CurveSurfaceIntersection] {
        let storage: @Sendable (Int) throws -> Void = { count in
            try allowance.consumeStorage(count)
            if let ordinal = cancelAtStorageOrdinal, allowance.counts.storageCalls == ordinal {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        if discrete {
            let solver: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector()
            return try solver.intersections(curve: curve, surface: surface, options: options,
                tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
                remainingSourceDepth: sourceDepth, consumeWork: { _ in try allowance.consumeWork() },
                consumeStorage: storage, maximumAlgebraicDepth: algebraDepth)
        }
        let solver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let result = try solver.intersectionResult(curve: curve, surface: surface, options: options,
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: sourceDepth, consumeWork: { _ in try allowance.consumeWork() },
            consumeStorage: storage, maximumAlgebraicDepth: algebraDepth)
        try require(result.originalPolynomialPoints?.count == result.points.count)
        return result.points
    }

    private static func ruledPublicProof() throws {
        let rich: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        let discrete: any CurveSurfaceIntersecting = DefaultCurveSurfaceIntersector()
        let c = Curve3D.bSpline(ruledCurve()), surface = Surface3D.procedural(.ruled(ruled()))
        let result = try rich.intersectionResult(curve: c, surface: surface, options: .init(), tolerance: tolerance)
        try require(result.points.count == 1 && result.originalPolynomialPoints?.count == 1)
        let point = result.points[0]
        try require(point.point == Point3D(x: 0.5,y: 0.5,z: 0) && point.kind == .transverse)
        try require(abs(point.curveParameter - 1.0 / 3) < 1e-9
            && abs(point.surfaceU - 8.0 / 3) < 1e-9 && point.surfaceV == 0.5)
        for mode in [false, true] {
            let allowance = OriginalPointRelationAllowance()
            try require(try admittedRuled(mode, curve: c, surface: surface, allowance: allowance) == result.points)
            try require(allowance.counts.work > 0 && allowance.counts.storage > 0)
        }
        try require(try discrete.intersections(curve: c, surface: surface,
            options: .init(), tolerance: tolerance) == result.points)
        print("PORTABLE_RULED_WEIGHTED_FOUR_PUBLIC_ROUTES_OK")

        let retained: OriginalPolynomialCurveSurfacePoints
        do {
            var originalCurve = ruledCurve(), originalSurface = ruled()
            let original = try rich.intersectionResult(curve: .bSpline(originalCurve),
                surface: .procedural(.ruled(originalSurface)), options: .init(), tolerance: tolerance)
            guard let receipt = original.originalPolynomialPoints else { throw ProofError.incorrectPublication }
            originalCurve.controlPoints[0] = .init(x: 100,y: 100,z: 100)
            originalSurface = ruled(weighted: false)
            retained = receipt
        }
        try require(retained.curve == ruledCurve() && retained.surface == ruled())
        let handle = try retained.point(at: 0)
        try require(retained.owns(handle))
        let ledger = OriginalPointRelationAllowance()
        var usage = OriginalRelationUsage(consumeWork: { try ledger.consumeWork($0) },
            retainStorage: { try ledger.consumeWordStorage($0) }, visitCell: { _ in try ledger.consumeWork() },
            visitCoefficientCell: { _ in try ledger.consumeWork() })
        let three = try ExactRationalCoefficient.originalDouble(3, usage: &usage)
        let third = try ExactRationalCoefficient.one.divided(by: three, usage: &usage)
        let u = try ExactRationalCoefficient.originalDouble(8, usage: &usage).divided(by: three, usage: &usage)
        try require(try handle.compareParameter(axis: 0, to: third, in: retained,
            maximumAlgebraicDepth: 32, usage: &usage) == .zero)
        try require(try handle.compareParameter(axis: 1, to: u, in: retained,
            maximumAlgebraicDepth: 32, usage: &usage) == .zero)
        print("PORTABLE_RULED_ORIGINAL_TUPLE_OWNER_LIFETIME_OK")

        let folded = Surface3D.procedural(.ruled(ruled(weighted: false, folded: true)))
        let foldedCurve = Curve3D.bSpline(ruledCurve(weighted: false, x: 0.25))
        let multiple = try rich.intersectionResult(curve: foldedCurve, surface: folded,
            options: .init(), tolerance: tolerance)
        try require(multiple.points.count == 2 && multiple.originalPolynomialPoints?.count == 2)
        try require(multiple.points[0].point == multiple.points[1].point
            && multiple.points[0].surfaceU == -0.5 && multiple.points[1].surfaceU == 0.5)
        try expectFailure(.resourceLimitExceeded) {
            _ = try rich.intersectionResult(curve: foldedCurve, surface: folded,
                options: .init(maximumCandidateCount: 1), tolerance: tolerance)
        }
        let empty = try rich.intersectionResult(curve: .bSpline(ruledCurve(z0: 1,z1: 2)),
            surface: surface, options: .init(), tolerance: tolerance)
        try require(empty.points.isEmpty && empty.originalPolynomialPoints?.count == 0
            && (empty.originalPolynomialPoints?.coverageCellCount ?? 0) > 0
            && empty.originalPolynomialPoints?.effectiveDomains?.count == 3)
        let continuous = Curve3D.bSpline(.init(degree: 1, knots: [0,0,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 0)]))
        for mode in [false, true] {
            try expectFailure(.nonDiscreteIntersection) {
                _ = try admittedRuled(mode, curve: continuous, surface: surface,
                    allowance: OriginalPointRelationAllowance())
            }
        }
        try expectFailure(.nonDiscreteIntersection) {
            _ = try rich.intersectionResult(curve: continuous, surface: surface, options: .init(), tolerance: tolerance)
        }
        try expectFailure(.nonDiscreteIntersection) {
            _ = try discrete.intersections(curve: continuous, surface: surface, options: .init(), tolerance: tolerance)
        }
        print("PORTABLE_RULED_MULTIPLE_UV_EMPTY_NONDISCRETE_ATOMIC_OK")

        for budget in [OriginalPointRelationAllowance(work: 0), OriginalPointRelationAllowance(storage: 0)] {
            try expectFailure(.resourceLimitExceeded) {
                _ = try admittedRuled(false, curve: c, surface: surface, allowance: budget)
            }
        }
        try expectFailure(.resourceLimitExceeded) {
            _ = try admittedRuled(false, curve: c, surface: surface,
                allowance: OriginalPointRelationAllowance(), sourceDepth: 0)
        }
        let irrational = Curve3D.bSpline(.init(degree: 2, knots: [0,0,0,1,1,1], controlPoints: [
            .init(x: 0,y: 0.5,z: -0.5), .init(x: 0.5,y: 0.5,z: -0.5), .init(x: 1,y: 0.5,z: 0.5)]))
        try expectFailure(.resourceLimitExceeded) {
            _ = try admittedRuled(false, curve: irrational, surface: surface,
                allowance: OriginalPointRelationAllowance(), algebraDepth: 0)
        }
        print("PORTABLE_RULED_INDEPENDENT_WORK_STORAGE_SOURCE_ALGEBRA_LIMITS_OK")
    }

    private static nonisolated func ruledCancellationProof() async throws {
        let c = Curve3D.bSpline(ruledCurve()), surface = Surface3D.procedural(.ruled(ruled()))
        for discrete in [false, true] {
            for empty in [false, true] {
                let options = CurveSurfaceIntersectionOptions(
                    surfaceURange: empty ? try .init(lower: 5,upper: 6) : nil)
                let baseline = OriginalPointRelationAllowance()
                try require(try admittedRuled(discrete, curve: c, surface: surface,
                    options: options, allowance: baseline).count == (empty ? 0 : 1))
                let finalCall = baseline.counts.storageCalls
                try require(finalCall > 0)
                let cancelled = OriginalPointRelationAllowance()
                let operation = Task {
                    try admittedRuled(discrete, curve: c, surface: surface,
                        options: options, allowance: cancelled, cancelAtStorageOrdinal: finalCall)
                }
                do { _ = try await operation.value }
                catch is CancellationError {
                    try require(cancelled.counts.storageCalls == finalCall)
                    continue
                }
                throw ProofError.incorrectPublication
            }
        }
        print("PORTABLE_RULED_FINAL_STORAGE_CANCELLATION_POINT_EMPTY_OK")
    }

    private static func planeDerivativeValueProof() throws {
        var usage = OriginalRelationUsage(consumeWork: { _ in }, retainStorage: { _ in },
            visitCell: { _ in }, visitCoefficientCell: { _ in })
        func boundary(_ a: Point3D, _ b: Point3D) throws -> OriginalCurveRootSpan3D {
            try .init(source: .bSpline(.init(degree: 1, knots: [0,0,1,1], controlPoints: [a,b])),
                start: .authored(0), end: .authored(1), maximumParameterWidth: tolerance.relative,
                maximumSubdivisionDepth: 0, tolerance: tolerance,
                storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 32)
        }
        func retainedSource() throws -> ProceduralSurface3D {
            let bottom = try boundary(.origin, .init(x: 1,y: 0,z: 0))
            let top = try boundary(.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 0))
            let left = try boundary(.origin, .init(x: 0,y: 1,z: 0))
            let right = try boundary(.init(x: 1,y: 0,z: 0), .init(x: 1,y: 1,z: 0))
            let boundaries = try OriginalCoonsSurface3D(vMinimumBoundary: bottom, vMaximumBoundary: top,
                uMinimumBoundary: left, uMaximumBoundary: right, tolerance: tolerance, usage: &usage)
            let construction = try OriginalBoundaryCorrectedSurface3D(construction: plane(), boundaries: boundaries,
                maximumSpanCount: 1, maximumSubdivisionDepth: 0, tolerance: tolerance, usage: &usage)
            let payload = try OriginalPlaneDerivativeSurface3D(construction: construction, boundaries: boundaries,
                startConstraints: [], endConstraints: [], remainingSourceDepth: 32, tolerance: tolerance, usage: &usage)
            return .originalPlaneDerivative(payload)
        }
        let copy: ProceduralSurface3D
        do {
            let original = try retainedSource()
            copy = original
            try require(Set([original, copy]).count == 1)
        }
        guard case .originalPlaneDerivative(let retained) = copy else { throw ProofError.indirectValuePoint }
        let reversed = retained.boundaries.vMinimumBoundary.reversed()
        try require(reversed.reversed() == retained.boundaries.vMinimumBoundary)
        let queryAllowance = OriginalPointRelationAllowance()
        let reversedJet = try reversed.preparedFirstOrder(over: .init(lower: 0.25, upper: 0.25),
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0, remainingSourceDepth: 0,
            consumeWork: { try queryAllowance.consumeWork() }, consumeStorage: queryAllowance.consumeStorage)
        try require(reversedJet.position.x.lower <= 0.75 && reversedJet.position.x.upper >= 0.75)
        try require(reversedJet.firstDerivative.x.lower <= -1 && reversedJet.firstDerivative.x.upper >= -1)
        print("PORTABLE_ROOT_SPAN_REVERSED_OWNER_QUERY_OK")
        let source = Surface3D.procedural(copy)
        let expected = Point3D(x: 0.5,y: 0.5,z: 0)
        let evaluated = try source.point(u: 0.5, v: 0.5, tolerance: tolerance)
        guard (evaluated - expected).length <= tolerance.distance else {
            throw ProofError.indirectValuePoint
        }
        print("PORTABLE_INDIRECT_PLANE_SOURCE_COPY_HASH_LIFETIME_OK")
#if !hasFeature(Embedded)
        let data = try JSONEncoder().encode(source)
        func decoder(storage: Int) throws -> (JSONDecoder, NativeRationalSourceAllowance) {
            let allowance = try NativeRationalSourceAllowance(maximumWork: 80_000_000,
                maximumCells: 80_000_000, maximumStorage: storage, maximumDepth: 64, operationCheck: {})
            let decoder = JSONDecoder()
            decoder.userInfo[NativeRationalSourceDecodingContext.key] = allowance
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumSourceDepthKey] = 64
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepthKey] = 0
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumAlgebraicDepthKey] = 32
            decoder.userInfo[OriginalAffineWordDecodingContext.toleranceKey] = tolerance
            return (decoder, allowance)
        }
        let (admittedDecoder, allowance) = try decoder(storage: 268_435_456)
        let decoded = try admittedDecoder.decode(Surface3D.self, from: data)
        guard decoded == source && Set([decoded, source]).count == 1 else { throw ProofError.indirectCodecSource }
        guard try decoded.point(u: 0.5, v: 0.5, tolerance: tolerance) == evaluated else {
            throw ProofError.indirectCodecPoint
        }
        let admittedStorage = try allowance.snapshot().storage
        try require(admittedStorage > 0)
        let (exhaustedDecoder, _) = try decoder(storage: admittedStorage - 1)
        try expectFailure(.resourceLimitExceeded) { _ = try exhaustedDecoder.decode(Surface3D.self, from: data) }
        print("PORTABLE_INDIRECT_PLANE_SOURCE_CODEC_REQUERY_STORAGE_FAILURE_OK")
#endif
    }

    static nonisolated func cancellation() async throws {
        try await ruledCancellationProof()
        let operation = Task {
            let solver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
            return try solver.intersectionResult(curve: .bSpline(curve()), surface: .bSpline(plane()),
                options: .init(), tolerance: tolerance, maximumSpanCount: 1,
                maximumSubdivisionDepth: 0, remainingSourceDepth: 1,
                consumeWork: { _ in withUnsafeCurrentTask { $0?.cancel() } },
                consumeStorage: { _ in }, maximumAlgebraicDepth: 32)
        }
        do { _ = try await operation.value }
        catch is CancellationError { print("PORTABLE_ORIGINAL_ADMISSION_CANCELLATION_OK"); return }
        throw ProofError.incorrectPublication
    }
}
