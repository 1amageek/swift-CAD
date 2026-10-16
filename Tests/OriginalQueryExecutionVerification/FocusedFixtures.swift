import CADCore
@testable import CADGeometry
import L0
import Synchronization

extension OriginalQueryExecutionAcceptance {
    final class LifetimeCounter: Sendable { let value = Mutex(0) }
    final class LifetimeOwner: Sendable {
        let counter: LifetimeCounter
        init(_ counter: LifetimeCounter) { self.counter = counter }
        deinit { counter.value.withLock { $0 += 1 } }
    }

    static func focusedIndependentAxesAndLifetime() throws {
        let ceilings = try OriginalQueryExecutionLimits(maximumValueDepth: 1,
            maximumCoefficientDepth: 2, maximumCells: 3, remainingSourceDepth: 4,
            maximumTransportDepth: 5, maximumSubdivisionDepth: 6)
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: ceilings)
        try execution.admitDepth(value: 1, coefficient: 2)
        try execution.admitSourceDepth(4)
        try execution.admitTransportDepth(5)
        try execution.admitGeometricDepth(6)
        try execution.consumeCells(3)
        try rejects { try execution.admitDepth(value: 2, coefficient: 0) }
        try rejects { try execution.admitDepth(value: 0, coefficient: 3) }
        try rejects { try execution.admitSourceDepth(5) }
        try rejects { try execution.admitTransportDepth(6) }
        try rejects { try execution.admitGeometricDepth(7) }
        try rejects { try execution.consumeCells(1) }
        try require(execution.valueDepth == 1 && execution.coefficientDepth == 2
            && execution.sourceDepth == 4 && execution.transportDepth == 5
            && execution.geometricDepth == 6 && execution.visitedCells == 3)

