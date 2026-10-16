import CADCore
import Synchronization
@testable import CADGeometry

/// Shared source-owned continuity checks; this receipt does not certify coincidence or smooth joins.
enum BRepRepairAffineLiftChecks {
    struct Failure: Error { let message: String }
    static let tolerance = ModelingTolerance.standard
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    static func execution(_ budget: OriginalQueryBudget, source: Int = 16) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: source, maximumSubdivisionDepth: 32))
    }
    static func plane(z: Double = 0) -> Surface3D {
        .plane(.init(origin: .init(x: 0,y: 0,z: z),normal: .unitZ,uDirection: .unitX))
    }
    static func chart(alongU: Bool, reversed: Bool) -> SurfaceParameterCurve {
        let start = reversed ? 1.0 : 0.0, end = reversed ? 0.0 : 1.0
        return alongU ? .constantV(v: 0.25,uStart: start,uEnd: end)
            : .constantU(u: 0.25,vStart: start,vEnd: end)
    }
    static func prepared(_ source: Curve3D, using admission: inout OriginalQueryExecution) throws
        -> PreparedCurveDifferentialEncloser {
        try .init(curve: source,tolerance: tolerance,remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32,maximumAlgebraicDepth: 32,using: &admission)
    }
    static func issue(_ owner: PreparedCurveDifferentialEncloser, over range: ScalarInterval,
        using admission: inout OriginalQueryExecution) throws -> PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource {
        guard let receipt = try owner.admittingContinuousFirstOrder(over: range,tolerance: tolerance,
            maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &admission) else {
            throw Failure(message: "The validated original affine plane lift lost its continuity capability.")
        }
        try require(receipt.prepared.curve == owner.curve && receipt.parameters == range,
            "The continuity receipt changed its original source or requested domain.")
        return receipt
    }
    static func axesDirectionsSubdomainsAndWholeBound() throws {
        for alongU in [false,true] {
            for reversed in [false,true] {
                let local = chart(alongU: alongU,reversed: reversed)
                let lifted = Curve3D.surfaceLift(.init(surface: plane(),parameterCurve: local))
                let budget = try OriginalQueryBudget(workLimit: 262_144)
                var admission = try execution(budget)
                let owner = try prepared(lifted,using: &admission)
                for range in [try ScalarInterval(lower: 0,upper: 1),
                    try ScalarInterval(lower: 0.2,upper: 0.8),try ScalarInterval(lower: 0.5,upper: 0.5)] {
                    let receipt = try issue(owner,over: range,using: &admission)
                    let jets = try receipt.prepared.closedNativeJets(over: range,tolerance: tolerance,
                        maximumSpanCount: 64,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &admission)
                    try require(!jets.spans.isEmpty,"The retained original lift lost its closed owning cover.")
                    for t in [range.lower,range.midpoint,range.upper] {
                        let varying = reversed ? 1-t : t
                        let p = Point3D(x: alongU ? varying : 0.25,y: alongU ? 0.25 : varying,z: 0)
                        let sign = reversed ? -1.0 : 1.0
                        let d = Vector3D(x: alongU ? sign : 0,y: alongU ? 0 : sign,z: 0)
                        for span in jets.spans where span.parameters.contains(t) {
                            for (jet,value,slope) in [(span.jet.x,p.x,d.x),(span.jet.y,p.y,d.y),(span.jet.z,p.z,d.z)] {
                                try require(jet.value.lower <= value && value <= jet.value.upper
                                    && jet.derivativeU.lower <= slope && slope <= jet.derivativeU.upper,
                                    "The unchanged original jet lost its independent affine position or derivative.")
                            }
                        }
                    }
                }
                // Fresh cold admission: the real correspondence consumer must still prove its whole residual.
                let boundBudget = try OriginalQueryBudget(workLimit: 262_144)
                var boundAdmission = try execution(boundBudget)
                let start = Point3D(x: alongU ? (reversed ? 1 : 0) : 0.25,
                    y: alongU ? 0.25 : (reversed ? 1 : 0),z: 0)
                let sign = reversed ? -1.0 : 1.0
                let source = Curve3D.line(.init(origin: start,
                    direction: .init(x: alongU ? sign : 0,y: alongU ? 0 : sign,z: 0)))
                let bound = try OriginalBoundedCurveSurfaceCorrespondence.deviationBound(curve: source,
                    from: 0,to: 1,surface: plane(),parameterCurve: local,
                    options: .init(maximumSubdivisionDepth: 32,maximumCellCount: 1_048_576,
                        maximumDeviation: tolerance.distance * 8),tolerance: tolerance,
                    maximumSpanCount: 1_048_576,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,
                    maximumAlgebraicDepth: 32,using: &boundAdmission)
                try require(bound.isFinite && bound <= tolerance.distance * 8 && boundBudget.snapshot.cellVisits == 1,
                    "The real affine correspondence did not complete its one-cell residual proof.")
            }
        }
    }
    static func original(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return original(retained.originalError) }
        if case .admissionRejected(let retained)? = error as? ExactScalarFailure { return original(retained) }
        return error
    }
    static func retained(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if case .admissionRejected(let cause)? = error as? ExactScalarFailure { return retained(cause) }
        return nil
    }
    static func refusal(_ matches: (any Error) -> Bool, _ body: () throws -> Void) throws {
        do { try body() }
        catch { guard matches(error) else { throw error }; return }
        throw Failure(message: "An invalid or cancelled continuity request published a receipt.")
    }
    static func scopeAndUnsupportedGuards() throws {
        var admission = try execution(OriginalQueryBudget(workLimit: 262_144))
        let owner = try prepared(.surfaceLift(.init(surface: plane(),parameterCurve: chart(alongU: true,reversed: false))),
            using: &admission)
        let full = try ScalarInterval(lower: 0,upper: 1)
        for range in [try ScalarInterval(lower: -0.1,upper: 0.5),try ScalarInterval(lower: 0.5,upper: 1.1)] {
            try refusal({ if case .invalidInput? = original($0) as? GeometryConversionError { true } else { false } }) {
                _ = try owner.admittingContinuousFirstOrder(over: range,tolerance: tolerance,
                    maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &admission)
            }
        }
        let changed = ModelingTolerance(distance: tolerance.distance * 2,angle: tolerance.angle,relative: tolerance.relative)
        try refusal({ if case .invalidInput? = original($0) as? GeometryConversionError { true } else { false } }) {
            _ = try owner.admittingContinuousFirstOrder(over: full,tolerance: changed,
                maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &admission)
        }
        try refusal({ if case .resourceLimitExceeded? = original($0) as? GeometryConversionError { true } else { false } }) {
            _ = try owner.admittingContinuousFirstOrder(over: full,tolerance: tolerance,
                maximumSubdivisionDepth: 32,remainingSourceDepth: 0,using: &admission)
        }
        let shallowBudget = try OriginalQueryBudget()
        var shallow = try execution(shallowBudget,source: 0)
        try refusal({ retained($0)?.context.resource?.axis == .sourceDepth }) {
            _ = try issue(owner,over: full,using: &shallow)
        }
        try require(shallowBudget.snapshot.work == 0 && shallowBudget.snapshot.storageBytes == 0,
            "Caller source-depth refusal occurred after paid receipt attachment.")
        for (surface,local) in [(Surface3D.analytic(.plane(origin: .origin,normal: .unitZ)),chart(alongU: true,reversed: false)),
            (plane(),SurfaceParameterCurve.polyline([.init(u: 0,v: 0),.init(u: 1,v: 0),.init(u: 1,v: 1)]))] {
            let unsupported = try prepared(.surfaceLift(.init(surface: surface,parameterCurve: local)),using: &admission)
            let result = try unsupported.admittingContinuousFirstOrder(over: full,tolerance: tolerance,
                maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &admission)
            try require(result == nil,"The new affine capability admitted an unrelated support or piecewise corner.")
        }
        try refusal({ if case .invalidDistance(let value)? = original($0) as? GeometryError { value == 0 } else { false } }) {
            _ = try prepared(.surfaceLift(.init(surface: plane(),parameterCurve: .constantV(v: 0,uStart: 1,uEnd: 1))),
                using: &admission)
        }
    }
    static func coldIssue(_ budget: OriginalQueryBudget) throws -> PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource {
        var admission = try execution(budget)
        try admission.consumeWork(7); try admission.retainStorage(bytes: 11)
        let owner = try prepared(.surfaceLift(.init(surface: plane(),parameterCurve: chart(alongU: false,reversed: true))),
            using: &admission)
        return try issue(owner,over: .init(lower: 0.2,upper: 0.8),using: &admission)
    }
    static func callerRefusalAndCancellation() throws {
        var preparing = try execution(OriginalQueryBudget())
        let owner = try prepared(.surfaceLift(.init(surface: plane(),parameterCurve: chart(alongU: false,reversed: true))),
            using: &preparing)
        for resource in [ExactResource.work,.storage] {
            let lower = try OriginalQueryBudget(workLimit: resource == .work ? 0 : nil,
                storageByteLimit: resource == .storage ? 0 : nil)
            var reader = try execution(lower)
            try refusal({ if case .resourceLimit(let actual)? = original($0) as? ExactScalarFailure { actual == resource } else { false } }) {
                _ = try issue(owner,over: .init(lower: 0.2,upper: 0.8),using: &reader)
            }
        }
        let checkpoints = Checkpoints()
        let measured = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
        _ = try coldIssue(measured)
        let end = measured.snapshot
        for stop in [1,checkpoints.count] {
            let cancelled = Checkpoints(stop: stop)
            let abort = try OriginalQueryBudget(checkpoint: { try cancelled.checkpoint() })
            try refusal({ if case .cancelled? = original($0) as? ExactScalarFailure { true } else { false } }) {
                _ = try coldIssue(abort)
            }
            try require(abort.snapshot.work == (stop == 1 ? 0 : end.work)
                && abort.snapshot.storageBytes == (stop == 1 ? 0 : end.storageBytes),
                "Entry or terminal cancellation changed its actual debit boundary.")
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
    static func retainedLifetimeAndNonunitStoredPlane() throws {
        let budget = try OriginalQueryBudget()
        var admission = try execution(budget)
        var input = Curve3D.surfaceLift(.init(surface: plane(),parameterCurve: chart(alongU: true,reversed: false)))
        let originalInput = input
        let receipt = try issue(prepared(input,using: &admission),over: .init(lower: 0,upper: 1),using: &admission)
        input = .surfaceLift(.init(surface: plane(z: 3),parameterCurve: chart(alongU: false,reversed: true)))
        try require(input != originalInput && receipt.prepared.curve == originalInput,
            "Mutating the caller source changed retained continuity authority.")
        let foreignBudget = try OriginalQueryBudget()
        var foreign = try execution(foreignBudget)
        let retained = try issue(receipt.prepared,over: receipt.parameters,using: &foreign)
        let jet = try retained.prepared.closedNativeJets(over: retained.parameters,tolerance: tolerance,
            maximumSpanCount: 64,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &foreign)
        try require(jet.spans.allSatisfy { $0.jet.z.value.lower <= 0 && $0.jet.z.value.upper < 1 }
            && foreignBudget.snapshot.work > 0 && foreignBudget.snapshot.storageBytes > 0,
            "A foreign reader lost original source lifetime or escaped readmission.")
        let host = Surface3D.plane(.init(origin: .origin,normal: .init(x: 0,y: 0,z: 2)))
        let nonunit = Curve3D.surfaceLift(.init(surface: host,parameterCurve: chart(alongU: true,reversed: false)))
        let nonunitReceipt = try issue(prepared(nonunit,using: &admission),over: receipt.parameters,using: &admission)
        try require(nonunitReceipt.prepared.curve == nonunit,"Continuity normalized or rebound the stored nonunit plane source.")
    }
    static func run() throws {
        try axesDirectionsSubdomainsAndWholeBound()
        try scopeAndUnsupportedGuards()
        try callerRefusalAndCancellation()
        try retainedLifetimeAndNonunitStoredPlane()
    }
}
