import CADCore
import Synchronization
import WASILibc
@testable import CADGeometry

/// Behavioral oracles for the actual complete Geometry module on matching WASI lanes.
@main
struct FullGeometryPortable {
    enum OracleFailure: Error { case mismatch, missingRefusal }
    enum SinkFailure: Error { case stopped }
    static let tolerance = ModelingTolerance(distance: 1e-10, angle: 1e-11, relative: 1e-12)

    static func log(_ message: String) {
        Swift.print(message)
        _ = fflush(nil)
    }
    static func require(_ condition: Bool, line: UInt32 = #line) throws {
        guard condition else { log("FAIL portable oracle at line \(line)"); throw OracleFailure.mismatch }
    }
    static func limits() throws -> OriginalQueryExecutionLimits {
        try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            maximumCells: 4096, remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumSpans: 64)
    }
    static func rejects(_ code: KernelErrorCode, line: UInt32 = #line, _ body: () throws -> Void) throws {
        do { try body() }
        catch {
            if let failure = OriginalQueryFailure.classification(of: error) {
                try require(failure.code == code, line: line)
                return
            }
            if let scalar = error as? ExactScalarFailure {
                switch scalar {
                case .admissionRejected(let cause):
                    log("OBSERVED direct admissionRejected at oracle line \(line)")
                    try require(OriginalQueryFailure.classification(of: cause)?.code == code, line: line)
                    return
                case .resourceLimit(.work):
                    log("OBSERVED raw ExactScalarFailure.resourceLimit(work) at oracle line \(line)")
                    try require(code == .resourceLimitExceeded, line: line)
                    return
                case .resourceLimit(.storage):
                    log("OBSERVED raw ExactScalarFailure.resourceLimit(storage) at oracle line \(line)")
                    try require(code == .resourceLimitExceeded, line: line)
                    return
                default: throw scalar
                }
            }
            log("FAIL refusal has no expected concrete classification at oracle line \(line)")
            throw error
        }
        throw OracleFailure.missingRefusal
    }
    static func box(_ lower: Double, _ upper: Double) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: lower, upper: upper),
            v: try ScalarInterval(lower: 0, upper: 1))
    }
    static func plane() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [-2, -1, 0, 1, 2, 3, 4],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1.0].map { y in
                [-0.5, 0.5, 1.5, 2.5].map { Point3D(x: $0, y: y, z: 0) }
            })
    }
    static func c0Surface() -> BSplineSurface3D {
        BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
            vKnots: [0, 0, 1, 1], controlPoints: [0.0, 1.0].map { y in
                zip([0.0, 0.25, 0.5, 0.75, 1.0], [0.0, 0.0, 0.0, 1.0, 2.0]).map {
                    Point3D(x: $0.0, y: y, z: $0.1)
                }
            })
    }
    static func nativePanelsAndOwners() throws {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        let surface = plane()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface,
            tolerance: tolerance, using: &execution)
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: surface, over: box(0, 2), tolerance: tolerance, using: &execution)
        try require(panels.count == 2 && panels[0].span.uSpanIndex == 2 && panels[1].span.uSpanIndex == 3)
        for panel in panels {
            for u in [panel.parameters.u.lower, panel.parameters.u.midpoint, panel.parameters.u.upper] {
                let jet = try panel.span.pointJet(u: u, v: 0.4, on: surface,
                    tolerance: tolerance, using: &execution)
                try require(jet.x.value.lower <= u && jet.x.value.upper >= u)
                try require(jet.y.value.lower <= 0.4 && jet.y.value.upper >= 0.4)
                try require(jet.x.derivativeU.lower <= 1 && jet.x.derivativeU.upper >= 1)
                try require(jet.y.derivativeV.lower <= 1 && jet.y.derivativeV.upper >= 1)
                let normal = try surface.normal(u: u, v: 0.4, owning: panel.span,
                    tolerance: tolerance, using: &execution)
                try require(abs(normal.z - 1) < 1e-12)
            }
        }
        let before = budget.snapshot.work
        _ = try prepared.intervalJet(over: box(0, 2), tolerance: tolerance, using: &execution)
        try require(budget.snapshot.work > before && budget.snapshot.storageBytes > 0)
        var changed = surface
        changed.controlPoints[0][0].z = 1
        try rejects(.invalidInput) {
            _ = try panels[0].span.pointJet(u: 0.4, v: 0.5, on: changed,
                tolerance: tolerance, using: &execution)
        }
        try rejects(.resourceLimitExceeded) {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: surface, over: box(0, 2), tolerance: tolerance, maximumCellCount: 1, using: &execution)
        }
        let c0 = c0Surface()
        let c0Prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: c0,
            tolerance: tolerance, using: &execution)
        let spans = try c0Prepared.originalNativeSpans(over: box(0, 1), tolerance: tolerance, using: &execution)
        try require(spans.count == 2)
        let left = try c0.normal(u: 0.5, v: 0.5, owning: spans[0], tolerance: tolerance, using: &execution)
        let right = try c0.normal(u: 0.5, v: 0.5, owning: spans[1], tolerance: tolerance, using: &execution)
        try require(abs(left.z - 1) < 1e-12 && abs(right.x + 4 / Double(17).squareRoot()) < 1e-12)
        try require(left.dot(right) < 0.3)
        log("PASS native panels: nonclamped polynomial law, C0 owners, exact source and cell refusals")
    }
    static func retainedCurveReader() throws {
        let source = Curve3D.bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.5, y: 1, z: 0), Point3D(x: 1, y: 0, z: 0)]))
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        let retained = try ValidatedCurve3D(source, tolerance: tolerance, using: &execution)
        let before = budget.snapshot.work
        let ordinary = try retained.tessellationIntervalEvaluation(ScalarInterval(lower: 0, upper: 1))
        try require(ordinary.midpointPoint == Point3D(x: 0.5, y: 0.5, z: 0))
        try require(budget.snapshot.work > before)
        let direct = try retained.tessellationIntervalEvaluation(ScalarInterval(lower: 0, upper: 1), using: &execution)
        try require(direct.midpointPoint == ordinary.midpointPoint && direct.bounds.chordDeviationUpperBound == ordinary.bounds.chordDeviationUpperBound)
        let noWork = try OriginalQueryBudget(workLimit: 0)
        var refused = OriginalQueryExecution(budget: noWork, limits: try limits())
        try rejects(.resourceLimitExceeded) {
            _ = try retained.tessellationIntervalEvaluation(ScalarInterval(lower: 0, upper: 1), using: &refused)
        }
        try require(noWork.snapshot.work == 0)
        let noStorage = try OriginalQueryBudget(storageByteLimit: 0)
        var storageRefused = OriginalQueryExecution(budget: noStorage, limits: try limits())
        try rejects(.resourceLimitExceeded) {
            _ = try retained.tessellationIntervalEvaluation(ScalarInterval(lower: 0, upper: 1), using: &storageRefused)
        }
        try require(noStorage.snapshot.storageBytes == 0)
        log("PASS retained curve reader: actual polynomial midpoint, cumulative ordinary/direct reads, foreign budget refusals")
    }
    static func publicNativePlane() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: -2, y: 0, z: -1), Point3D(x: 2, y: 0, z: 1)]))
        let target = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX))
        let options = CurveSurfaceIntersectionOptions(curveRange: try .init(lower: 0, upper: 1))
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        let resolver: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector()
        for _ in 0..<2 {
            let before = budget.snapshot.work
            let result = try resolver.intersectionResult(curve: curve, surface: target,
                options: options, tolerance: tolerance, using: &execution)
            let events = result.points
            try require(events.count == 1 && result.overlaps.isEmpty)
            try require((events[0].point - Point3D.origin).length <= tolerance.distance && abs(events[0].curveParameter - 0.5) <= tolerance.relative)
            try require(budget.snapshot.work > before && budget.snapshot.storageBytes > 0)
        }
        log("PASS public Native-plane: actual source root and protocol direct witness share caller execution")
    }
    final class ProvenanceProbe: SurfaceSilhouetteProvenanceWriting {
        struct State: Sendable { var events = 0; var surfaces = 0; var completed = false }
        let state = Mutex(State())
        func write(_ event: SurfaceSilhouetteProvenanceEvent, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            var surfaceCount = 0, completed = false
            switch event {
            case .surface(let source):
                guard case .bSpline(let native) = source else {
                    switch source {
                    case .plane: FullGeometryPortable.log("FAIL writer surface event: plane instead of original Native bSpline")
                    case .analytic: FullGeometryPortable.log("FAIL writer surface event: analytic instead of original Native bSpline")
                    case .procedural: FullGeometryPortable.log("FAIL writer surface event: procedural instead of original Native bSpline")
                    default: FullGeometryPortable.log("FAIL writer surface event: other case instead of original Native bSpline")
                    }
                    throw OracleFailure.mismatch
                }
                let reader: any OriginalBSplineSourceReading = native
                try FullGeometryPortable.require(reader.parameterCount == 2 && reader.degree(in: 0) == 2)
                try FullGeometryPortable.require(reader.controlCount(in: 0) == 4 && reader.controlCount(in: 1) == 2)
                try FullGeometryPortable.require(reader.coordinate(ofControl: 0, in: 0) == -0.5 && reader.weight(ofControl: 0) == 1)
                surfaceCount = 1
            case .endRecord: completed = true
            default: break
            }
            state.withLock { state in state.events += 1; state.surfaces += surfaceCount; state.completed = completed }
        }
    }
    struct RefusingProvenance: SurfaceSilhouetteProvenanceWriting {
        func write(_ event: SurfaceSilhouetteProvenanceEvent, using execution: inout OriginalQueryExecution) throws {
            throw SinkFailure.stopped
        }
    }
    static func sourceWriterAndReaderWitnesses() throws {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        let producer: any SurfaceSilhouetteProducing = DefaultSurfaceSilhouetteProducer()
        let envelope = try producer.silhouette(of: .bSpline(plane()), over: box(0, 2),
            view: .unitX, tolerance: tolerance, using: &execution)
        let cover = envelope.coincidentDomains.sorted { $0.u.lower < $1.u.lower }
        try require(cover.count == 2 && envelope.curves.isEmpty && envelope.excludedDomains.isEmpty)
        try require(cover[0].u.lower == 0 && cover[0].u.upper == 1 && cover[1].u.lower == 1 && cover[1].u.upper == 2)
        try require(cover.allSatisfy { $0.v.lower == 0 && $0.v.upper == 1 })
        let probe = ProvenanceProbe()
        let writer: any SurfaceSilhouetteProvenanceWriting = probe
        let before = budget.snapshot.work
        try envelope.writeOriginalProvenance(to: writer, using: &execution)
        let state = probe.state.withLock { $0 }
        try require(state.events > 10 && state.surfaces == 1 && state.completed)
        try require(budget.snapshot.work > before)
        do { try envelope.writeOriginalProvenance(to: RefusingProvenance(), using: &execution) }
        catch SinkFailure.stopped {
            log("PASS source writer/reader: actual original envelope, cross-module nongeneric existential witnesses, original sink failure")
            return
        }
        throw OracleFailure.missingRefusal
    }
    static func cancellation() throws {
        let budget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        do {
            _ = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: plane(), over: box(0, 2), tolerance: tolerance, using: &execution)
        } catch let failure as ExactScalarFailure {
            if case .cancelled = failure {
                try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0)
                log("PASS cancellation: actual Native proof refuses before admission")
                return
            }
            throw failure
        }
        throw OracleFailure.missingRefusal
    }
    static func main() throws {
        try nativePanelsAndOwners()
        try retainedCurveReader()
        try publicNativePlane()
        try sourceWriterAndReaderWitnesses()
        try cancellation()
        log("PASS full Geometry portable: 5 oracle groups")
    }
}
