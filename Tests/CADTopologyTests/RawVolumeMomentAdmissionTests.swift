import CADCore
import CADGeometry
import CADTopology
import Synchronization

#if !RAW_VOLUME_MOMENT_PORTABLE
import Testing

@Suite("Raw volume moment admission", .timeLimit(.minutes(1)))
struct RawVolumeMomentAdmissionTests {
    @Test func ordinaryAndDirectRawCubePublishAllTenMoments() throws {
        try RawVolumeMomentAdmissionChecks.ordinaryAndDirectRawCubePublishAllTenMoments()
    }
    @Test func rawValidationAndIntegrationShareCallerResourceLimits() throws {
        try RawVolumeMomentAdmissionChecks.rawValidationAndIntegrationShareCallerResourceLimits()
    }
    @Test func missingBodyRefusesMomentPublication() throws {
        try RawVolumeMomentAdmissionChecks.missingBodyRefusesMomentPublication()
    }
    @Test func rawQueryRefusesEntryAndInProgressCancellation() throws {
        try RawVolumeMomentAdmissionChecks.rawQueryRefusesEntryAndInProgressCancellation()
    }
}
#endif

enum RawVolumeMomentAdmissionChecks {
    private typealias Shared = VolumeMomentLoopAdmissionChecks

    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int
        init(stop: Int) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw .cancelled }
        }
    }

    private static func query(_ model: BRepModel, bodyID: BodyID,
        using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
        let provider: any BRepVolumeMomentMeasuring = DefaultBRepVolumeMomentMeasurer()
        return try provider.moments(of: bodyID, in: model, options: Shared.options,
            tolerance: Shared.tolerance, using: &execution)
    }

    static func ordinaryAndDirectRawCubePublishAllTenMoments() throws {
        let input = Shared.cube()
        let provider: any BRepVolumeMomentMeasuring = DefaultBRepVolumeMomentMeasurer()
        print("RAW_MOMENT_ORDINARY_BEGIN")
        let ordinary = try provider.moments(of: input.bodyID, in: input.model,
            options: Shared.options, tolerance: Shared.tolerance)
        try Shared.checkMoments(ordinary)
        try Shared.require(ordinary.consumedWork > 0 && ordinary.consumedWork <= Shared.options.maximumWork,
            "Ordinary raw moments escaped their unchanged request ceiling.")
        print("RAW_MOMENT_ORDINARY_END work=\(ordinary.consumedWork)")

        let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork)
        var execution = try Shared.execution(budget)
        try execution.consumeWork(13)
        print("RAW_MOMENT_DIRECT_BEGIN prior=13")
        let result = try query(input.model, bodyID: input.bodyID, using: &execution)
        try Shared.checkMoments(result)
        try Shared.require(result.consumedWork == execution.localWork - 13
            && budget.snapshot.work == execution.localWork
            && execution.activeContributionCount == 0 && budget.snapshot.storageBytes > 0,
            "Raw validation and integration lost cumulative work ownership or their contribution scope.")
        try Shared.require(result.consumedWork > 0 && result.consumedWork <= Shared.options.maximumWork,
            "Direct raw moments escaped their unchanged request ceiling.")
        print("RAW_MOMENT_DIRECT_END work=\(result.consumedWork) cumulative=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
    }

    static func rawValidationAndIntegrationShareCallerResourceLimits() throws {
        let input = Shared.cube()
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? 100_000 : Shared.options.maximumWork,
                storageByteLimit: resource == .storage ? 0 : nil)
            var execution = try Shared.execution(budget)
            do {
                _ = try query(input.model, bodyID: input.bodyID, using: &execution)
                throw Shared.Failure(message: "A resource-rejected raw moment invocation published output.")
            } catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
            }
            try Shared.require(execution.activeContributionCount == 0
                && execution.localWork == budget.snapshot.work,
                "Raw resource refusal lost the original owner or retained an active contribution.")
            if resource == .work {
                try Shared.require(budget.snapshot.work > 0 && budget.snapshot.work <= 100_000,
                    "Raw work refusal committed a rejected debit or reset admitted work.")
            } else {
                try Shared.require(budget.snapshot.storageBytes == 0,
                    "Raw storage refusal allocated a rejected payload.")
            }
            let axis = resource == .work ? "work" : "storage"
            print("RAW_MOMENT_RESOURCE axis=\(axis) work=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
        }
    }

    static func missingBodyRefusesMomentPublication() throws {
        let input = Shared.cube()
        let absent = BodyID(PortableIdentity128(high: 8, low: 2))
        let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork)
        var execution = try Shared.execution(budget)
        do {
            _ = try query(input.model, bodyID: absent, using: &execution)
            throw Shared.Failure(message: "A missing raw body published volume moments.")
        } catch {
            guard let failure = Shared.original(error) as? KernelError,
                failure.phase == .topology, failure.code == .resourceLimitExceeded,
                failure.message == "Volume moments require a solid and finite nonnegative accuracy." else { throw error }
        }
        try Shared.require(execution.activeContributionCount == 0 && budget.snapshot.work > 0,
            "Missing-body refusal bypassed raw validation or leaked its contribution.")
    }

    static func rawQueryRefusesEntryAndInProgressCancellation() throws {
        let input = Shared.cube()
        for stop in [1, 1_000] {
            let observer = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(workLimit: Shared.options.maximumWork,
                checkpoint: { try observer.check() })
            var execution = try Shared.execution(budget)
            do {
                _ = try query(input.model, bodyID: input.bodyID, using: &execution)
                throw Shared.Failure(message: "A cancelled raw moment invocation published output.")
            } catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .cancelled = scalar else { throw error }
            }
            try Shared.require(observer.count == stop && execution.activeContributionCount == 0
                && execution.localWork == budget.snapshot.work,
                "Raw cancellation lost its original checkpoint, work owner or contribution lifetime.")
            if stop == 1 {
                try Shared.require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                    "Entry cancellation consumed raw-query resources.")
            } else {
                try Shared.require(budget.snapshot.work > 0 && budget.snapshot.work <= Shared.options.maximumWork,
                    "In-progress raw cancellation reset or exceeded admitted work.")
            }
            print("RAW_MOMENT_CANCEL checkpoint=\(stop) work=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
        }
    }
}
