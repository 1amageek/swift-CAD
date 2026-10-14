import CADCore
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import WASILibc
#endif
@main struct BoundedSphereConeCallbackBareFinding {
    struct Failure: Error { let line: Int }
    static func require(_ value: Bool, line: Int = #line) throws { guard value else { throw Failure(line: line) } }
    static func input(_ positive: Bool) throws -> (Curve3D, Surface3D) {
        let angle = Double(bitPattern: 0x3fddac670561bb50)
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 2, y: 0, z: -4), axis: .unitZ, halfAngle: angle))
        // Producer-selected numeric hints identify the exact critical arc.
        let source = try CertifiedSphereConeIntersectionCurve(sphereSurface: sphere, coneSurface: cone,
            componentKind: .boundedAngularInterval, lowerAngle: Double(bitPattern: 4602529519994401816),
            upperAngle: Double(bitPattern: 4613149419042483861), tolerance: .standard)
        return (.certifiedIntersection(.sphereCone(source)), .plane(.init(origin: .origin, normal: .unitY, uDirection: .unitX)))
    }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let workLimit: Int; let byteLimit: Int; let cancelAt: Int?; let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = 268_435_456, cancelAt: Int? = nil, cancelStorageAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt; self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let count = try state.withLock { s in
                guard s.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work += 1; return s.work
            }
            if count == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let count = try state.withLock { s in
                let next = s.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= byteLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                s.bytes = next.partialValue; return s.bytes
            }
            if count == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func admitted(_ curve: Curve3D, _ plane: Surface3D, request: ScalarInterval?, counter: Counter,
        sourceDepth: Int = 1, scalarDepth: Int = 32) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: plane,
            options: .init(curveRange: request), tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: scalarDepth)
    }
    static func main() throws {
        let (curve, plane) = try input(false)
        let request = try ScalarInterval(lower: 0, upper: 1)
        let measured = Counter(); _ = try admitted(curve, plane, request: request, counter: measured)
        let counts = measured.totals
        let bareCounter = Counter(work: counts.work, bytes: counts.bytes)
        let bare = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: plane,
            options: .init(curveRange: request), tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: 1,
            consumeWork: { try bareCounter.consume($0) }, consumeStorage: { try bareCounter.retain($0) },
            maximumAlgebraicDepth: 32)
        try require(bare.count == 2)
        for (index, point) in bare.enumerated() {
            try require(point.curveParameter == (index == 0 ? 0.25 : 0.75))
            try require(point.point.y == 0 && point.surfaceU == point.point.x && point.surfaceV == -point.point.z)
            try require(abs(point.point.x * point.point.x + point.point.z * point.point.z - 4) < 1e-10)
            try require(index == 0 ? point.point.x < 0 : point.point.x > 0)
        }
        try require(bareCounter.totals.work == counts.work && bareCounter.totals.bytes == counts.bytes)
        print("PASS callback bare complete two contacts, exact quarter T, target UV and same admission")

    }
}
