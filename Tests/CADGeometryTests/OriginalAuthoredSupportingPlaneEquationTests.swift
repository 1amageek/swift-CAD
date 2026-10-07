import CADCore
@testable import CADGeometry
import Testing

@Suite("Original authored-U supporting plane authority")
struct OriginalAuthoredSupportingPlaneEquationTests {
    private enum Failure: Error, Equatable { case work, storage, unexpectedCell }
    private struct Budget: RationalAlgebraAdmitting, Sendable {
        var work = 0, words = 0, workCalls = 0, storageCalls = 0
        var cancelAtWorkCall: Int?, cancelAtStorageCall: Int?
        var maximumWork = 10_000_000, maximumWords = 10_000_000
        mutating func consumeExactWork(_ count: Int) throws {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard count >= 0, count <= maximumWork - work else { throw Failure.work }
            work += count; workCalls += 1
            if workCalls == cancelAtWorkCall { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard count >= 0, count <= maximumWords - words else { throw Failure.storage }
            words += count; storageCalls += 1
            if storageCalls == cancelAtStorageCall { withUnsafeCurrentTask { $0?.cancel() } }
        }
        mutating func visitExactCell(depth: Int) throws { throw Failure.unexpectedCell }
    }
    private let delta = 1e-12
    private let tolerance = ModelingTolerance.standard
    private var plane: Plane3D {
        .init(origin: .origin, normal: .unitZ, uDirection: .init(x: 1, y: 0, z: delta))
    }
    private func equation(_ source: Surface3D? = nil, depth: Int = 1,
        usage: inout Budget) throws -> OriginalSupportingPlaneEquation {
        try .prepared(source: source ?? .plane(plane), tolerance: tolerance,
            remainingSourceDepth: depth, usage: &usage)
    }
    private func traversal(usage: inout Budget) throws -> OriginalCurveRootSpan3D {
        let native = BSplineCurve3D(degree: 1, knots: [2, 2, 4, 4],
            controlPoints: [.origin, .init(x: 1, y: 0, z: delta)], weights: [1, 1])
        return try .init(source: .bSpline(native), start: .authored(2), end: .authored(4),
            nativeSpanIndex: 1, maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: 0,
            tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
            maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
    }
    private func image() throws -> OriginalImageSurface3D {
        let transform = try AffineTransform3D(basisX: .init(x: -2, y: 0, z: 0),
            basisY: .init(x: 1, y: 1, z: 0), basisZ: .init(x: 0, y: 0, z: 4),
            translation: .init(x: 8, y: -3, z: 0))
        return try .init(source: .plane(plane), uGain: -2, vGain: 4,
            transform: transform, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneEquationRetainsToleratedNonorthogonalU() throws {
        try plane.validate(tolerance: tolerance)
        var usage = Budget()
        let support = try equation(usage: &usage)
        let d = try ExactRationalCoefficient.originalDouble(delta, usage: &usage)
        #expect(support.normal.x == d.negated)
        #expect(support.normal.y.isZero && support.normal.z == .one && support.offset.isZero)
        #expect(try support.contains(.init(x: 1, y: 2, z: delta), usage: &usage))
        #expect(try !support.contains(.init(x: 1, y: 2, z: 0), usage: &usage))
        let original = try traversal(usage: &usage)
        let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(original, usage: &usage)
        #expect(pieces.count == 1)
        for piece in pieces {
            #expect(piece.lower == .zero && piece.upper == .one)
            #expect(try support.polynomial(piece.homogeneous, includeOffset: true, usage: &usage).isZero)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneDerivativeProjectionPreservesOriginalChartTangent() throws {
        var usage = Budget()
        let constraint = OriginalPlaneDerivativeConstraint(surface: .plane(plane), order: .curvature)
        let projection = try OriginalPlaneDerivativeProjection(constraints: [constraint], derivativeOrder: 1,
            remainingSourceDepth: 0, tolerance: tolerance, usage: &usage)
        let u = try OriginalSupportingPlaneEquation.Vector.original(Vector3D(x: 1, y: 0, z: delta), usage: &usage)
        let projected = try projection.projectedExact(u, usage: &usage)
        #expect(projected.x == u.x && projected.y == u.y && projected.z == u.z)
        #expect(try projection.includes(constraint, usage: &usage))
        let original = try traversal(usage: &usage)
        let connector = try OriginalPlaneDerivativeCurve3D(source: original,
            startConstraints: [constraint], endConstraints: [constraint], tolerance: tolerance,
            usage: &usage, remainingSourceDepth: 1)
        #expect(connector.source == original && connector.source.source == original.source)
        #expect(connector.startConstraints == [constraint] && connector.endConstraints == [constraint])
        #expect(connector.domain == .closed(0, 1))
        let support = try equation(usage: &usage)
        let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(of: connector, usage: &usage)
        #expect(!pieces.isEmpty)
        for piece in pieces {
            #expect(try support.polynomial(piece.homogeneous, includeOffset: true, usage: &usage).isZero)
        }
        for atEnd in [false, true] {
            let tangent = try connector.projectedOriginalDerivative(u, atEnd: atEnd, order: 1, usage: &usage)
            #expect(tangent.x == u.x && tangent.y == u.y && tangent.z == u.z)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneEquationRetainsExactAffineTransportAndSource() throws {
        let retained = try image()
        var usage = Budget()
        let support = try equation(.parameterImage(retained), usage: &usage)
        #expect(retained.source == .plane(plane) && retained.uGain == -2 && retained.vGain == 4)
        // Power-of-two scaling makes these binary point coefficients exact images.
        #expect(try support.contains(.init(x: 6, y: -3, z: 4 * delta), usage: &usage))
        #expect(try !support.contains(.init(x: 6, y: -3, z: 0), usage: &usage))
        let local = try support.pulledBack(by: retained.transform, usage: &usage)
        let original = try equation(usage: &usage)
        let determinant = try ExactRationalCoefficient.originalDouble(-8, usage: &usage)
        #expect(local.normal.x == (try original.normal.x.multiplied(by: determinant, usage: &usage)))
        #expect(local.normal.z == determinant && local.offset.isZero)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneEquationMalformedSourcesRemainTyped() throws {
        var usage = Budget()
        let degenerate = Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitZ)
        #expect(throws: GeometryConversionError.self) { _ = try equation(.plane(degenerate), usage: &usage) }
        let nonfinite = Plane3D(origin: .origin, normal: .unitZ, uDirection: .init(x: 1, y: 0, z: .infinity))
        #expect(throws: KernelError.self) { _ = try equation(.plane(nonfinite), usage: &usage) }
        let retained = try image()
        #expect(throws: GeometryConversionError.self) { _ = try equation(.parameterImage(retained), depth: 0, usage: &usage) }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneEquationUsesIndependentCallerWorkAndStorage() throws {
        var successful = Budget()
        _ = try equation(usage: &successful)
        #expect(successful.work > 0 && successful.words > 0)
        var work = Budget(maximumWork: successful.work - 1)
        #expect(throws: Failure.work) { _ = try equation(usage: &work) }
        #expect(work.words > 0)
        var storage = Budget(maximumWords: successful.words - 1)
        #expect(throws: Failure.storage) { _ = try equation(usage: &storage) }
        #expect(storage.work > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func nilUAndDirectAnalyticEquationsRetainRawNormal() throws {
        var usage = Budget()
        let raw = Vector3D(x: 0.25, y: -0.5, z: 2)
        let origin = Point3D(x: 4, y: 2, z: 1)
        let legacy = try equation(.plane(.init(origin: origin, normal: raw)), usage: &usage)
        let analytic = try equation(.analytic(.plane(origin: origin, normal: raw)), usage: &usage)
        let original = try OriginalSupportingPlaneEquation.Vector.original(raw, usage: &usage)
        #expect(legacy.normal.x == original.x && legacy.normal.y == original.y && legacy.normal.z == original.z)
        #expect(analytic.normal.x == legacy.normal.x && analytic.normal.y == legacy.normal.y && analytic.normal.z == legacy.normal.z)
        #expect(analytic.offset == legacy.offset)
        #expect(try legacy.contains(origin, usage: &usage))
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["work", "storage"])
    func authoredPlaneEquationTerminalCallbackCancellationPropagates(boundary: String) async throws {
        var measured = Budget()
        _ = try equation(usage: &measured)
        let lastWork = measured.workCalls, lastStorage = measured.storageCalls
        #expect(lastWork > 0 && lastStorage > 0)
        let task = Task {
            var usage = Budget(cancelAtWorkCall: boundary == "work" ? lastWork : nil,
                cancelAtStorageCall: boundary == "storage" ? lastStorage : nil)
            // The selected final callback cancels and returns normally. The
            // successful issuer must check cancellation before publishing.
            return try equation(usage: &usage)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlaneEquationCancellationPropagates() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var usage = Budget()
            return try equation(usage: &usage)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
