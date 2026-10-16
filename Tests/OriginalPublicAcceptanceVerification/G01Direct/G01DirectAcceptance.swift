import CADCore
import CADGeometry
import Synchronization

@main struct G01DirectAcceptance {
    struct Failure: Error { let line: Int; let detail: String }
    enum Entry: String, CaseIterable { case ordinary, admitted, prepared }
    enum Selection: String, CaseIterable { case singleton, wide, regression }
    struct Retained {
        let relation: OriginalBoundedSphereConeSurfaceRelation
        let swapped: Bool
        let chart: OriginalSourceChart<OriginalBoundedSphereConeSurfaceSnapshot, Int>
    }
    final class CheckpointCounter: Sendable {
        private let count = Mutex(0)
        private let cancelAt: Int?
        init(cancelAt: Int? = nil) { self.cancelAt = cancelAt }
        var total: Int { count.withLock { $0 } }
        func checkpoint() throws {
            let current = count.withLock { value in value += 1; return value }
            if current == cancelAt { throw CancellationError() }
        }
    }
    static let workLimit = 8_388_608
    static let byteLimit = 268_435_456
    static let options = SurfaceSurfaceIntersectionOptions(maximumSubdivisionDepth: 8)

    static func require(_ condition: Bool, _ detail: String, line: Int = #line) throws {
        guard condition else { throw Failure(line: line, detail: detail) }
    }
    static func executionLimits(source: Int = 1, coefficient: Int = 32, geometric: Int = 8)
        throws -> OriginalQueryExecutionLimits {
        try .init(maximumValueDepth: 32, maximumCoefficientDepth: coefficient,
            maximumCells: 262_144, maximumCharts: 262_144, maximumFamilies: 262_144,
            maximumResults: 1_024, remainingSourceDepth: source, maximumTransportDepth: 32,
            maximumSubdivisionDepth: geometric, maximumSpans: 262_144)
    }
    static func readerLimits() throws -> OriginalDomainIdentityLimits {
        try .init(source: .init(remainingSourceDepth: 1), maximumTransportDepth: 1,
            maximumCharts: 2, maximumFamilies: 2, maximumIdentityProofs: 0)
    }
    static func freshExecution(source: Int = 1, coefficient: Int = 32, geometric: Int = 8)
        throws -> OriginalQueryExecution {
        .init(budget: try OriginalQueryBudget(workLimit: workLimit, storageByteLimit: byteLimit),
            limits: try executionLimits(source: source, coefficient: coefficient, geometric: geometric))
    }
    static func input(swapped: Bool) -> (Surface3D, Surface3D) {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let cone = Surface3D.analytic(.cone(apex: .init(x: 3, y: 0, z: -4),
            axis: .unitZ, halfAngle: Double(bitPattern: 0x3fddac670561bb50)))
        return swapped ? (cone, sphere) : (sphere, cone)
    }
    static func boxes(_ selection: Selection, swapped: Bool) throws -> (SurfaceParameterBox, SurfaceParameterBox) {
        let sphere = SurfaceParameterBox(u: try .init(lower: -2, upper: -1), v: try .init(lower: -1, upper: 0))
        let cone = SurfaceParameterBox(u: try .init(lower: selection == .regression ? 1 : 0.5,
            upper: selection == .singleton ? 0.5 : 2), v: try .init(lower: 3, upper: 4))
        return swapped ? (cone, sphere) : (sphere, cone)
    }
    static func query(_ entry: Entry, selection: Selection, swapped: Bool) throws -> SurfaceSurfaceIntersectionResult {
        print("START G01 query \(entry.rawValue) \(selection.rawValue) swapped=\(swapped)")
        var (first, second) = input(swapped: swapped)
        let (firstBox, secondBox) = try boxes(selection, swapped: swapped)
        let intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let result: SurfaceSurfaceIntersectionResult
        switch entry {
        case .ordinary:
            result = try intersector.intersectionResult(first: first, over: firstBox,
                second: second, over: secondBox, options: options, tolerance: .standard)
        case .admitted:
            var execution = try freshExecution()
            result = try intersector.intersectionResult(first: first, over: firstBox,
                second: second, over: secondBox, options: options, tolerance: .standard, using: &execution)
            try require(execution.budget.snapshot.work <= workLimit
                && execution.budget.snapshot.storageBytes <= byteLimit, "direct query escaped caller ceilings")
            print("USAGE G01 admitted \(selection.rawValue) swapped=\(swapped) work=\(execution.budget.snapshot.work) bytes=\(execution.budget.snapshot.storageBytes)")
        case .prepared:
            var execution = try freshExecution()
            let prepared: any OriginalSurfacePairIntersecting = try intersector.prepareOriginalPair(
                first: first, second: second, tolerance: .standard, using: &execution)
            result = try prepared.intersectionResult(firstBox: firstBox, secondBox: secondBox,
                options: options, using: &execution)
            try require(execution.budget.snapshot.work <= workLimit
                && execution.budget.snapshot.storageBytes <= byteLimit, "prepared query escaped shared caller ceilings")
            print("USAGE G01 prepared \(selection.rawValue) swapped=\(swapped) work=\(execution.budget.snapshot.work) bytes=\(execution.budget.snapshot.storageBytes)")
        }
        print("STAGE G01 query produced \(entry.rawValue) \(selection.rawValue) swapped=\(swapped)")
        first = .analytic(.plane(origin: .origin, normal: .unitZ))
        second = .analytic(.plane(origin: .init(x: 0, y: 0, z: 1), normal: .unitZ))
        try require(first != input(swapped: swapped).0 && second != input(swapped: swapped).1,
            "lifetime setup did not replace caller source values")
        return result
    }
    static func check(_ result: SurfaceSurfaceIntersectionResult, selection: Selection, swapped: Bool) throws -> Retained {
        print("STAGE G01 check reader \(selection.rawValue) swapped=\(swapped)")
        guard let reader = result.originalBoundedSphereConeRelation else {
            throw Failure(line: #line, detail: "rich public result lost bounded sphere/cone witness")
        }
        let relation = reader.original
        print("STAGE G01 check chart \(selection.rawValue) swapped=\(swapped)")
        var identity = try freshExecution()
        let chart = try relation.source.chart(0, limits: readerLimits().source, using: &identity)
        print("STAGE G01 check metadata \(selection.rawValue) swapped=\(swapped)")
        let pair = input(swapped: swapped)
        try require(result.representation == .exactRelation, "public path returned numerical representatives")
        try require(relation.source.original.original.first == pair.0
            && relation.source.original.original.second == pair.1, "retained source lifetime/order changed")
        if selection == .singleton {
            try require(reader.isEmpty && relation.isEmpty && result.intersections.isEmpty,
                "negative singleton did not retain exact empty publication")
            try require(relation.branchCount == 0 && relation.imageDimension == nil
                && relation.fiberDimension == nil && !reader.hasPositiveDimensionalImage
                && !reader.hasPositiveDimensionalSolutions, "empty relation dimensions are inconsistent")
            try require(relation.finiteCut?.isEmpty == true && relation.finiteCut?.boundaryRoot == nil,
                "singleton exclusion lost complete finite-cut authority")
        } else {
            guard result.intersections.count == 1,
                case .originalBoundedSphereCone(let component) = result.intersections[0] else {
                throw Failure(line: #line, detail: "public result lost its single original component")
            }
            try require(!reader.isEmpty && reader.hasPositiveDimensionalSolutions && reader.hasPositiveDimensionalImage
                && relation.branchCount == 1 && relation.imageDimension == 1 && relation.fiberDimension == 0,
                "selected relation dimensions changed")
            try require(component.relation === relation && !component.isClosed
                && component.imageDimension == 1 && component.firstSurface == pair.0 && component.secondSurface == pair.1,
                "published component has a different owner/order")
            let requested = try boxes(selection, swapped: swapped)
            if selection == .wide {
                guard let cut = relation.finiteCut, let root = cut.boundaryRoot else {
                    throw Failure(line: #line, detail: "wide public result lost exact finite-cut endpoint")
                }
                try require(relation.finiteArc == nil && !cut.isEmpty && cut.branch == 1
                    && cut.firstBox == requested.0 && cut.secondBox == requested.1
                    && root.source.owns(chart) && root.candidateBranch == 1,
                    "finite cut changed original domains/source branch")
            } else {
                guard let arc = relation.finiteArc else {
                    throw Failure(line: #line, detail: "old selected [1,2] result lost its finite arc")
                }
                try require(relation.finiteCut == nil && arc.coneU == 1...2 && arc.branch == 1
                    && arc.firstBox == requested.0 && arc.secondBox == requested.1, "old selected-domain regression")
            }
        }
        return Retained(relation: relation, swapped: swapped, chart: chart)
    }
    static func queries(_ entry: Entry) throws -> [Retained] {
        var wide: [Retained] = []
        for selection in Selection.allCases {
            for swapped in [false, true] {
                let kept = try check(query(entry, selection: selection, swapped: swapped), selection: selection, swapped: swapped)
                if selection == .wide { wide.append(kept) }
                if selection == .regression && entry == .admitted {
                    for u in [1.0, 1.5, 2.0] { try member(kept, rawU: u) }
                    try directArcReaders(kept)
                }
                print("PASS G01 query \(entry.rawValue) \(selection.rawValue) swapped=\(swapped)")
            }
        }
        print("PASS G01 public \(entry.rawValue)")
        return wide
    }
    static func member(_ kept: Retained, rawU: Double) throws {
        var a = try freshExecution()
        let q = ExactRationalScalarDomain()
        let zero = try OriginalParameterCycle(exact: q.integer(0, using: &a), using: &a)
        let value = try kept.relation.member(coneU: rawU, branch: 1, coneCycle: zero,
            sphereCycle: zero, limits: readerLimits(), using: &a)
        try require(value.relation === kept.relation && value.branch == 1
            && value.position.source.owns(kept.chart), "member lost original owner/branch")
        let first = try value.firstUV(limits: readerLimits(), using: &a)
        let second = try value.secondUV(limits: readerLimits(), using: &a)
        guard case .cone(let u, let v) = kept.swapped ? first : second,
            case .sphere(let sphere) = kept.swapped ? second : first else {
            throw Failure(line: #line, detail: "finite member lost complete original UV families")
        }
        let field = kept.relation.source.original.field
        try require(field.compare(u, field.binary64(exactly: rawU, using: &a), using: &a) == .equal,
            "exact authored membership label changed")
        try require(v.branch == 1 && sphere.x.axis == 0 && sphere.y.axis == 1 && sphere.z.axis == 2
            && value.position.x.axis == 0 && value.position.y.axis == 1 && value.position.z.axis == 2,
            "member XYZ/UV symbolic axes changed")
        print("PASS G01 member u=\(rawU) swapped=\(kept.swapped)")
    }
    static func directArcReaders(_ kept: Retained) throws {
        guard let arc = kept.relation.finiteArc else {
            throw Failure(line: #line, detail: "direct arc reader control lost regression arc")
        }
        var sourceOne = try freshExecution()
        try arc.admitProof(using: &sourceOne)
        let u = try kept.relation.source.original.field.binary64(exactly: 1.5, using: &sourceOne)
        let position = try arc.position(coneU: u, using: &sourceOne)
        try require(position.source.owns(kept.chart) && position.branch == 1,
            "source1 direct arc position lost original owner/branch")
        var proofSourceZero = try freshExecution(source: 0)
        try rejectsResource(.sourceDepth) { try arc.admitProof(using: &proofSourceZero) }
        try require(proofSourceZero.budget.snapshot.work == 0
            && proofSourceZero.budget.snapshot.storageBytes == 0,
            "direct arc source0 proof mutated counters before refusal")
        var positionSourceZero = try freshExecution(source: 0)
        try rejectsResource(.sourceDepth) { _ = try arc.position(coneU: u, using: &positionSourceZero) }
        try require(positionSourceZero.budget.snapshot.work == 0
            && positionSourceZero.budget.snapshot.storageBytes == 0,
            "direct arc source0 position mutated counters or published output")
        print("PASS G01 direct arc source0/source1 readers swapped=\(kept.swapped)")
    }
    static func outside(_ error: any Error) -> Bool {
        if let failure = error as? OriginalQueryFailure { return outside(failure.originalError) }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let cause) = failure { return outside(cause) }
        if let failure = error as? OriginalDomainIdentityFailure, case .outsideSupport = failure { return true }
        return false
    }
    static func resource(_ error: any Error) -> OriginalQueryFailure? {
        if let failure = error as? OriginalQueryFailure { return failure }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let cause) = failure { return resource(cause) }
        return nil
    }
    static func rejectsResource(_ axis: OriginalQueryResourceAxis, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let failure = resource(error), failure.context.resource?.axis == axis,
                OriginalQueryFailure.classification(of: failure)?.code == .resourceLimitExceeded else { throw error }
            return
        }
        throw Failure(line: #line, detail: "expected original resource axis \(axisName(axis))")
    }
    static func isCancelled(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let failure = error as? OriginalQueryFailure { return isCancelled(failure.originalError) }
        if let failure = error as? ExactScalarFailure {
            if case .cancelled = failure { return true }
            if case .admissionRejected(let cause) = failure { return isCancelled(cause) }
        }
        return false
    }
    static func rejectsCancellation(_ operation: () throws -> Void) throws {
        do { try operation() }
        catch { guard isCancelled(error) else { throw error }; return }
        throw Failure(line: #line, detail: "cancelled public operation returned success")
    }
    static func readers(_ retained: [Retained]) throws {
        for kept in retained {
            try require(kept.relation.source.owns(kept.chart), "detached source owner was released")
            guard let root = kept.relation.finiteCut?.boundaryRoot else {
                throw Failure(line: #line, detail: "detached public cut lost root")
            }
            var a = try freshExecution()
            let limits = try readerLimits().source
            let position = try root.position(limits: limits, using: &a)
            try require(root.boundaryStation == -1 && root.boundaryCoordinate == (kept.swapped ? .secondU : .firstU)
                && position.x.axis == 0 && position.y.axis == 1 && position.z.axis == 2, "endpoint source station/XYZ axes changed")
            for coordinate in [position.firstUV.u, position.firstUV.v, position.secondUV.u, position.secondUV.v] {
                try require(root.owns(coordinate), "4UV projection has a foreign implicit root")
                let interval = try coordinate.enclosure(limits: limits, using: &a)
                let requested = root.requestedBox.interval(for: coordinate.axis)
                if coordinate.axis == root.boundaryCoordinate {
                    try require(interval.lower == -1 && interval.upper == -1, "authored boundary label moved")
                } else {
                    try require(interval.lower > requested.lower && interval.upper < requested.upper,
                        "dependent endpoint isolation escaped the original requested interior")
                }
            }
            for xyz in [position.x, position.y, position.z] {
                try require(root.owns(xyz) && xyz.isFirst == kept.swapped, "XYZ projection lost implicit root/source order")
                let law = try xyz.originalLaw(limits: limits, using: &a)
                let expected = kept.swapped ? root.source.original.firstLaw : root.source.original.secondLaw
                let uv = try xyz.parameters(limits: limits, using: &a)
                let lawChart = try expected.source.chart(0, limits: limits, using: &a)
                try require(law.source.owns(lawChart) && !uv.isSphere
                    && root.owns(uv.u) && root.owns(uv.v), "XYZ does not compose original cone law with same root UV")
            }
            for rawU in [0.93, 1.0, 1.5, 2.0] { try member(kept, rawU: rawU) }
            var negative = try freshExecution()
            let zero = try OriginalParameterCycle(exact: ExactRationalScalarDomain().integer(0, using: &negative), using: &negative)
            do {
                _ = try kept.relation.member(coneU: 0.9, branch: 1, coneCycle: zero,
                    sphereCycle: zero, limits: readerLimits(), using: &negative)
                throw Failure(line: #line, detail: "outside authored label was published")
            } catch { guard outside(error) else { throw error } }
            var lowSource = try freshExecution(source: 0)
            try rejectsResource(.sourceDepth) { _ = try root.position(limits: limits, using: &lowSource) }
            try require(lowSource.budget.snapshot.work == 0, "source N-1 reader mutated work")
            var lowCoefficient = try freshExecution(coefficient: root.proofDepth.coefficient - 1)
            try rejectsResource(.coefficientDepth) { _ = try root.position(limits: limits, using: &lowCoefficient) }
            try require(lowCoefficient.budget.snapshot.work == 0, "coefficient N-1 reader mutated work")
            var lowGeometric = try freshExecution(geometric: root.contractionCount - 1)
            try rejectsResource(.geometricDepth) { _ = try root.position(limits: limits, using: &lowGeometric) }
            try require(lowGeometric.budget.snapshot.work == 0, "geometric N-1 reader mutated work")
            let cancelledBudget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
            var cancelled = OriginalQueryExecution(budget: cancelledBudget, limits: try executionLimits())
            try rejectsCancellation { _ = try root.position(limits: limits, using: &cancelled) }
            try require(cancelledBudget.snapshot.work == 0 && cancelledBudget.snapshot.storageBytes == 0,
                "cancelled retained reader mutated counters")
        }
        print("PASS G01 public readers")
    }
    static func terminalCancellation(_ selection: Selection) throws {
        let pair = input(swapped: false), request = try boxes(selection, swapped: false)
        let baselineCounter = CheckpointCounter()
        let baselineBudget = try OriginalQueryBudget(workLimit: workLimit, storageByteLimit: byteLimit,
            checkpoint: { try baselineCounter.checkpoint() })
        var baseline = OriginalQueryExecution(budget: baselineBudget, limits: try executionLimits())
        let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.0, over: request.0,
            second: pair.1, over: request.1, options: options, tolerance: .standard, using: &baseline)
        _ = try check(result, selection: selection, swapped: false)
        let terminal = baselineCounter.total
        try require(terminal > 1 && baselineBudget.snapshot.work > 0, "terminal baseline has no paid original proof")
        let cancelledCounter = CheckpointCounter(cancelAt: terminal)
        let cancelledBudget = try OriginalQueryBudget(workLimit: workLimit, storageByteLimit: byteLimit,
            checkpoint: { try cancelledCounter.checkpoint() })
        var cancelled = OriginalQueryExecution(budget: cancelledBudget, limits: try executionLimits())
        var publication: SurfaceSurfaceIntersectionResult?
        do {
            publication = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.0, over: request.0,
                second: pair.1, over: request.1, options: options, tolerance: .standard, using: &cancelled)
            throw Failure(line: #line, detail: "terminal cancellation published a result")
        } catch {
            guard error is CancellationError else { throw error }
        }
        try require(publication == nil && cancelledCounter.total == terminal,
            "terminal cancellation returned output or missed the observed checkpoint")
        try require(cancelledBudget.snapshot.work == baselineBudget.snapshot.work
            && cancelledBudget.snapshot.storageBytes == baselineBudget.snapshot.storageBytes
            && cancelledBudget.snapshot.cellVisits == baselineBudget.snapshot.cellVisits,
            "terminal cancellation did not reach the same paid publication boundary")
        let context = cancelled.context
        guard let first = context.first, let second = context.second,
            case .surfaceBox(let retainedFirst) = first.request,
            case .surfaceBox(let retainedSecond) = second.request,
            case .firstSurface = first.role, case .secondSurface = second.role else {
            throw Failure(line: #line, detail: "terminal cancellation lost original selected requests")
        }
        try require(context.operation == .surfaceSurface && context.entry == .admitted
            && context.stage == .publication && retainedFirst == request.0 && retainedSecond == request.1
            && context.firstOwner?.sourceDepth == 1 && context.secondOwner?.sourceDepth == 1,
            "terminal cancellation lost admitted publication/source authority context")
        print("PASS G01 terminal cancellation \(selection.rawValue) checkpoint=\(terminal) noOutput=true")
    }
    static func sameCounters(_ lhs: OriginalQueryBudgetSnapshot, _ rhs: OriginalQueryBudgetSnapshot) -> Bool {
        lhs.work == rhs.work && lhs.storageBytes == rhs.storageBytes
            && lhs.cellVisits == rhs.cellVisits && lhs.records == rhs.records
            && lhs.sourceTextBytes == rhs.sourceTextBytes
    }
    static func retainedContributionReadmission() throws {
        let budget = try OriginalQueryBudget(workLimit: workLimit, storageByteLimit: byteLimit)
        var issuer = OriginalQueryExecution(budget: budget, limits: try executionLimits())
        let contribution = try issuer.makeContributionHandle(executionLimits: executionLimits())
        let pair = input(swapped: false), request = try boxes(.regression, swapped: false)
        let intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        let result = try issuer.withContributionScope(contribution) { a in
            try intersector.intersectionResult(first: pair.0, over: request.0,
                second: pair.1, over: request.1, options: options, tolerance: .standard, using: &a)
        }
        guard let relation = result.originalBoundedSphereConeRelation?.original,
            let arc = relation.finiteArc else {
            throw Failure(line: #line, detail: "contribution-issued public query lost its finite arc")
        }
        try require(arc.coneU == 1...2 && arc.branch == 1 && !relation.isEmpty,
            "contribution-issued regression changed its original domain or branch")
        try require(contribution.snapshot.work > 0 && contribution.snapshot.storageBytes > 0,
            "public issuance did not attribute actual work/storage to its retained contribution")
        try require(issuer.activeContributionCount == 0, "issuer contribution scope did not close")
        var sourceZero = OriginalQueryExecution(budget: budget, limits: try executionLimits(source: 0))
        try require(sourceZero.activeContributionCount == 0,
            "same-budget reader setup preattached the retained contribution")
        let beforeBudget = budget.snapshot, beforeContribution = contribution.snapshot
        do {
            try arc.admitProof(using: &sourceZero)
            throw Failure(line: #line, detail: "same-budget source0 retained read returned success")
        } catch {
            guard let failure = resource(error),
                OriginalQueryFailure.classification(of: failure)?.code == .resourceLimitExceeded,
                let observation = failure.context.resource, observation.axis == .sourceDepth else { throw error }
            guard case .known(0) = observation.used, case .known(0) = observation.limit,
                case .known(1) = observation.requested else {
                throw Failure(line: #line, detail: "same-budget source0 refusal lost exact depth counts")
            }
        }
        try require(sameCounters(beforeBudget, budget.snapshot),
            "source0 retained read charged the shared budget before source refusal")
        try require(sameCounters(beforeContribution, contribution.snapshot),
            "source0 retained read charged the retained contribution before source refusal")
        try require(sourceZero.localWork == 0 && sourceZero.localStorageBytes == 0
            && sourceZero.activeContributionCount == 0,
            "source0 reader mutated local paid state or retained active scopes")
        print("PASS G01 retained contribution source preflight")
    }
    static func resources() throws {
        let pair = input(swapped: false), request = try boxes(.wide, swapped: false)
        for axis in [OriginalQueryResourceAxis.work, .storageBytes, .sourceDepth] {
            let budget = try OriginalQueryBudget(workLimit: axis == .work ? 0 : workLimit,
                storageByteLimit: axis == .storageBytes ? 0 : byteLimit)
            var a = OriginalQueryExecution(budget: budget, limits: try executionLimits(source: axis == .sourceDepth ? 0 : 1))
            try rejectsResource(axis) {
                _ = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.0, over: request.0,
                    second: pair.1, over: request.1, options: options, tolerance: .standard, using: &a)
            }
            if axis == .work { try require(budget.snapshot.work == 0, "zero work entry debited caller") }
            if axis == .storageBytes { try require(budget.snapshot.storageBytes == 0, "zero storage entry debited caller") }
        }
        let budget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var a = OriginalQueryExecution(budget: budget, limits: try executionLimits())
        try rejectsCancellation {
            _ = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.0, over: request.0,
                second: pair.1, over: request.1, options: options, tolerance: .standard, using: &a)
        }
        try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
            "cancelled public entry mutated caller counters")
        try retainedContributionReadmission()
        let regression = try boxes(.regression, swapped: false)
        func measured(work: Int, bytes: Int) throws -> (SurfaceSurfaceIntersectionResult, OriginalQueryBudgetSnapshot) {
            let owner = try OriginalQueryBudget(workLimit: work, storageByteLimit: bytes)
            var execution = OriginalQueryExecution(budget: owner, limits: try executionLimits())
            let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first: pair.0, over: regression.0,
                second: pair.1, over: regression.1, options: options, tolerance: .standard, using: &execution)
            return (result, owner.snapshot)
        }
        let baseline = try measured(work: workLimit, bytes: byteLimit)
        _ = try check(baseline.0, selection: .regression, swapped: false)
        let n = baseline.1
        try require(n.work > 0 && n.storageBytes > 0, "public baseline has no observed proof cost")
        let exact = try measured(work: n.work, bytes: n.storageBytes)
        _ = try check(exact.0, selection: .regression, swapped: false)
        try require(exact.1.work == n.work && exact.1.storageBytes == n.storageBytes,
            "exact N public source/proof cost changed")
        try rejectsResource(.work) { _ = try measured(work: n.work - 1, bytes: n.storageBytes) }
        try rejectsResource(.storageBytes) { _ = try measured(work: n.work, bytes: n.storageBytes - 1) }
        print("PASS G01 measured public N/N-1 work=\(n.work) bytes=\(n.storageBytes)")
        try terminalCancellation(.regression)
        try terminalCancellation(.singleton)
        print("PASS G01 public resources")
    }
    static func full() throws {
        let intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()
        for swapped in [false, true] {
            print("START G01 query admitted full swapped=\(swapped)")
            let pair = input(swapped: swapped)
            var a = try freshExecution()
            let result = try intersector.intersectionResult(first: pair.0, second: pair.1,
                options: options, tolerance: .standard, using: &a)
            guard let reader = result.originalBoundedSphereConeRelation else {
                throw Failure(line: #line, detail: "unbounded public result lost its original relation")
            }
            let relation = reader.original
            try require(result.representation == .exactRelation && !reader.isEmpty
                && reader.hasPositiveDimensionalImage && reader.hasPositiveDimensionalSolutions
                && relation.halfAngleSupport != nil && relation.finiteArc == nil && relation.finiteCut == nil
                && relation.branchCount == 2 && relation.originalParameterDimension == 4
                && relation.imageDimension == 1 && relation.fiberDimension == 0,
                "unbounded publication lost its materialized half-angle support or two branches")
            try require(relation.source.original.original.first == pair.0
                && relation.source.original.original.second == pair.1
                && relation.source.original.sphereIsFirst == !swapped,
                "unbounded source owner/order changed")
            guard result.intersections.count == 1,
                case .originalBoundedSphereCone(let component) = result.intersections[0] else {
                throw Failure(line: #line, detail: "unbounded publication lost its original component")
            }
            try require(component.relation === relation && component.isClosed
                && component.firstSurface == pair.0 && component.secondSurface == pair.1,
                "unbounded component changed its source relation/order")
            let chart = try relation.source.chart(0, limits: readerLimits().source, using: &a)
            let f = relation.source.original.field
            let numerator = try f.integer(3, using: &a), denominator = try f.integer(4, using: &a)
            let t = try f.dividing(numerator, denominator, using: &a)
            let section = try relation.section(halfAngle: t, limits: readerLimits(), using: &a)
            let g = section.field, values = section.sourceValues
            try require(section.relation === relation && section.relation.source.owns(chart)
                && !section.isSharedEndpoint && !values.isDoubleRoot,
                "full section lost original source identity or distinct roots")
            try require(f.compare(section.sourceHalfAngle, t, using: &a) == .equal,
                "full section changed exact authored half-angle")
            try require(g.compare(section.plusSlant, section.minusSlant, using: &a) == .greater
                && g.compare(section.plusSlant, values.plusSlant, using: &a) == .equal
                && g.compare(section.minusSlant, values.minusSlant, using: &a) == .equal,
                "full section changed ordered source-owned slant roots")
            try require(a.budget.snapshot.work <= workLimit && a.budget.snapshot.storageBytes <= byteLimit,
                "unbounded query/section escaped the same caller budget")
            print("PASS G01 query admitted full swapped=\(swapped) work=\(a.budget.snapshot.work) bytes=\(a.budget.snapshot.storageBytes)")
        }
        print("PASS G01 public full")
    }
    static func run() throws {
        #if hasFeature(Embedded)
        let group = "all"
        #else
        let group = CommandLine.arguments.dropFirst().first ?? "all"
        #endif
        switch group {
        case "ordinary", "admitted", "prepared":
            guard let entry = Entry(rawValue: group) else { throw Failure(line: #line, detail: "unknown entry") }
            _ = try queries(entry)
        case "readers":
            var retained: [Retained] = []
            for swapped in [false, true] {
                retained.append(try check(query(.admitted, selection: .wide, swapped: swapped), selection: .wide, swapped: swapped))
            }
            try readers(retained)
        case "resources": try resources()
        case "full": try full()
        case "all":
            _ = try queries(.ordinary)
            let retained = try queries(.admitted)
            _ = try queries(.prepared)
            try readers(retained)
            try resources()
            try full()
            print("PASS G01 public all")
        default: throw Failure(line: #line, detail: "unknown group \(group)")
        }
    }
    static func axisName(_ axis: OriginalQueryResourceAxis) -> String {
        switch axis {
        case .sourceTextBytes: return "sourceTextBytes"
        case .combinedUnits: return "combinedUnits"
        case .work: return "work"
        case .storageBytes: return "storageBytes"
        case .sourceRecords: return "sourceRecords"
        case .valueDepth: return "valueDepth"
        case .coefficientDepth: return "coefficientDepth"
        case .sourceDepth: return "sourceDepth"
        case .transportDepth: return "transportDepth"
        case .cells: return "cells"
        case .charts: return "charts"
        case .families: return "families"
        case .identities: return "identities"
        case .results: return "results"
        case .spans: return "spans"
        case .polynomialDegree: return "polynomialDegree"
        case .extensionLevel: return "extensionLevel"
        case .closures: return "closures"
        case .attachments: return "attachments"
        case .geometricDepth: return "geometricDepth"
        case .scalarSlots: return "scalarSlots"
        case .countOverflow: return "countOverflow"
        }
    }
    static func countText(_ count: OriginalQueryResourceCount) -> String {
        switch count {
        case .known(let number): return String(number)
        case .unknown: return "unknown"
        case .unlimited: return "unlimited"
        }
    }
    static func entryName(_ entry: OriginalQueryFailureContext.Entry) -> String {
        switch entry {
        case .ordinary: return "ordinary"
        case .admitted: return "admitted"
        case .prepared: return "prepared"
        case .membership: return "membership"
        case .unspecified: return "unspecified"
        }
    }
    static func stageName(_ stage: OriginalQueryFailureContext.Stage) -> String {
        switch stage {
        case .request: return "request"
        case .source: return "source"
        case .domain: return "domain"
        case .relation: return "relation"
        case .refinement: return "refinement"
        case .publication: return "publication"
        case .membership: return "membership"
        case .unspecified: return "unspecified"
        }
    }
    static func diagnose(_ error: any Error) {
        if let failure = error as? Failure {
            print("FAIL G01 fixture line=\(failure.line) detail=\(failure.detail)")
        } else if let failure = error as? OriginalQueryFailure {
            print("FAIL G01 original code=\(failure.kernelFailure.code.rawValue) message=\(failure.kernelFailure.message)")
            print("FAIL G01 context entry=\(entryName(failure.context.entry)) stage=\(stageName(failure.context.stage))")
            if let observation = failure.context.resource {
                print("FAIL G01 resource axis=\(axisName(observation.axis)) used=\(countText(observation.used)) limit=\(countText(observation.limit)) requested=\(countText(observation.requested))")
            }
        } else if let failure = error as? KernelError {
            print("FAIL G01 kernel code=\(failure.code.rawValue) message=\(failure.message)")
        } else if let failure = error as? ExactScalarFailure, case .admissionRejected(let cause) = failure {
            diagnose(cause)
        } else {
            print("FAIL G01 other typed cause; original error rethrown unchanged")
        }
    }
    static func main() throws {
        do { try run() }
        catch { diagnose(error); throw error }
    }

}
