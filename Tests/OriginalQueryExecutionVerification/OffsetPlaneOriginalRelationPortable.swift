import CADCore
import CADGeometry
import Synchronization

/// Uses public offset images and the real bounded correspondence witness.
@main
struct OffsetPlaneOriginalRelationPortable {
    private struct Failure: Error { let line: UInt; let message: String }
    private struct Input {
        let plane: Plane3D
        let distance: Double
        let expectedPlane: Plane3D?
    }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let visit = state.withLock { $0 += 1; return $0 }
            if visit == stop { throw .cancelled }
        }
    }
    private static func require(_ condition: Bool, _ message: String, line: UInt = #line) throws {
        if !condition { throw Failure(line: line, message: message) }
    }
    private static func execution(_ budget: OriginalQueryBudget, sourceDepth: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0,
            remainingSourceDepth: sourceDepth, maximumTransportDepth: 0,
            maximumSubdivisionDepth: 0, maximumSpans: 1))
    }
    private static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let cause) = failure {
            return original(cause)
        }
        return error
    }
    private static func resource(_ axis: ExactResource, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let failure = original(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = failure, actual == axis else { throw error }
            return
        }
        throw Failure(line: #line, message: "A resource-limited original offset query published success.")
    }
    private static func cancellation(_ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let failure = original(error) as? ExactScalarFailure, case .cancelled = failure else { throw error }
            return
        }
        throw Failure(line: #line, message: "A cancelled original offset query published success.")
    }
    private static func image(_ input: Input, using query: inout OriginalQueryExecution) throws
        -> OffsetSurfaceParameterCurveImage {
        try OffsetSurface3D(source: .plane(input.plane), distance: input.distance)
            .parameterCurveImage(transporting: .constantV(v: 0, uStart: -0.020, uEnd: 0.020),
                tolerance: .standard, using: &query)
    }
    private static func validate(_ image: OffsetSurfaceParameterCurveImage, on surface: Surface3D,
        using query: inout OriginalQueryExecution) throws {
        let chart = SurfaceParameterCurve.offsetSurfaceImage(image)
        let witness: any CurveSurfaceCorrespondenceValidating = DefaultCurveSurfaceCorrespondenceValidator()
        try witness.validate(curve: .surfaceLift(.init(surface: surface, parameterCurve: chart)),
            from: 0, to: 1, surface: surface, parameterCurve: chart,
            options: .init(maximumSubdivisionDepth: 1, maximumCellCount: 1,
                maximumDeviation: ModelingTolerance.standard.distance),
            tolerance: .standard, using: &query)
    }
    private static func query(_ input: Input, using admission: inout OriginalQueryExecution) throws {
        let value = try image(input, using: &admission)
        let target = try value.targetSurface(tolerance: .standard, using: &admission)
        if let expected = input.expectedPlane {
            try require(target == .plane(expected), "The exactly materialized plane changed its original chart.")
        } else {
            try require(target == .procedural(.offset(value.offset)), "An unequal rounded plane replaced the original offset.")
        }
        try validate(value, on: target, using: &admission)
        try require(admission.valueDepth == 0 && admission.coefficientDepth == 0,
            "Rational plane identity consumed an algebraic coefficient capability.")
    }
    private static func inputs() -> [Input] {
        let z = Plane3D(origin: .origin, normal: .unitZ)
        let oblique = Plane3D(origin: .init(x: 1, y: -2, z: 4), normal: .init(x: 3, y: 4, z: 0))
        let framed = Plane3D(origin: .origin, normal: -Vector3D.unitZ, uDirection: .init(x: 0.6, y: 0.8, z: 0))
        return [
            .init(plane: z, distance: 0.005, expectedPlane: .init(origin: .init(x: 0, y: 0, z: 0.005), normal: .unitZ)),
            .init(plane: oblique, distance: 5, expectedPlane: .init(origin: .init(x: 4, y: 2, z: 4), normal: oblique.normal)),
            .init(plane: oblique, distance: -5, expectedPlane: .init(origin: .init(x: -2, y: -6, z: 4), normal: oblique.normal)),
            .init(plane: framed, distance: 0.125,
                expectedPlane: .init(origin: .init(x: 0, y: 0, z: -0.125), normal: framed.normal, uDirection: framed.uDirection)),
            .init(plane: framed, distance: 0, expectedPlane: framed),
            .init(plane: .init(origin: .init(x: 0, y: 0, z: 9_007_199_254_740_992), normal: .unitZ), distance: 1, expectedPlane: nil),
            .init(plane: .init(origin: .origin, normal: .init(x: 1, y: 1, z: 0)), distance: 1, expectedPlane: nil),
            .init(plane: .init(origin: .origin, normal: .unitZ,
                uDirection: .init(x: 1, y: 0, z: ModelingTolerance.standard.angle / 2)), distance: 0.125, expectedPlane: nil),
            .init(plane: .init(origin: .origin, normal: .init(x: 0, y: 0, z: 1e-200)), distance: 1, expectedPlane: nil)
        ]
    }
    private static func wholePlaneAndRetainedSource() throws {
        for input in inputs() {
            var admission = try execution(OriginalQueryBudget(workLimit: 262_144))
            try query(input, using: &admission)
        }
        print("PASS offset-plane: signed/nonunit/oblique/authored-U/zero and retained rounded source")
    }
    private static func wrongSourceAndDepth() throws {
        let input = inputs()[0]
        var setup = try execution(OriginalQueryBudget())
        let value = try image(input, using: &setup)
        let wrong = [
            Plane3D(origin: .init(x: 0, y: 0, z: -0.005), normal: .unitZ),
            Plane3D(origin: .init(x: 1e-12, y: 0, z: 0.005), normal: .unitZ),
            Plane3D(origin: .init(x: 0, y: 0, z: 0.005), normal: -Vector3D.unitZ),
            Plane3D(origin: .init(x: 0, y: 0, z: 0.005), normal: .unitZ, uDirection: .unitX)
        ]
        for target in wrong {
            var admission = try execution(OriginalQueryBudget(workLimit: 262_144))
            do { try validate(value, on: .plane(target), using: &admission) }
            catch {
                guard let failure = original(error) as? KernelError, failure.code == .unsupportedCapability else { throw error }
                continue
            }
            throw Failure(line: #line, message: "A foreign plane chart acquired the original offset relation.")
        }
        var shallow = try execution(OriginalQueryBudget(workLimit: 262_144), sourceDepth: 0)
        do { try query(input, using: &shallow) }
        catch {
            if original(error) is GeometryConversionError {
                print("PASS offset-plane: foreign source/side/basis and source-depth refusal")
                return
            }
            throw error
        }
        throw Failure(line: #line, message: "A zero-source-depth caller admitted a lifted offset descendant.")
    }
    private static func limitsAndCancellation() throws {
        let input = inputs()[0]
        let checkpoints = Checkpoints()
        var measuring = try execution(OriginalQueryBudget(checkpoint: { try checkpoints.check() }))
        try query(input, using: &measuring)
        let complete = measuring.budget.snapshot
        try require(complete.work > 0 && complete.storageBytes > 0, "The original relation bypassed caller work or storage.")
        var exact = try execution(OriginalQueryBudget(workLimit: complete.work, storageByteLimit: complete.storageBytes))
        try query(input, using: &exact)
        try require(exact.budget.snapshot.work == complete.work && exact.budget.snapshot.storageBytes == complete.storageBytes,
            "Exact resource-boundary execution changed its complete work or storage.")
        var workShort = try execution(OriginalQueryBudget(workLimit: complete.work - 1))
        try resource(.work) { try query(input, using: &workShort) }
        var bytesShort = try execution(OriginalQueryBudget(storageByteLimit: complete.storageBytes - 1))
        try resource(.storage) { try query(input, using: &bytesShort) }
        for stop in [1, checkpoints.count] {
            let cancelled = Checkpoints(stop: stop)
            var admission = try execution(OriginalQueryBudget(checkpoint: { try cancelled.check() }))
            try cancellation { try query(input, using: &admission) }
            try require(admission.budget.snapshot.work == (stop == 1 ? 0 : complete.work)
                && admission.budget.snapshot.storageBytes == (stop == 1 ? 0 : complete.storageBytes),
                "Cancellation reset or bypassed the cumulative caller accounting.")
        }
        print("PASS offset-plane: exact work/bytes N and N-1, entry/terminal cancellation")
    }
    static func main() throws {
        try wholePlaneAndRetainedSource()
        try wrongSourceAndDepth()
        try limitsAndCancellation()
    }
}