        let released = LifetimeCounter()
        func retainUntilExecutionEnds() throws {
            var reader = OriginalQueryExecution(budget: try OriginalQueryBudget(), limits: ceilings)
            func admitOwner() throws {
                let owner = LifetimeOwner(released)
                let zero = try ExactScalarDepth(value: 0, coefficient: 0)
                let admitted = try reader.admitRetainedPreparation(owner: owner,
                    budget: try OriginalQueryBudget(), work: 1, storageBytes: 1,
                    depth: zero, sourceDepth: 0, geometricDepth: 0, transportDepth: 0)
                try require(admitted)
            }
            try admitOwner()
            try require(released.value.withLock { $0 } == 0)
            try reader.consumeWork(1)
        }
        try retainUntilExecutionEnds()
        try require(released.value.withLock { $0 } == 1)
        print("PASS independent depth/cell ceilings and retained preparation lifetime")
    }

    static func focusedNestedCleanup() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        do {
            _ = try execution.withPreparationScope { a in
                _ = try a.openPreparationScope()
                try a.admitSourceDepth(2)
                throw ExternalStop()
            }
            throw Failure(line: #line)
        } catch is ExternalStop {}
        let next = try execution.withPreparationScope { a in
            try a.admitDepth(value: 1, coefficient: 0)
            try a.admitSourceDepth(1)
        }
        try require(next.depth.scalar.value == 1 && next.depth.sourceDepth == 1)
        do {
            try execution.withConversionScope(maximumWorkUnits: 1, maximumScalarCount: 1,
                maximumCertificationBoxes: 1) { a in
                _ = try a.openConversionScope(maximumWorkUnits: 0, maximumScalarCount: 0,
                    maximumCertificationBoxes: 0)
                throw ExternalStop()
            }
            throw Failure(line: #line)
        } catch is ExternalStop {}
        try require(execution.conversionScopeSnapshot == nil)
        try execution.charge(scalars: 2, work: 2)
        print("PASS preparation/conversion descendant cleanup preserves original error and restores scopes")
    }

    static func focusedExactPredicateBoundary() throws {
        let a = Point3D(x: 1, y: 1, z: 1)
        let b = Point3D(x: 1, y: 1.nextUp, z: 1)
        let c = Point3D(x: 1, y: 1, z: 1.nextUp)
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: 0, maximumCoefficientDepth: 0)
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: limits)
        try require(try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .positive)
        let work = budget.snapshot.work
        let bytes = budget.snapshot.storageBytes
        try require(work > 1 && bytes > 0)
        let exact = try OriginalQueryBudget(workLimit: work, storageByteLimit: bytes)
        var bounded = OriginalQueryExecution(budget: exact, limits: limits)
        try require(try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
            determinantTolerance: 0, using: &bounded) == .positive)
        try require(exact.snapshot.work == work && exact.snapshot.storageBytes == bytes)
        var short = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: work - 1), limits: limits)
        try rejects {
            _ = try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
                determinantTolerance: 0, using: &short)
        }
        var small = OriginalQueryExecution(budget: try OriginalQueryBudget(storageByteLimit: bytes - 1), limits: limits)
        try rejects {
            _ = try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
                determinantTolerance: 0, using: &small)
        }
        try require(try RobustPredicates.orientation3D(a, c, b, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .negative)
        try require(try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
            determinantTolerance: 0x1p-103, using: &execution) == .indeterminate)
        let difference = try FloatingPointExpansion.difference(0x1p100, 1, using: &execution)
        try require(difference == [-1, 0x1p100])
        let factor = try FloatingPointExpansion.difference(0.75, 0.125, using: &execution)
        let product = try FloatingPointExpansion.product(difference, factor, using: &execution)
        try require(product == [-0.625, 0.625 * 0x1p100])
        print("PASS true 3D cancellation branch, exact work/storage N and N-1, and binary expansion oracle")
    }

    struct ClassifyingFailure: KernelFailureClassifying {
        let kernelFailure: KernelError
    }

    static func focusedSourceTextContributions() throws {
        let budget = try OriginalQueryBudget(sourceTextByteLimit: 8)
        let parent = try budget.makeContributionHandle(sourceTextByteLimit: 5)
        var execution = try OriginalQueryExecution(contribution: parent, limits: try limits())
        let child = try execution.makeContributionHandle(sourceTextByteLimit: 3)
        try execution.retainStorage(bytes: 16)
        try require(parent.snapshot.sourceTextBytes == 0 && child.snapshot.sourceTextBytes == 0)
        try execution.withContributionScopes([child, child]) { a in
            try a.chargeSourceText(storageBytes: 2)
            try a.chargeSourceText(storageBytes: 1)
            let before = budget.snapshot
            try rejects { try a.chargeSourceText(records: 1, work: 1, storageBytes: 1) }
            try require(budget.snapshot.work == before.work && budget.snapshot.records == before.records
                && budget.snapshot.storageBytes == before.storageBytes
                && budget.snapshot.sourceTextBytes == before.sourceTextBytes)
        }
        try require(child.snapshot.sourceTextBytes == 3 && child.remainingSourceTextBytes == 0)
        try require(parent.snapshot.sourceTextBytes == 3 && parent.remainingSourceTextBytes == 2)
        try execution.chargeSourceText(storageBytes: 2)
        try require(parent.snapshot.sourceTextBytes == 5 && child.snapshot.sourceTextBytes == 3)
        let before = budget.snapshot
        try rejects { try execution.chargeSourceText(storageBytes: 1) }
        try require(budget.snapshot.storageBytes == before.storageBytes && parent.remainingSourceTextBytes == 0)
        try budget.chargeSourceText(storageBytes: 3)
        try require(budget.snapshot.sourceTextBytes == 8 && parent.snapshot.sourceTextBytes == 5)
        try rejects { try budget.chargeSourceText(storageBytes: 1) }
        var reused = try OriginalQueryExecution(contribution: child, limits: try limits())
        try rejects { try reused.chargeSourceText(storageBytes: 1) }
        try require(budget.snapshot.work == 0 && budget.snapshot.records == 0)
        try rejects { _ = try budget.makeContributionHandle(sourceTextByteLimit: -1) }
        try rejects { _ = try execution.makeContributionHandle(sourceTextByteLimit: -1) }
        let quantumBudget = try OriginalQueryBudget()
        let quantum = try quantumBudget.makeContributionHandle(sourceTextByteLimit: 1, storageByteQuantum: 4)
        try quantumBudget.chargeSourceText(storageBytes: 1, contributions: [quantum, quantum])
        try require(quantum.snapshot.storageBytes == 4 && quantum.snapshot.sourceTextBytes == 1)
        try require(quantumBudget.snapshot.sourceTextBytes == 1 && quantum.remainingSourceTextBytes == 0)
        try rejects { try quantumBudget.chargeSourceText(storageBytes: 1, contribution: quantum) }
        let zero = try quantumBudget.makeContributionHandle(sourceTextByteLimit: 0)
        try quantumBudget.retainStorage(bytes: 32, contribution: zero)
        try require(zero.snapshot.sourceTextBytes == 0)
        try rejects { try quantumBudget.chargeSourceText(storageBytes: 1, contribution: zero) }
        print("PASS root/child persistent text ceilings, atomic rejection, duplicate attachment and exact text bytes")
    }

    static func focusedFailureClassification() throws {
        let original = KernelError(phase: .validation, code: .unsupportedCapability,
            residual: 0.25, tolerance: nil, message: "Retained classifier witness")
        let known = ClassifyingFailure(kernelFailure: original)
        let wrapped = KernelError.wrapping(known, phase: .geometry, tolerance: .standard)
        try require(wrapped.phase == original.phase && wrapped.code == original.code
            && wrapped.message == original.message && wrapped.residual == original.residual
            && wrapped.tolerance == .standard)
        let erased: any Error = original
        let erasedWrapped = KernelError.wrapping(erased, phase: .geometry, tolerance: .standard)
        if erasedWrapped.phase != original.phase || erasedWrapped.code != original.code {
            print("FAIL erased Core classification: phase=\(erasedWrapped.phase.rawValue), code=\(erasedWrapped.code.rawValue)")
        }
        try require(erasedWrapped.phase == original.phase && erasedWrapped.code == original.code
            && erasedWrapped.message == original.message && erasedWrapped.residual == original.residual
            && erasedWrapped.tolerance == .standard)
        let foreign: any Error = ExternalStop()
        try require(KernelError.wrapping(foreign, phase: .geometry, tolerance: nil).code == .unclassifiedFailure)
        print("PASS classifier concrete witness overload")
        let context = OriginalQueryFailureContext(operation: .conversion, entry: .admitted, stage: .relation)
        let retained = OriginalQueryFailure.published(ExactScalarFailure.resourceLimit(.work),
            context: context, tolerance: nil)
        let discovered = OriginalQueryFailure.classification(of: retained)
        let retainedFailure = retained as? OriginalQueryFailure
        if discovered == nil { print("FAIL Geometry classification(of:) returned nil") }
        if retainedFailure == nil { print("FAIL caller Error-to-OriginalQueryFailure cast returned nil") }
        guard let classification = discovered, let failure = retainedFailure else {
            throw Failure(line: #line)
        }
        try require(classification.code == .resourceLimitExceeded)
        try require(failure.context.operation == .conversion && failure.context.stage == .relation)
        guard let scalar = failure.originalError as? ExactScalarFailure,
            case .resourceLimit(.work) = scalar else {
            print("FAIL retained original scalar cause discovery")
            throw Failure(line: #line)
        }
        try require(OriginalQueryFailure.classification(of: original) == original)
        print("PASS known classifier witness and retained concrete original failure classification")
    }

    static func focusedPredicates() throws {
        let origin = Point2D(x: 0, y: 0)
        let diagonal = Point2D(x: 1, y: 1)
        let nearby = Point2D(x: 2, y: 2.nextUp)
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget, limits: try limits())
        try require(try RobustPredicates.orientation2D(origin, diagonal,
            relativeTo: nearby, determinantTolerance: 0, using: &execution) == .positive)
        try require(try RobustPredicates.orientation2D(origin, diagonal,
            relativeTo: Point2D(x: 2, y: 2), determinantTolerance: 1,
            using: &execution) == .zero)
        try require(try RobustPredicates.orientation2D(origin, diagonal,
            relativeTo: nearby, determinantTolerance: 1, using: &execution) == .indeterminate)
        let huge = 1e308
        try require(try RobustPredicates.orientation2D(Point2D(x: huge, y: 0),
            Point2D(x: 0, y: huge), relativeTo: origin,
            determinantTolerance: 0, using: &execution) == .positive)
        try require(budget.snapshot.work > 4 && budget.snapshot.storageBytes > 0)
        var denied = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: 1),
            limits: try limits())
        try rejects {
            _ = try RobustPredicates.orientation2D(origin, diagonal, relativeTo: nearby,
                determinantTolerance: 0, using: &denied)
        }
        try require(denied.localWork == 1)
        let a = Point3D(x: 1, y: 0, z: 0)
        let b = Point3D(x: 0, y: 1, z: 0)
        let c = Point3D(x: 0, y: 0, z: 1)
        try require(try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .positive)
        try require(try RobustPredicates.orientation3D(a, b, c, relativeTo: .origin,
            determinantTolerance: 2, using: &execution) == .indeterminate)
        try require(try RobustPredicates.orientation3D(a, b, a, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .zero)
        try rejects {
            _ = try RobustPredicates.orientation2D(origin, diagonal, relativeTo: nearby,
                determinantTolerance: .nan, using: &execution)
        }
        try require(try RobustPredicates.orientation2D(Point2D(x: 476038661, y: 48605832),
            Point2D(x: -611465690, y: -69332139), relativeTo: origin,
            determinantTolerance: 3283980011921799, using: &execution) == .indeterminate)
        try require(try RobustPredicates.orientation3D(Point3D(x: -300368, y: 359871, z: 423778),
            Point3D(x: 241545, y: 260068, z: 272867), Point3D(x: 317110, y: 238413, z: 196568),
            relativeTo: .origin, determinantTolerance: 7693130806237696,
            using: &execution) == .indeterminate)
        let tinyA = Point3D(x: 1e-200, y: 0, z: 0)
        let tinyB = Point3D(x: 0, y: 1e-200, z: 0)
        let tinyC = Point3D(x: 0, y: 0, z: 1e-200)
        try require(try RobustPredicates.orientation3D(tinyA, tinyB, tinyC, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .positive)
        try require(try RobustPredicates.orientation3D(tinyA, tinyC, tinyB, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .negative)
        try require(try RobustPredicates.orientation3D(tinyA, tinyB, tinyC, relativeTo: .origin,
            determinantTolerance: .leastNormalMagnitude, using: &execution) == .indeterminate)
        try require(try RobustPredicates.orientation3D(tinyA, tinyB, tinyA, relativeTo: .origin,
            determinantTolerance: 0, using: &execution) == .zero)
        try require(try RobustPredicates.orientation3D(Point3D(x: huge, y: 0, z: 0),
            Point3D(x: 0, y: huge, z: 0), Point3D(x: 0, y: 0, z: huge),
            relativeTo: .origin, determinantTolerance: 0, using: &execution) == .positive)
        try require(try RobustPredicates.orientation3D(tinyA, tinyB, tinyC, relativeTo: .origin,
            determinantTolerance: 0) == .positive)
        print("PASS admitted exact 2D/3D predicates, tolerance, underflow/overflow-safe exact source signs and rejection")
    }
}
