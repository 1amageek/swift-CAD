import CADCore
import CADGeometry
import Synchronization

/// Real common-execution admission of the existing four Core authoring laws.
@main
struct CoreBezierAdmissionPortable {
    enum Law: Int { case natural, arc, soft, reflective }
    struct Failure: Error { let line: UInt; let message: String }
    private final class StopAtWork: Sendable {
        private let work = Mutex(0)
        let threshold: Int
        init(_ threshold: Int) { self.threshold = threshold }
        func record(_ units: Int) { work.withLock { $0 += units } }
        func checkpoint() throws(ExactScalarFailure) {
            let stopped = work.withLock { $0 >= threshold }
            if stopped { throw .cancelled }
        }
    }

    static func require(_ condition: Bool, _ message: String, line: UInt = #line) throws {
        guard condition else { throw Failure(line: line, message: message) }
    }
    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0,
                remainingSourceDepth: 0, maximumTransportDepth: 0, maximumSubdivisionDepth: 0))
    }
    static func source() -> [Point2D] {
        [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 3, y: 0)]
    }
    static func ordinary(_ law: Law) throws -> [Point2D] {
        switch law {
        case .natural:
            return try NaturalBezierContinuation(tolerance: .standard)
                .naturalSpan(ofSegment: source(), at: .end, length: 3)
        case .arc:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .arc(spanCount: 1), controlPoints: source(), length: 3)
        case .soft:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .soft(spanCount: 1), controlPoints: source(), length: 3)
        case .reflective:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .reflective(degree: 3, coversCurve: false), controlPoints: source(), length: 1.5)
        }
    }
    static func admitted(_ law: Law, using admission: inout OriginalQueryExecution) throws -> [Point2D] {
        switch law {
        case .natural:
            return try NaturalBezierContinuation(tolerance: .standard)
                .naturalSpan(ofSegment: source(), at: .end, length: 3, using: &admission)
        case .arc:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .arc(spanCount: 1), controlPoints: source(), length: 3, using: &admission)
        case .soft:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .soft(spanCount: 1), controlPoints: source(), length: 3, using: &admission)
        case .reflective:
            return try BezierShapedExtension(tolerance: .standard)
                .newPoints(shape: .reflective(degree: 3, coversCurve: false), controlPoints: source(), length: 1.5, using: &admission)
        }
    }
    static func same(_ first: [Point2D], _ second: [Point2D]) throws {
        try require(first.count == second.count, "Output point count changed.")
        for (a, b) in zip(first, second) {
            try require(a.x.bitPattern == b.x.bitPattern && a.y.bitPattern == b.y.bitPattern,
                "Ordinary and admitted numerical operations diverged.")
        }
    }
    static func cause(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return cause(failure.originalError) }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let original) = failure {
            return cause(original)
        }
        return error
    }
    static func resource(_ expected: ExactResource, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let failure = cause(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = failure, actual == expected else { throw error }
            return
        }
        throw Failure(line: #line, message: "A refused Core numeric query published output.")
    }
    static func cancelled(_ body: () throws -> Void) throws {
        do { try body() }
        catch {
            guard let failure = cause(error) as? ExactScalarFailure, case .cancelled = failure else { throw error }
            return
        }
        throw Failure(line: #line, message: "A cancelled Core numeric query published output.")
    }

    static func lawsAndParity() throws {
        for law in [Law.natural, .arc, .soft, .reflective] {
            let budget = try OriginalQueryBudget()
            var admission = try execution(budget)
            let result = try admitted(law, using: &admission)
            try same(result, ordinary(law))
            try require(result.count == 3, "An existing cubic authoring law changed its degree.")
            for (index, point) in result.enumerated() {
                let expected = law == .reflective ? 3.5 + Double(index) * 0.5 : 4 + Double(index)
                try require(abs(point.x - expected) < 1e-12 && abs(point.y) < 1e-12,
                    "An independently known straight authoring law changed.")
            }
            try require(budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0
                && budget.snapshot.cellVisits == 0, "Core numeric work bypassed admission or invented root visits.")
        }
        let budget = try OriginalQueryBudget()
        var admission = try execution(budget)
        let start = try NaturalBezierContinuation(tolerance: .standard)
            .naturalSpan(of: source(), at: .start, length: 3, using: &admission)
        for (index, point) in start.enumerated() {
            try require(abs(point.x - Double(index - 3)) < 1e-12 && abs(point.y) < 1e-12,
                "Start continuation changed orientation.")
        }
        let adaptive = try CurvatureProfileExtension(tolerance: .standard).cubicSpans(
            from: Point2D(x: 3, y: 0), direction: Point2D(x: 1, y: 0), curvature: 0,
            length: 3, profile: .soft, using: &admission)
        try same(adaptive, ordinary(.soft))
        let count = try BezierShapedExtension(tolerance: .standard)
            .profileSpanCount(segment: source(), length: 3, profile: .arc, using: &admission)
        try require(count == 1, "Straight profile changed its adaptive structure.")
        let reflected = try BezierShapedExtension(tolerance: .standard)
            .reflectiveSegmentCount(segments: source(), degree: 3, length: 1.5, using: &admission)
        try require(reflected.count == 1 && reflected.coversCurve, "Reflective source structure changed.")
        print("PASS Core Bezier original numeric laws")
        print("PASS Core Bezier ordinary and admitted parity")
    }

    static func resourceBoundaries() throws {
        for law in [Law.natural, .arc, .soft, .reflective] {
            let measured = try OriginalQueryBudget()
            var measuring = try execution(measured)
            let reference = try admitted(law, using: &measuring)
            let n = measured.snapshot
            _ = try admitted(law, using: &measuring)
            try require(measured.snapshot.work == 2 * n.work && measured.snapshot.storageBytes == 2 * n.storageBytes,
                "Repeated numeric calls did not retain their cumulative caller cost.")
            let exactBudget = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
            var exact = try execution(exactBudget)
            let exactResult = try admitted(law, using: &exact)
            try same(reference, exactResult)
            try require(exactBudget.snapshot.work == n.work && exactBudget.snapshot.storageBytes == n.storageBytes,
                "The exact admitted boundary changed its measured cost.")
            let workBudget = try OriginalQueryBudget(workLimit: n.work - 1, storageByteLimit: n.storageBytes)
            var shortWork = try execution(workBudget)
            try resource(.work) { _ = try admitted(law, using: &shortWork) }
            try require(workBudget.snapshot.work <= n.work - 1, "A failed work debit was committed.")
            let storageBudget = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes - 1)
            var shortStorage = try execution(storageBudget)
            try resource(.storage) { _ = try admitted(law, using: &shortStorage) }
            try require(storageBudget.snapshot.storageBytes <= n.storageBytes - 1, "A failed storage debit was committed.")
            let noStorageBudget = try OriginalQueryBudget(storageByteLimit: 0)
            var noStorage = try execution(noStorageBudget)
            try resource(.storage) { _ = try admitted(law, using: &noStorage) }
            try require(noStorageBudget.snapshot.storageBytes == 0, "An array was charged after its allocation.")
            print("CORE_BEZIER law=\(law.rawValue) work=\(n.work) bytes=\(n.storageBytes)")
        }
        print("PASS Core Bezier cumulative work and storage")
        print("PASS Core Bezier exact work and storage boundaries")
    }

    static func cancellationWithinIterations() throws {
        for law in [Law.natural, .arc, .soft, .reflective] {
            let baseline = try OriginalQueryBudget()
            var measuring = try execution(baseline)
            _ = try admitted(law, using: &measuring)
            let threshold = baseline.snapshot.work / 2
            try require(threshold > source().count + 10, "The cancellation fixture did not reach numeric iterations.")
            let stop = StopAtWork(threshold)
            let budget = try OriginalQueryBudget(consumeWorkUnits: { stop.record($0) }, checkpoint: { try stop.checkpoint() })
            var admission = try execution(budget)
            try cancelled { _ = try admitted(law, using: &admission) }
            try require(budget.snapshot.work >= threshold && budget.snapshot.work < baseline.snapshot.work
                && budget.snapshot.storageBytes > 0, "Cancellation did not stop inside actual numeric work.")
        }
        let stop = StopAtWork(0)
        let budget = try OriginalQueryBudget(checkpoint: { try stop.checkpoint() })
        var admission = try execution(budget)
        try cancelled { _ = try admitted(.natural, using: &admission) }
        try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
            "Entry cancellation performed paid work.")
        print("PASS Core Bezier cancellation within numeric iteration")
    }

    static func unitsAndErrors() throws {
        var coordinates = source().flatMap { [Quantity(value: $0.x, kind: .length), Quantity(value: $0.y, kind: .length)] }
        let budget = try OriginalQueryBudget()
        var admission = try execution(budget)
        let natural = try NaturalBezierContinuation(tolerance: .standard)
            .coordinate(coordinates, length: Quantity(value: 3, kind: .length), index: 0, using: &admission)
        let soft = try BezierShapedExtension(tolerance: .standard).coordinate(shape: .soft(spanCount: 1),
            coordinates: coordinates, length: Quantity(value: 3, kind: .length), index: 0, using: &admission)
        try require(natural.kind == .length && abs(natural.value - 4) < 1e-12
            && soft.kind == .length && abs(soft.value - 4) < 1e-12, "Coordinate values or units changed.")
        coordinates[1] = Quantity(value: 0, kind: .angle)
        do {
            _ = try NaturalBezierContinuation(tolerance: .standard)
                .coordinate(coordinates, length: Quantity(value: 3, kind: .length), index: 0, using: &admission)
            throw Failure(line: #line, message: "Wrong coordinate units were accepted.")
        } catch let error as UnitError {
            guard case .expectedQuantity(operation: "bezierNaturalExtension", expected: .length, actual: .angle) = error else { throw error }
        }
        do {
            _ = try BezierShapedExtension(tolerance: .standard).newPoints(shape: .arc(spanCount: 1),
                controlPoints: source(), length: -1, using: &admission)
            throw Failure(line: #line, message: "Invalid extension length was accepted.")
        } catch let error as KernelError {
            try require(error.code == .invalidInput, "The existing numeric error changed.")
        }
        print("PASS Core Bezier invalid units and numeric errors")
    }

    static func main() throws {
        try lawsAndParity()
        try resourceBoundaries()
        try cancellationWithinIterations()
        try unitsAndErrors()
        try TwoPointPolylineAdmissionPortable.run()
        print("PASS Core Bezier portable all")
    }
}

enum TwoPointPolylineAdmissionPortable {
    private enum Failure: Error { case mismatch(String), expectedFailure }

    private static func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure.mismatch(name) }
    }

    private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumSpans: 64))
    }

    private static func query(_ reversed: Bool = false, using execution: inout OriginalQueryExecution) throws {
        let a = SurfaceParameter(u: 0.125, v: -0.25), b = SurfaceParameter(u: 1.125, v: 0.75)
        let points = reversed ? [b, a] : [a, b]
        let source = Curve3D.surfaceLift(.init(surface: .plane(.init(origin: .origin, normal: .unitZ)),
            parameterCurve: .polyline(points)))
        let prepared = try PreparedCurveDifferentialEncloser(curve: source, tolerance: .standard,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 0,
            using: &execution)
        let receipt = try prepared.closedNativeJets(over: .init(lower: 0, upper: 1), tolerance: .standard,
            using: &execution)
        try require(receipt.spans.count == 1, "single complete original lift owner")
        let jet = receipt.spans[0].jet, sign = reversed ? -1.0 : 1.0
        // The source-owned +Z plane has U=+Y and V=-X.
        for (coordinate, lower, upper, gain) in [
            (jet.x, -b.v, -a.v, -sign), (jet.y, a.u, b.u, sign), (jet.z, 0, 0, 0)] {
            let value = coordinate.value
            try require(value.lower <= lower && value.upper >= upper, "whole affine value")
            let first = coordinate.derivativeU
            try require(first.lower <= gain && first.upper >= gain, "directed first derivative")
            for higher in [coordinate.secondDerivativeUU, coordinate.thirdDerivativeUUU] {
                try require(higher.lower <= 0 && higher.upper >= 0
                    && higher.lower >= -1e-12 && higher.upper <= 1e-12, "original higher zero enclosure")
            }
        }
    }

    private static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return original(cause)
        }
        return error
    }

    private static func expectResource(_ resource: ExactResource, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
            return
        }
        throw Failure.expectedFailure
    }

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == cancelAt { throw .cancelled }
        }
    }

    private static func correspondence() throws {
        let tolerance = ModelingTolerance.standard
        let validator = DefaultCurveSurfaceCorrespondenceValidator()
        for reversed in [false, true] {
            for offset in [0.0, tolerance.distance * 8] {
                let a = SurfaceParameter(u: -0.010 + offset, v: 0.020)
                let b = SurfaceParameter(u: -0.010 + offset, v: -0.020)
                var admission = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: 262_144),
                    limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                        remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumSpans: 64))
                do {
                    try validator.validate(curve: .line(.init(origin: .init(x: -0.020, y: -0.010, z: 0),
                        direction: .unitX)), from: reversed ? 0.040 : 0, to: reversed ? 0 : 0.040,
                        surface: .plane(.init(origin: .origin, normal: .unitZ)),
                        parameterCurve: .polyline(reversed ? [b, a] : [a, b]),
                        options: .init(maximumSubdivisionDepth: 32, maximumCellCount: 65_536,
                            maximumDeviation: tolerance.distance), tolerance: tolerance,
                        maximumSpanCount: 64, maximumSubdivisionDepth: 32, remainingSourceDepth: 16,
                        maximumAlgebraicDepth: 32, using: &admission)
                    try require(offset == 0, "distant correspondence must be refused")
                } catch {
                    guard offset > 0, let kernel = original(error) as? KernelError,
                        kernel.code == .topologyFailure else { throw error }
                }
            }
        }
        print("PASS two-point-polyline actual-planar-correspondence directed-valid distant-refusal")
    }

    static func run() throws {
        var measuring = try execution(OriginalQueryBudget(workLimit: 262_144))
        try query(using: &measuring)
        let complete = measuring.budget.snapshot
        try require(complete.work > 0 && complete.storageBytes > 0, "caller-paid proof")
        var reversed = try execution(OriginalQueryBudget(workLimit: 262_144))
        try query(true, using: &reversed)
        var exact = try execution(OriginalQueryBudget(workLimit: complete.work,
            storageByteLimit: complete.storageBytes))
        try query(using: &exact)
        try require(exact.budget.snapshot.work == complete.work
            && exact.budget.snapshot.storageBytes == complete.storageBytes, "exact caller boundary")
        var shortWork = try execution(OriginalQueryBudget(workLimit: complete.work - 1))
        try expectResource(.work) { try query(using: &shortWork) }
        for bytes in [0, complete.storageBytes - 1] {
            var shortBytes = try execution(OriginalQueryBudget(storageByteLimit: bytes))
            try expectResource(.storage) { try query(using: &shortBytes) }
        }
        let checkpoints = Checkpoints()
        var counted = try execution(OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() }))
        try query(using: &counted)
        try require(checkpoints.count > 1, "entry and terminal checkpoints")
        for stop in [1, checkpoints.count] {
            let cancellation = Checkpoints(cancelAt: stop)
            var cancelled = try execution(OriginalQueryBudget(checkpoint: { try cancellation.checkpoint() }))
            do { try query(using: &cancelled); throw Failure.expectedFailure }
            catch {
                guard let scalar = original(error) as? ExactScalarFailure,
                    case .cancelled = scalar else { throw error }
            }
            try require(cancelled.budget.snapshot.work == (stop == 1 ? 0 : complete.work),
                "cancellation preserves admitted work")
        }
        try correspondence()
        print("PASS two-point-polyline original-affine reversed D2-D3-zero algebra0 exact-N N-minus-1 bytes0 entry-terminal-cancel work=\(complete.work) bytes=\(complete.storageBytes)")
    }
}
