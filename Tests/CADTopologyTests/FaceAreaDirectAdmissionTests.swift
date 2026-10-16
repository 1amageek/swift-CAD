import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

#if !FACE_AREA_DIRECT_PORTABLE
import Testing

@Suite("Direct face area admission", .timeLimit(.minutes(1)))
struct FaceAreaDirectAdmissionTests {
    @Test func supportedSurfacesRetainTheirIndependentAreaAndCentroid() throws {
        try FaceAreaDirectAdmissionChecks.supportedSurfacesRetainTheirIndependentAreaAndCentroid()
    }
    @Test func workAndStorageUseTheCumulativeCallerBoundary() throws {
        try FaceAreaDirectAdmissionChecks.workAndStorageUseTheCumulativeCallerBoundary()
    }
    @Test func entryAndInProgressCancellationRetainTheCallerCause() throws {
        try FaceAreaDirectAdmissionChecks.entryAndInProgressCancellationRetainTheCallerCause()
    }
    @Test func sourceAxesGuardsAndResultLifetimeRemainIndependent() throws {
        try FaceAreaDirectAdmissionChecks.sourceAxesGuardsAndResultLifetimeRemainIndependent()
    }
}
#endif

enum FaceAreaDirectAdmissionChecks {
    struct Failure: Error { let message: String }
    struct Input {
        var model: BRepModel
        let faceID: FaceID
    }
    static let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-6)

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func execution(_ budget: OriginalQueryBudget, value: Int = 32,
        coefficient: Int = 32, source: Int = 16) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: value,
            maximumCoefficientDepth: coefficient, remainingSourceDepth: source, maximumSubdivisionDepth: 32))
    }

    static func rectangle(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) -> [SurfaceParameterCurve] {
        [.constantV(v: v0, uStart: u0, uEnd: u1),
         .constantU(u: u1, vStart: v0, vEnd: v1),
         .constantV(v: v1, uStart: u1, uEnd: u0),
         .constantU(u: u0, vStart: v1, vEnd: v0)]
    }

    static func fixture(_ surface: Surface3D, _ curves: [SurfaceParameterCurve]) -> Input {
        let surfaceID = SurfaceID(PortableIdentity128(high: 1, low: 1))
        let faceID = FaceID(PortableIdentity128(high: 2, low: 1))
        let loopID = LoopID(PortableIdentity128(high: 3, low: 1))
        let coedges = curves.enumerated().map {
            Coedge(edgeID: EdgeID(PortableIdentity128(high: 4, low: UInt64($0.offset + 1))),
                surfaceParameterCurve: $0.element)
        }
        return Input(model: BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID], orientation: .forward)],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: coedges)]), faceID: faceID)
    }

    static var plane: Surface3D {
        .plane(Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX))
    }

    static func polynomialPlane() -> Input {
        var curves = rectangle(0, 2, 0, 3)
        curves[0] = .bSpline(BSplineCurve2D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 2, y: 0)]))
        return fixture(plane, curves)
    }

    static func measure(_ input: Input, using execution: inout OriginalQueryExecution) throws -> FaceAreaMeasurement {
        try input.model.faceAreaMeasurement(of: input.faceID, tolerance: tolerance, using: &execution)
    }

    static func check(_ result: FaceAreaMeasurement, area: Double, centroid: Point3D) throws {
        try require(abs(result.area - area) <= tolerance.distance * tolerance.distance + tolerance.relative * area,
            "Face area differs from the independent integral: \(result.area), expected \(area).")
        try require((result.centroid - centroid).length <= tolerance.distance,
            "Face centroid differs from the independent integral: \(result.centroid), expected \(centroid).")
    }

    static func nativePlane() -> Surface3D {
        Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)],
                [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]]))
    }

    static func supportedSurfacesRetainTheirIndependentAreaAndCentroid() throws {
        let a = 0.25, b = 0.25
        let native = nativePlane()
        let torusArea = 4 * a * (3 * b + sin(b))
        let torusMoment = 2 * sin(a) * (18 * b + 12 * sin(b) + b + sin(2 * b) / 2)
        let sphereArea = 4 * a * sin(b)
        // Integrals of dA, x*dA, y*dA and z*dA over the authored rectangles.
        // Stored cylinder has U along +X; analytic axis-Z supports have U along +Y.
        let cases: [(Input, Double, Point3D)] = [
            (fixture(plane, rectangle(0, 2, 0, 3)), 6, Point3D(x: 1, y: 1.5, z: 0)),
            (polynomialPlane(), 6, Point3D(x: 1, y: 1.5, z: 0)),
            (fixture(.cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 2)),
                rectangle(-a, a, 0, 3)), 12 * a, Point3D(x: 2 * sin(a) / a, y: 0, z: 1.5)),
            (fixture(.analytic(.cone(apex: .origin, axis: .unitZ, halfAngle: .pi / 6)),
                rectangle(-a, a, 1, 2)), 3 * a * sin(.pi / 6),
                Point3D(x: 0, y: sin(.pi / 6) * (14.0 / 9) * sin(a) / a, z: cos(.pi / 6) * (14.0 / 9))),
            (fixture(.analytic(.torus(center: .origin, axis: .unitZ, majorRadius: 3, minorRadius: 1)),
                rectangle(-a, a, -b, b)), torusArea, Point3D(x: 0, y: torusMoment / torusArea, z: 0)),
            (fixture(.analytic(.sphere(center: .origin, radius: 1)), rectangle(-a, a, -b, b)),
                sphereArea, Point3D(x: 0, y: 2 * sin(a) * (b + sin(2 * b) / 2) / sphereArea, z: 0)),
            (fixture(native, rectangle(0, 1, 0, 1)), 1, Point3D(x: 0.5, y: 0.5, z: 0)),
            (fixture(plane, [.harmonic(center: Point2D(x: 0, y: 0), cosine: Point2D(x: 1, y: 0),
                sine: Point2D(x: 0, y: 1), startParameter: 0, endParameter: 2 * .pi)]), .pi, .origin)
        ]
        for (input, area, centroid) in cases {
            var admission = try execution(OriginalQueryBudget())
            try admission.consumeWork(13)
            try check(measure(input, using: &admission), area: area, centroid: centroid)
            try require(admission.budget.snapshot.work == admission.localWork && admission.localWork > 13,
                "The lower face query escaped the incoming work owner.")
            try check(input.model.faceAreaMeasurement(of: input.faceID, tolerance: tolerance), area: area, centroid: centroid)
        }
    }

    static func original(_ error: any Error) -> any Error {
        if let query = error as? OriginalQueryFailure { return original(query.originalError) }
        if let scalar = error as? ExactScalarFailure, case let .admissionRejected(cause) = scalar {
            return original(cause)
        }
        return error
    }

    static func resource(_ error: any Error, _ axis: ExactResource) throws {
        guard let scalar = original(error) as? ExactScalarFailure,
            case let .resourceLimit(actual) = scalar, actual == axis else { throw error }
    }

    static func workAndStorageUseTheCumulativeCallerBoundary() throws {
        let inputs: [(Input, Double, Point3D)] = [
            (polynomialPlane(), 6, Point3D(x: 1, y: 1.5, z: 0)),
            (fixture(nativePlane(), rectangle(0, 1, 0, 1)), 1, Point3D(x: 0.5, y: 0.5, z: 0))]
        for (input, area, centroid) in inputs {
            func run(_ budget: OriginalQueryBudget) throws -> FaceAreaMeasurement {
                var admission = try execution(budget)
                try admission.consumeWork(13)
                let result = try measure(input, using: &admission)
                try require(admission.localWork == budget.snapshot.work, "Caller work attribution changed.")
                return result
            }
            let observed = try OriginalQueryBudget()
            try check(run(observed), area: area, centroid: centroid)
            let n = observed.snapshot
            let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
            try check(run(exact), area: area, centroid: centroid)
            try require(exact.snapshot.work == n.work && exact.snapshot.storageBytes == n.storageBytes,
                "The same immutable input changed its paid trace.")
            for axis in [ExactResource.work, .storage] {
                let short = try OriginalQueryBudget(workLimit: n.work - (axis == .work ? 1 : 0),
                    storageByteLimit: n.storageBytes - (axis == .storage ? 1 : 0))
                do { _ = try run(short); throw Failure(message: "An N-1 face query published a result.") }
                catch { try resource(error, axis) }
            }
            let noStorage = try OriginalQueryBudget(storageByteLimit: 0)
            do { _ = try run(noStorage); throw Failure(message: "A zero-storage face query published a result.") }
            catch { try resource(error, .storage) }
            try require(noStorage.snapshot.storageBytes == 0, "Refused storage was committed.")
            let byteBudget = try OriginalQueryBudget(allocationPolicy: .bytes)
            try check(run(byteBudget), area: area, centroid: centroid)
            try require(byteBudget.snapshot.work == n.work + byteBudget.snapshot.storageBytes,
                "The face query masked the caller's per-byte work policy.")
            let m = byteBudget.snapshot
            let exactBytes = try OriginalQueryBudget(workLimit: m.work, storageByteLimit: m.storageBytes,
                allocationPolicy: .bytes)
            try check(run(exactBytes), area: area, centroid: centroid)
            try require(exactBytes.snapshot.work == m.work && exactBytes.snapshot.storageBytes == m.storageBytes,
                "The same byte-policy input changed its paid trace.")
            for axis in [ExactResource.work, .storage] {
                let short = try OriginalQueryBudget(workLimit: m.work - (axis == .work ? 1 : 0),
                    storageByteLimit: m.storageBytes - (axis == .storage ? 1 : 0), allocationPolicy: .bytes)
                do { _ = try run(short); throw Failure(message: "An N-1 byte-policy face query published a result.") }
                catch { try resource(error, axis) }
            }
            print("FACE_AREA_BOUNDARY area=\(area) work=\(n.work) bytes=\(n.storageBytes) byteWork=\(m.work)")
        }
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw .cancelled }
        }
    }

    static func entryAndInProgressCancellationRetainTheCallerCause() throws {
        let input = polynomialPlane()
        for stop in [1, 20] {
            let control = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try control.check() })
            var admission = try execution(budget)
            do { _ = try measure(input, using: &admission); throw Failure(message: "A cancelled face query published output.") }
            catch {
                guard let scalar = original(error) as? ExactScalarFailure, case .cancelled = scalar else { throw error }
            }
            try require(control.count == stop, "Cancellation lost its original checkpoint owner.")
            if stop == 1 {
                try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                    "Entry cancellation consumed resources.")
            } else { try require(budget.snapshot.work > 0, "In-progress cancellation reset prior work.") }
        }
    }

    static func sourceAxesGuardsAndResultLifetimeRemainIndependent() throws {
        var input = fixture(plane, rectangle(0, 2, 0, 3))
        let retained = input
        var admission = try execution(OriginalQueryBudget(), value: 0, coefficient: 0, source: 0)
        let result = try measure(input, using: &admission)
        try check(result, area: 6, centroid: Point3D(x: 1, y: 1.5, z: 0))
        try require(admission.effectiveLimits.maximumValueDepth == 0 && admission.effectiveLimits.maximumCoefficientDepth == 0,
            "Face measurement widened independent incoming algebra axes.")
        input.model.faces.removeAll(where: { _ in true })
        input.model.geometry.surfaces.removeAll(where: { _ in true })
        var fresh = try execution(OriginalQueryBudget())
        try check(measure(retained, using: &fresh), area: 6, centroid: result.centroid)
        try check(result, area: 6, centroid: Point3D(x: 1, y: 1.5, z: 0))
        do { _ = try measure(input, using: &fresh); throw Failure(message: "A missing face succeeded.") }
        catch { guard let topology = original(error) as? TopologyError,
            case .missingReference = topology else { throw error } }
        let unsupported = fixture(.cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 2)),
            [.harmonic(center: Point2D(x: 0, y: 0), cosine: Point2D(x: 1, y: 0),
                sine: Point2D(x: 0, y: 1), startParameter: 0, endParameter: 2 * .pi)])
        do { _ = try measure(unsupported, using: &fresh); throw Failure(message: "Unsupported cylindrical harmonic trim succeeded.") }
        catch { guard let failure = original(error) as? KernelError,
            failure.code == .unsupportedCapability else { throw error } }
        let shifted = fixture(plane, rectangle(0, 2, 0, 3).map {
            SurfaceParameterCurve.periodicTranslation(base: $0, uShift: 1, vShift: 0)
        })
        var shallow = try execution(OriginalQueryBudget(), source: 0)
        do { _ = try measure(shifted, using: &shallow); throw Failure(message: "A nested UV source escaped source depth zero.") }
        catch {
            func queryFailure(_ error: any Error) -> OriginalQueryFailure? {
                if let query = error as? OriginalQueryFailure { return query }
                if let scalar = error as? ExactScalarFailure, case let .admissionRejected(cause) = scalar {
                    return queryFailure(cause)
                }
                return nil
            }
            guard let failure = queryFailure(error), failure.kernelFailure.code == .resourceLimitExceeded,
                failure.context.resource?.axis == .sourceDepth,
                failure.context.resource?.limit == .known(0) else { throw error }
        }
    }
}
