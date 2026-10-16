import CADCore
import Synchronization
@testable import CADGeometry

/// Uses the validated original period theorem without changing the requested UV source expression.
enum PeriodicRepairCorrespondenceChecks {
    struct Failure: Error { let message: String }
    static let tolerance = ModelingTolerance.standard
    static let period = Double.pi * 2
    static func require(_ value: Bool,_ message: String) throws {
        guard value else { throw Failure(message: message) }
    }
    static func execution(_ budget: OriginalQueryBudget,source: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget,limits: try .init(maximumValueDepth: 32,maximumCoefficientDepth: 32,
            remainingSourceDepth: source,maximumSubdivisionDepth: 32))
    }
    static func host() -> Surface3D { .cylinder(.init(origin: .origin,axis: .unitZ,radius: 1)) }
    static func base() -> SurfaceParameterCurve { .constantU(u: 0.25,vStart: 0,vEnd: 1) }
    static func curve() -> Curve3D { .surfaceLift(.init(surface: host(),parameterCurve: base())) }
    static func bound(curve: Curve3D,host: Surface3D,chart: SurfaceParameterCurve,depth: Int = 32,
        using admission: inout OriginalQueryExecution) throws -> Double {
        try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(curve: curve,from: 0,to: 1,
            surface: host,parameterCurve: chart,
            options: .init(maximumSubdivisionDepth: depth,maximumCellCount: 1_048_576,
                maximumDeviation: tolerance.distance * 8),tolerance: tolerance,
            maximumSpanCount: 1_048_576,maximumSubdivisionDepth: depth,remainingSourceDepth: 16,
            maximumAlgebraicDepth: 32,using: &admission)
    }
    static func translatedOriginalHasWholeExactZero() throws {
        let originalChart = base(),source = curve(),support = host()
        let charts: [SurfaceParameterCurve] = [originalChart,
            .periodicTranslation(base: originalChart,uShift: period,vShift: 0),
            .periodicTranslation(base: originalChart,uShift: -period,vShift: 0),
            .periodicTranslation(base: .periodicTranslation(base: originalChart,uShift: period,vShift: 0),
                uShift: period,vShift: 0)]
        for chart in charts {
            let retained = chart
            let budget = try OriginalQueryBudget(workLimit: 262_144)
            var admission = try execution(budget)
            let zero = try bound(curve: source,host: support,chart: chart,using: &admission)
            try require(zero == 0 && budget.snapshot.cellVisits == 0,
                "A source-identical validated period shift lost its complete structural zero proof.")
            try require(chart == retained && source == curve() && support == host(),
                "Period reuse replaced the original source or requested UV wrapper.")
        }
        // Preserve the pre-existing exact raw-wrapper identity path as well.
        let translated = charts[1]
        var admission = try execution(OriginalQueryBudget(workLimit: 262_144))
        let zero = try bound(curve: .surfaceLift(.init(surface: support,parameterCurve: translated)),
            host: support,chart: translated,using: &admission)
        try require(zero == 0,"An identical retained translated chart lost its existing zero proof.")
    }
    static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure { return original(retained) }
        return error
    }
    static func retained(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if case .admissionRejected(let cause)? = error as? ExactScalarFailure { return retained(cause) }
        return nil
    }
    static func refusal(_ matches: (any Error) -> Bool,_ operation: () throws -> Void) throws {
        do { try operation() }
        catch { guard matches(error) else { throw error }; return }
        throw Failure(message: "An unproved or cancelled periodic correspondence published a bound.")
    }
    static func invalidShiftForeignBaseAndSourceRefuse() throws {
        var invalid = try execution(OriginalQueryBudget(workLimit: 262_144))
        try refusal({ if case .invalidInput? = original($0) as? GeometryConversionError { true } else { false } }) {
            _ = try bound(curve: curve(),host: host(),
                chart: .periodicTranslation(base: base(),uShift: period / 2,vShift: 0),using: &invalid)
        }
        var foreign = try execution(OriginalQueryBudget(workLimit: 262_144))
        let foreignChart = SurfaceParameterCurve.periodicTranslation(
            base: .constantU(u: 0.5,vStart: 0,vEnd: 1),uShift: period,vShift: 0)
        // A one-level negative control must reach the existing unresolved residual proof, never exact zero.
        try refusal({ if case .resourceLimitExceeded? = original($0) as? GeometryConversionError { true } else { false } }) {
            _ = try bound(curve: curve(),host: host(),chart: foreignChart,depth: 1,using: &foreign)
        }
        try require(foreign.budget.snapshot.cellVisits > 0,"A foreign base bypassed the existing residual consumer.")
        var shallow = try execution(OriginalQueryBudget(workLimit: 262_144),source: 0)
        try refusal({ retained($0)?.context.resource?.axis == .sourceDepth }) {
            _ = try bound(curve: curve(),host: host(),
                chart: .periodicTranslation(base: base(),uShift: period,vShift: 0),using: &shallow)
        }
    }
    final class Checkpoints: Sendable {
        private let state = Mutex(0)
        let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let count = state.withLock { $0 += 1; return $0 }
            if count == stop { throw .cancelled }
        }
    }
    static func cancellationAndRetainedSourceLifetime() throws {
        let chart = SurfaceParameterCurve.periodicTranslation(base: base(),uShift: period,vShift: 0)
        let checks = Checkpoints()
        let measured = try OriginalQueryBudget(workLimit: 262_144,checkpoint: { try checks.checkpoint() })
        var admission = try execution(measured)
        let result = try bound(curve: curve(),host: host(),chart: chart,using: &admission)
        try require(result == 0 && checks.count > 1,"The measured query did not reach its final zero publication.")
        let cost = measured.snapshot
        for stop in [1,checks.count] {
            let checks = Checkpoints(stop: stop)
            let abort = try OriginalQueryBudget(workLimit: 262_144,checkpoint: { try checks.checkpoint() })
            var admission = try execution(abort)
            try refusal({ if case .cancelled? = original($0) as? ExactScalarFailure { true } else { false } }) {
                _ = try bound(curve: curve(),host: host(),chart: chart,using: &admission)
            }
            try require(abort.snapshot.work == (stop == 1 ? 0 : cost.work)
                && abort.snapshot.storageBytes == (stop == 1 ? 0 : cost.storageBytes),
                "Cancellation changed the exact paid publication boundary.")
        }
        let retained = try retainedInput()
        var reader = try execution(OriginalQueryBudget(workLimit: 262_144))
        let zero = try bound(curve: retained.curve,host: retained.host,chart: retained.chart,using: &reader)
        try require(zero == 0 && retained.chart == chart,
            "Releasing or changing the caller's source invalidated retained original values.")
    }
    private static func retainedInput() throws -> (curve: Curve3D,host: Surface3D,chart: SurfaceParameterCurve) {
        var support = host(),local = base()
        let curve = Curve3D.surfaceLift(.init(surface: support,parameterCurve: local))
        let result = (curve: curve,host: support,
            chart: SurfaceParameterCurve.periodicTranslation(base: local,uShift: period,vShift: 0))
        support = .plane(.init(origin: .origin,normal: .unitZ))
        local = .constantU(u: 9,vStart: 0,vEnd: 1)
        try require(support != result.host && local != base(),"The caller source mutation control did not change its inputs.")
        return result
    }
    static func run() throws {
        try translatedOriginalHasWholeExactZero()
        try invalidShiftForeignBaseAndSourceRefuse()
        try cancellationAndRetainedSourceLifetime()
    }
}
