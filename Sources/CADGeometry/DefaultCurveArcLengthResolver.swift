import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

public struct DefaultCurveArcLengthResolver: CurveArcLengthResolving {
    private struct Cell: Sendable {
        let interval: ScalarInterval
        let lowerBound: Double
        let upperBound: Double
        let depth: Int
        let bezierPatch: RationalBezierCurvePatch3D?

        var gap: Double {
            upperBound - lowerBound
        }
    }

    private struct CellHeap {
        private var storage: [Cell] = []
        private var admittedCapacity = 0

        var count: Int {
            storage.count
        }

        var cells: [Cell] {
            storage
        }

        /// Transfers the existing paid cell buffer into native parameter order.
        mutating func orderedCells(consumeWork: (Int) throws -> Void) throws -> [Cell] {
            guard storage.count > 1 else { return storage }
            for root in stride(from: storage.count / 2 - 1, through: 0, by: -1) {
                try siftNative(root: root, end: storage.count, consumeWork: consumeWork)
            }
            for end in stride(from: storage.count - 1, through: 1, by: -1) {
                try consumeWork(max(storage[0].depth, storage[end].depth))
                storage.swapAt(0, end)
                try siftNative(root: 0, end: end, consumeWork: consumeWork)
            }
            return storage
        }

        private mutating func siftNative(root: Int, end: Int,
            consumeWork: (Int) throws -> Void) throws {
            var parent = root
            while true {
                let left = parent * 2 + 1
                guard left < end else { return }
                var child = left
                let right = left + 1
                if right < end {
                    try consumeWork(max(storage[left].depth, storage[right].depth))
                    if storage[right].interval.lower > storage[left].interval.lower { child = right }
                }
                try consumeWork(max(storage[parent].depth, storage[child].depth))
                guard storage[parent].interval.lower < storage[child].interval.lower else { return }
                storage.swapAt(parent, child)
                parent = child
            }
        }

        mutating func insert(_ cell: Cell, maximumCapacity: Int,
            consumeWork: () throws -> Void, reserveCells: ((Int) throws -> Void)?) throws {
            try consumeWork()
            if let reserveCells, storage.count == admittedCapacity {
                let doubled = admittedCapacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow, storage.count < maximumCapacity else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                        message: "Arc-length heap capacity exceeded original cell admission.")
                }
                let capacity = min(maximumCapacity, max(1, doubled.partialValue))
                try reserveCells(capacity)
                storage.reserveCapacity(capacity)
                admittedCapacity = capacity
            }
            storage.append(cell)
            var child = storage.count - 1
            while child > 0 {
                try consumeWork()
                let parent = (child - 1) / 2
                guard storage[child].gap > storage[parent].gap else { break }
                storage.swapAt(child, parent)
                child = parent
            }
        }

        mutating func removeMaximum(consumeWork: () throws -> Void) throws -> Cell? {
            try consumeWork()
            guard storage.isEmpty == false else { return nil }
            if storage.count == 1 {
                return storage.removeLast()
            }
            let result = storage[0]
            storage[0] = storage.removeLast()
            var parent = 0
            while true {
                try consumeWork()
                let left = parent * 2 + 1
                guard left < storage.count else { break }
                let right = left + 1
                let child = (
                    right < storage.count
                        && storage[right].gap > storage[left].gap
                ) ? right : left
                guard storage[child].gap > storage[parent].gap else { break }
                storage.swapAt(parent, child)
                parent = child
            }
            return result
        }
    }

    private struct PreparedParameterization: CurveArcLengthParameterization {
        let lengthEnclosure: CurveArcLengthEnclosure
        let curve: Curve3D
        let interval: ScalarInterval
        let absoluteAccuracy: Double
        let options: CurveArcLengthOptions
        let tolerance: ModelingTolerance
        let cells: [Cell]?
        let resolver: DefaultCurveArcLengthResolver

        func parameterBounds(atFraction requested: ScalarInterval,
            maximumParameterWidth: Double) throws -> ScalarInterval {
            let fraction = OutwardScalarInterval(lower: requested.lower, upper: requested.upper)
            try resolver.consume(0, tolerance: tolerance)
            guard resolver.originalPreparation != nil, let cells,
                  fraction.isFinite, fraction.lower >= 0, fraction.upper <= 1,
                  maximumParameterWidth.isFinite, maximumParameterWidth > 0 else {
                throw KernelError(phase: .geometry, code: .invalidInput,
                    tolerance: tolerance,
                    message: "Original inverse localization requires a paid partition, unit fraction interval and positive native width.")
            }
            if fraction.lower == 0, fraction.upper == 0 {
                return try ScalarInterval(lower: interval.lower, upper: interval.lower)
            }
            if fraction.lower == 1, fraction.upper == 1 {
                return try ScalarInterval(lower: interval.upper, upper: interval.upper)
            }
            return try resolver.inverseOriginalParameterBounds(fraction: fraction,
                maximumParameterWidth: maximumParameterWidth, curve: curve,
                initialCells: cells, options: options, tolerance: tolerance)
        }

        func hasSmoothNativeInterval(over requested: ScalarInterval) throws -> Bool {
            try resolver.consume(0, tolerance: tolerance)
            guard let prepared = resolver.originalPreparation,
                  let depth = resolver.callerMaximumDepth,
                  let spans = resolver.callerMaximumSpans, let work = resolver.callerWork,
                  requested.lower >= interval.lower, requested.upper <= interval.upper,
                  requested.width > 0 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original native smoothness requires a retained positive interval.")
            }
            if let mapped = try resolver.mappedChartSmoothness(prepared.curve,
                over: requested, depth: 0, tolerance: tolerance) { return mapped }
            guard try resolver.hasSmoothTaylorAuthority(prepared.curve, depth: 0,
                tolerance: tolerance) else { return false }
            let receipt = try prepared.closedNativeJets(over: requested, tolerance: tolerance,
                maximumSpanCount: spans, maximumSubdivisionDepth: depth,
                remainingSourceDepth: resolver.callerSourceDepth ?? depth, consumeWork: { try work(0) },
                consumeStorage: resolver.callerStorage)
            var owners = 0
            for span in receipt.spans {
                try resolver.consume(0, tolerance: tolerance)
                if span.parameters.width > 0 {
                    owners += 1
                    if owners > 1 { return false }
                }
            }
            return owners == 1
        }

        func differentialEnclosure(over requested: ScalarInterval) throws -> CurveDifferentialEnclosure {
            try resolver.consume(0, tolerance: tolerance)
            guard let prepared = resolver.originalPreparation,
                  let depth = resolver.callerMaximumDepth,
                  let spans = resolver.callerMaximumSpans,
                  let work = resolver.callerWork,
                  requested.lower >= interval.lower, requested.upper <= interval.upper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original differential reuse requires its retained bounded native domain.")
            }
            let receipt = try prepared.closedNativeJets(over: requested, tolerance: tolerance,
                maximumSpanCount: spans, maximumSubdivisionDepth: depth,
                remainingSourceDepth: resolver.callerSourceDepth ?? depth, consumeWork: { try work(0) },
                consumeStorage: resolver.callerStorage)
            guard let first = receipt.spans.first else {
                throw KernelError(phase: .geometry, code: .intersectionFailure,
                    tolerance: tolerance, message: "Original differential coverage is empty.")
            }
            var jet = first.jet
            for span in receipt.spans {
                try resolver.consume(0, tolerance: tolerance)
                jet = jet.union(span.jet)
            }
            func coordinate(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
                _ z: OutwardScalarInterval) throws -> CoordinateEnclosure3D {
                try resolver.consume(0, tolerance: tolerance)
                guard x.isFinite, y.isFinite, z.isFinite else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Original differential hull is not finite.")
                }
                return CoordinateEnclosure3D(x: try ScalarInterval(lower: x.lower, upper: x.upper),
                    y: try ScalarInterval(lower: y.lower, upper: y.upper),
                    z: try ScalarInterval(lower: z.lower, upper: z.upper))
            }
            return CurveDifferentialEnclosure(
                position: try coordinate(jet.x.value, jet.y.value, jet.z.value),
                firstDerivative: try coordinate(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU),
                secondDerivative: try coordinate(jet.x.secondDerivativeUU,
                    jet.y.secondDerivativeUU, jet.z.secondDerivativeUU))
        }

        func enclosure(over requested: ScalarInterval) throws -> CurveArcLengthEnclosure {
            try resolver.consume(0, tolerance: tolerance)
            guard resolver.originalPreparation != nil, let cells,
                  requested.lower >= interval.lower, requested.upper <= interval.upper else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Native subinterval lengths require the bounded original preparation domain.")
            }
            if requested.width == 0 { return try CurveArcLengthEnclosure(lowerBound: 0, upperBound: 0) }
            if requested.lower == interval.lower, requested.upper == interval.upper {
                return lengthEnclosure
            }
            var lower = 0.0, upper = 0.0
            for cell in cells {
                try resolver.consume(cell.depth, tolerance: tolerance)
                let lo = max(cell.interval.lower, requested.lower)
                let hi = min(cell.interval.upper, requested.upper)
                guard lo < hi else { continue }
                let part: CurveArcLengthEnclosure
                if lo == cell.interval.lower, hi == cell.interval.upper {
                    part = try CurveArcLengthEnclosure(lowerBound: cell.lowerBound,
                        upperBound: cell.upperBound)
                } else {
                    let boundaryOptions = CurveArcLengthOptions(absoluteAccuracy: absoluteAccuracy * 0.25,
                        relativeAccuracy: 0, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        maximumIntervalCount: options.maximumIntervalCount)
                    part = try resolver.certifiedPartition(curve: curve,
                        interval: ScalarInterval(lower: lo, upper: hi),
                        absoluteAccuracy: absoluteAccuracy * 0.25, options: boundaryOptions,
                        tolerance: tolerance, initialDepth: cell.depth).enclosure
                }
                lower = max(0, (lower + part.lowerBound).nextDown)
                upper = (upper + part.upperBound).nextUp
            }
            guard upper - lower <= max(absoluteAccuracy, options.relativeAccuracy * upper) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    residual: upper - lower, tolerance: tolerance,
                    message: "Retained arc-length cells cannot meet the native subinterval accuracy.")
            }
            return try CurveArcLengthEnclosure(lowerBound: lower, upperBound: upper)
        }

        func parameterEnclosure(
            atArcLengthFraction fraction: Double
        ) throws -> CurveArcLengthParameterEnclosure {
            guard fraction.isFinite,
                  fraction >= 0.0,
                  fraction <= 1.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: fraction,
                    tolerance: tolerance,
                    message: "Curve arc-length fraction must be finite and lie in the closed unit interval."
                )
            }
            if fraction == 0.0 {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: interval.lower,
                        upper: interval.lower
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            if fraction == 1.0 {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: interval.upper,
                        upper: interval.upper
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            guard let cells else {
                let parameter = interval.lower + interval.width * fraction
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: parameter,
                        upper: parameter
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            return try resolver.invertedParameterEnclosure(
                atArcLengthFraction: fraction,
                curve: curve,
                interval: interval,
                lengthEnclosure: lengthEnclosure,
                initialCells: cells,
                absoluteAccuracy: absoluteAccuracy,
                options: options,
                tolerance: tolerance
            )
        }
    }

    private let originalPreparation: PreparedCurveDifferentialEncloser?
    private let callerMaximumDepth: Int?
    private let callerSourceDepth: Int?
    private let callerMaximumAlgebraicDepth: Int?
    private let callerWork: (@Sendable (Int) throws -> Void)?
    private let callerMaximumSpans: Int?
    private let callerStorage: (@Sendable (Int) throws -> Void)?

    public init() {
        originalPreparation = nil
        callerMaximumDepth = nil
        callerSourceDepth = nil
        callerMaximumAlgebraicDepth = nil
        callerWork = nil
        callerMaximumSpans = nil
        callerStorage = nil
    }

    private init(prepared: PreparedCurveDifferentialEncloser, maximumDepth: Int, maximumSpans: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil) {
        originalPreparation = prepared
        callerMaximumDepth = maximumDepth
        callerSourceDepth = remainingSourceDepth
        callerMaximumAlgebraicDepth = maximumAlgebraicDepth
        callerWork = consumeWork
        callerMaximumSpans = maximumSpans
        callerStorage = consumeStorage
    }

    private func reserve(count: Int, stride: Int, depth: Int,
        tolerance: ModelingTolerance) throws {
        guard let callerStorage else { return }
        try consume(depth, tolerance: tolerance)
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original arc-length byte admission overflowed.")
        }
        try callerStorage(bytes.partialValue)
    }

    private func consume(_ depth: Int, tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        if let callerMaximumDepth, depth > callerMaximumDepth {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Arc length exhausted the caller's subdivision depth.")
        }
        try callerWork?(depth)
    }

    public func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> any CurveArcLengthParameterization {
        try boundedParameterization(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    public func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization {
        try boundedParameterization(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: nil)
    }

    public func parameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> any CurveArcLengthParameterization {
        try boundedParameterization(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func boundedParameterization(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil
    ) throws -> any CurveArcLengthParameterization {
        try consumeWork(0)
        let accuracy = try options.validatedAbsoluteAccuracy(tolerance: tolerance)
        guard maximumSubdivisionDepth >= 0, interval.width > 0,
              remainingSourceDepth.map({ $0 >= 0 }) ?? true,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Bounded arc-length preparation needs a positive original interval and caller depth.")
        }
        let depth = min(maximumSubdivisionDepth, options.maximumSubdivisionDepth)
        let sourceDepth = remainingSourceDepth ?? depth
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: sourceDepth, maximumSubdivisionDepth: depth,
            consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let invocation = Self(prepared: prepared, maximumDepth: depth,
            maximumSpans: options.maximumIntervalCount, consumeWork: consumeWork,
            consumeStorage: consumeStorage, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        try invocation.validateOriginalInterval(curve, interval: interval,
            remainingSourceDepth: sourceDepth, tolerance: tolerance)
        let tightened = CurveArcLengthOptions(absoluteAccuracy: accuracy * 0.5,
            relativeAccuracy: 0,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumIntervalCount: options.maximumIntervalCount)
        let partition = try invocation.certifiedPartition(curve: curve, interval: interval,
            absoluteAccuracy: accuracy * 0.5, options: tightened, tolerance: tolerance)
        return PreparedParameterization(lengthEnclosure: partition.enclosure, curve: curve,
            interval: interval, absoluteAccuracy: accuracy, options: options, tolerance: tolerance,
            cells: partition.cells, resolver: invocation)
    }

    public func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil
    ) throws -> CurveArcLengthEnclosure {
        try boundedEnclosure(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    public func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure {
        try boundedEnclosure(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: nil)
    }

    public func enclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void
    ) throws -> CurveArcLengthEnclosure {
        try boundedEnclosure(of: curve, over: interval, options: options,
            tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    private func boundedEnclosure(of curve: Curve3D, over interval: ScalarInterval,
        options: CurveArcLengthOptions, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil
    ) throws -> CurveArcLengthEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        try consumeWork(0)
        let accuracy = try options.validatedAbsoluteAccuracy(tolerance: tolerance)
        guard maximumSubdivisionDepth >= 0, interval.width > 0,
              remainingSourceDepth.map({ $0 >= 0 }) ?? true,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Bounded original arc length needs a positive interval and nonnegative caller depth.")
        }
        let depth = min(maximumSubdivisionDepth, options.maximumSubdivisionDepth)
        let sourceDepth = remainingSourceDepth ?? depth
        // Preparation validates the original source with this same allowance.
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve,
            tolerance: tolerance, remainingSourceDepth: sourceDepth, maximumSubdivisionDepth: depth,
            consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let invocation = Self(prepared: prepared, maximumDepth: depth,
            maximumSpans: options.maximumIntervalCount, consumeWork: consumeWork,
            consumeStorage: consumeStorage, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        try invocation.validateOriginalInterval(curve, interval: interval,
            remainingSourceDepth: sourceDepth, tolerance: tolerance)
        return try invocation.certifiedPartition(curve: curve, interval: interval,
            absoluteAccuracy: accuracy, options: options, tolerance: tolerance).enclosure
    }

    public func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try tolerance.validate()
        let absoluteAccuracy = try options.validatedAbsoluteAccuracy(
            tolerance: tolerance
        )
        try curve.validate(tolerance: tolerance)
        guard interval.width > 0.0,
              try curve.parameterDomain.containsSpan(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve arc-length evaluation requires a positive interval inside the curve domain."
            )
        }
        if originalPreparation == nil, let exactEnclosure = try constantSpeedEnclosure(
            of: curve,
            over: interval
        ) {
            return exactEnclosure
        }
        return try certifiedPartition(
            curve: curve,
            interval: interval,
            absoluteAccuracy: absoluteAccuracy,
            options: options,
            tolerance: tolerance
        ).enclosure
    }

    public func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        let prepared = try parameterization(
            of: curve,
            over: interval,
            options: options,
            tolerance: tolerance
        )
        return try prepared.parameterEnclosure(
            atArcLengthFraction: fraction
        )
    }

    public func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization {
        try tolerance.validate()
        let absoluteAccuracy = try options.validatedAbsoluteAccuracy(
            tolerance: tolerance
        )
        try curve.validate(tolerance: tolerance)
        guard interval.width > 0.0,
              try curve.parameterDomain.containsSpan(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve arc-length parameterization requires a positive interval inside the curve domain."
            )
        }
        if originalPreparation == nil, let constantEnclosure = try constantSpeedEnclosure(
            of: curve,
            over: interval
        ) {
            return PreparedParameterization(
                lengthEnclosure: constantEnclosure,
                curve: curve,
                interval: interval,
                absoluteAccuracy: absoluteAccuracy,
                options: options,
                tolerance: tolerance,
                cells: nil,
                resolver: self
            )
        }
        // Half of the spatial budget is reserved for uncertainty in the
        // total-length target; the remaining half is resolved locally by
        // the inverse search.
        let partitionAccuracy = absoluteAccuracy * 0.5
        let tightenedOptions = CurveArcLengthOptions(
            absoluteAccuracy: partitionAccuracy,
            relativeAccuracy: min(options.relativeAccuracy, 1.0e-12),
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumIntervalCount: options.maximumIntervalCount
        )
        let partitionResult = try certifiedPartition(
            curve: curve,
            interval: interval,
            absoluteAccuracy: partitionAccuracy,
            options: tightenedOptions,
            tolerance: tolerance
        )
        return PreparedParameterization(
            lengthEnclosure: partitionResult.enclosure,
            curve: curve,
            interval: interval,
            absoluteAccuracy: absoluteAccuracy,
            options: options,
            tolerance: tolerance,
            cells: partitionResult.cells,
            resolver: self
        )
    }

    private func invertedParameterEnclosure(
        atArcLengthFraction fraction: Double,
        curve: Curve3D,
        interval: ScalarInterval,
        lengthEnclosure total: CurveArcLengthEnclosure,
        initialCells: [Cell],
        absoluteAccuracy: Double,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        let target = OutwardScalarInterval.exact(fraction)
            * .init(lower: total.lowerBound, upper: total.upperBound)
        let targetLower = target.lower
        let targetUpper = target.upper
        var cells = initialCells
        var admittedCapacity = 0
        var splitCount = 0
        while true {
            try consume(0, tolerance: tolerance)
            let candidates = try candidateCellRange(
                cells: cells,
                targetLower: targetLower,
                targetUpper: targetUpper,
                tolerance: tolerance
            )
            guard let candidates,
                  let firstIndex = candidates.first,
                  let lastIndex = candidates.last else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion lost the target from its cumulative length enclosure."
                )
            }
            var spatialError = 0.0
            for cell in cells[firstIndex...lastIndex] {
                try consume(cell.depth, tolerance: tolerance)
                spatialError = (spatialError + cell.upperBound).nextUp
            }
            let parameterRange = try ScalarInterval(
                lower: cells[firstIndex].interval.lower,
                upper: cells[lastIndex].interval.upper
            )
            if spatialError <= absoluteAccuracy {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: parameterRange,
                    spatialErrorUpperBound: spatialError
                )
            }
            guard splitCount < options.maximumIntervalCount,
                  cells.count < options.maximumIntervalCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: spatialError,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion exceeded its interval budget before reaching the requested spatial error."
                )
            }
            let splitIndex = try (firstIndex...lastIndex).max {
                try consume(max(cells[$0].depth, cells[$1].depth), tolerance: tolerance)
                return cells[$0].upperBound < cells[$1].upperBound
            } ?? firstIndex
            let source = cells[splitIndex]
            guard source.depth < options.maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: spatialError,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion exceeded its subdivision depth."
                )
            }
            let halves = try split(
                source,
                curve: curve,
                tolerance: tolerance
            )
            try replaceRetainedCell(at: splitIndex, children: halves, cells: &cells,
                admittedCapacity: &admittedCapacity,
                maximumCapacity: options.maximumIntervalCount, tolerance: tolerance)
            splitCount += 1
        }
    }

    private func constantSpeedEnclosure(
        of curve: Curve3D,
        over interval: ScalarInterval
    ) throws -> CurveArcLengthEnclosure? {
        let parameterWidth = interval.width
        let speed: Double
        switch curve {
        case .line, .analytic(.line):
            speed = 1.0
        case let .circle(circle):
            speed = circle.radius
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            speed = radius
        case let .parameterImage(image):
            return try constantSpeedEnclosure(of: image.source, over: image.originalInterval(interval))
        case let .rigidImage(image):
            return try constantSpeedEnclosure(of: image.source, over: interval)
        case .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage, .originalAffineWord, .originalEndpointConnector,
             .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            return nil
        }
        let value = speed * parameterWidth
        return try CurveArcLengthEnclosure(
            lowerBound: max(0.0, value.nextDown),
            upperBound: value.nextUp
        )
    }

    private func inverseOriginalParameterBounds(fraction: OutwardScalarInterval,
        maximumParameterWidth: Double, curve: Curve3D, initialCells: [Cell],
        options: CurveArcLengthOptions, tolerance: ModelingTolerance) throws -> ScalarInterval {
        // This alias borrows the paid immutable partition until the first split.
        // Before COW or growth, reserve the complete destination capacity and pay
        // every original element copied; no preparation or allowance is restarted.
        var cells = initialCells
        var admittedCapacity = 0
        var iteration = 0
        while true {
            try consume(0, tolerance: tolerance)
            var lower = 0.0, upper = 0.0
            for cell in cells {
                try consume(cell.depth, tolerance: tolerance)
                lower = max(0, (lower + cell.lowerBound).nextDown)
                upper = (upper + cell.upperBound).nextUp
            }
            let total = OutwardScalarInterval(lower: lower, upper: upper)
            let target = total * fraction
            guard total.isFinite, upper > 0, target.isFinite,
                  let candidates = try candidateCellRange(cells: cells,
                    targetLower: target.lower, targetUpper: target.upper,
                    tolerance: tolerance) else {
                throw KernelError(phase: .geometry, code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Original inverse length localization lost its complete target cover.")
            }
            let bracket = try ScalarInterval(lower: cells[candidates.lowerBound].interval.lower,
                upper: cells[candidates.upperBound].interval.upper)
            if bracket.width <= maximumParameterWidth { return bracket }
            guard cells.count < options.maximumIntervalCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    residual: bracket.width, tolerance: tolerance,
                    message: "Original inverse length localization exhausted its retained cell policy.")
            }
            // Both cumulative-length uncertainty and local native width can
            // obstruct localization. Alternate their refinements; neither a
            // numerical prefix nor a guessed speed determines an exclusion.
            var selected: Int?
            var score = -Double.infinity
            for index in cells.indices {
                try consume(cells[index].depth, tolerance: tolerance)
                guard cells[index].depth < options.maximumSubdivisionDepth,
                      callerMaximumDepth.map({ cells[index].depth < $0 }) ?? true else { continue }
                if iteration.isMultiple(of: 2), !candidates.contains(index) { continue }
                let priority = iteration.isMultiple(of: 2)
                    ? cells[index].interval.width : cells[index].gap
                if priority > score { selected = index; score = priority }
            }
            guard let selected else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    residual: bracket.width, tolerance: tolerance,
                    message: "Original inverse length localization exhausted original cell depth.")
            }
            let source = cells[selected]
            let children = try split(source, curve: curve, tolerance: tolerance)
            try replaceRetainedCell(at: selected, children: children, cells: &cells,
                admittedCapacity: &admittedCapacity,
                maximumCapacity: options.maximumIntervalCount, tolerance: tolerance)
            iteration += 1
        }
    }

    private func replaceRetainedCell(at selected: Int, children: (lower: Cell, upper: Cell),
        cells: inout [Cell], admittedCapacity: inout Int, maximumCapacity: Int,
        tolerance: ModelingTolerance) throws {
        if cells.count == admittedCapacity || admittedCapacity == 0 {
            let doubled = cells.count.multipliedReportingOverflow(by: 2)
            let next = cells.count.addingReportingOverflow(1)
            guard !doubled.overflow, !next.overflow, next.partialValue <= maximumCapacity else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original inverse cell capacity overflowed.")
            }
            let capacity = min(maximumCapacity, max(next.partialValue, doubled.partialValue))
            try reserve(count: capacity, stride: MemoryLayout<Cell>.stride,
                depth: cells[selected].depth, tolerance: tolerance)
            for cell in cells { try consume(cell.depth, tolerance: tolerance) }
            cells.reserveCapacity(capacity)
            admittedCapacity = capacity
        }
        for index in selected..<cells.count { try consume(cells[index].depth, tolerance: tolerance) }
        cells[selected] = children.lower
        cells.insert(children.upper, at: selected + 1)
    }

    private func certifiedPartition(
        curve: Curve3D,
        interval: ScalarInterval,
        absoluteAccuracy: Double,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance,
        initialDepth: Int = 0
    ) throws -> (cells: [Cell], enclosure: CurveArcLengthEnclosure) {
        let initialCells = try initialCells(
            curve: curve,
            interval: interval,
            tolerance: tolerance,
            initialDepth: initialDepth
        )
        guard initialCells.isEmpty == false,
              initialCells.count <= options.maximumIntervalCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(initialCells.count),
                tolerance: tolerance,
                message: "Certified curve arc-length evaluation exceeded its initial interval budget."
            )
        }
        var lowerBound = 0.0
        var upperBound = 0.0
        var heap = CellHeap()
        for initial in initialCells {
            try consume(initial.depth, tolerance: tolerance)
            lowerBound = (lowerBound + initial.lowerBound).nextDown
            upperBound = (upperBound + initial.upperBound).nextUp
            try heap.insert(initial, maximumCapacity: options.maximumIntervalCount,
                consumeWork: { try consume(initial.depth, tolerance: tolerance) },
                reserveCells: callerStorage == nil ? nil : { count in
                    try reserve(count: count, stride: MemoryLayout<Cell>.stride,
                        depth: initial.depth, tolerance: tolerance)
                })
        }
        while upperBound - lowerBound > max(
            absoluteAccuracy,
            options.relativeAccuracy * upperBound
        ) {
            guard heap.count < options.maximumIntervalCount,
                  let source = try heap.removeMaximum(consumeWork: { try consume(0, tolerance: tolerance) }),
                  source.depth < options.maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: upperBound - lowerBound,
                    tolerance: tolerance,
                    message: "Certified curve arc-length evaluation exceeded its subdivision budget before reaching the requested enclosure width."
                )
            }
            let halves = try split(
                source,
                curve: curve,
                tolerance: tolerance
            )
            if originalPreparation != nil {
                lowerBound = (OutwardScalarInterval.exact(lowerBound)
                    + .exact(halves.lower.lowerBound) + .exact(halves.upper.lowerBound)
                    - .exact(source.lowerBound)).lower
                upperBound = (OutwardScalarInterval.exact(upperBound)
                    + .exact(halves.lower.upperBound) + .exact(halves.upper.upperBound)
                    - .exact(source.upperBound)).upper
            } else {
                lowerBound += halves.lower.lowerBound + halves.upper.lowerBound - source.lowerBound
                upperBound += halves.lower.upperBound + halves.upper.upperBound - source.upperBound
            }
            lowerBound = max(0.0, lowerBound.nextDown)
            upperBound = max(lowerBound, upperBound.nextUp)
            try heap.insert(halves.lower, maximumCapacity: options.maximumIntervalCount,
                consumeWork: { try consume(halves.lower.depth, tolerance: tolerance) },
                reserveCells: callerStorage == nil ? nil : { count in
                    try reserve(count: count, stride: MemoryLayout<Cell>.stride,
                        depth: halves.lower.depth, tolerance: tolerance)
                })
            try heap.insert(halves.upper, maximumCapacity: options.maximumIntervalCount,
                consumeWork: { try consume(halves.upper.depth, tolerance: tolerance) },
                reserveCells: callerStorage == nil ? nil : { count in
                    try reserve(count: count, stride: MemoryLayout<Cell>.stride,
                        depth: halves.upper.depth, tolerance: tolerance)
                })
        }
        // The immutable partition keeps this already-admitted heap backing.
        // In-place ordering avoids an unmetered standard-library sort scratch buffer.
        let ordered = try heap.orderedCells { try consume($0, tolerance: tolerance) }
        return (
            cells: ordered,
            enclosure: try CurveArcLengthEnclosure(
                lowerBound: lowerBound,
                upperBound: upperBound
            )
        )
    }

    private func split(
        _ source: Cell,
        curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> (lower: Cell, upper: Cell) {
        try consume(source.depth, tolerance: tolerance)
        if let patch = source.bezierPatch {
            let halves = try patch.subdivided(tolerance: tolerance)
            guard halves.count == 2 else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational Bezier arc-length subdivision must produce two child patches."
                )
            }
            return (
                try cell(
                    curve: curve,
                    interval: ScalarInterval(
                        lower: halves[0].lower,
                        upper: halves[0].upper
                    ),
                    depth: source.depth + 1,
                    bezierPatch: halves[0],
                    tolerance: tolerance
                ),
                try cell(
                    curve: curve,
                    interval: ScalarInterval(
                        lower: halves[1].lower,
                        upper: halves[1].upper
                    ),
                    depth: source.depth + 1,
                    bezierPatch: halves[1],
                    tolerance: tolerance
                )
            )
        }
        let middle = source.interval.midpoint
        return (
            try cell(
                curve: curve,
                interval: ScalarInterval(
                    lower: source.interval.lower,
                    upper: middle
                ),
                depth: source.depth + 1,
                bezierPatch: nil,
                tolerance: tolerance
            ),
            try cell(
                curve: curve,
                interval: ScalarInterval(
                    lower: middle,
                    upper: source.interval.upper
                ),
                depth: source.depth + 1,
                bezierPatch: nil,
                tolerance: tolerance
            )
        )
    }

    private func candidateCellRange(
        cells: [Cell],
        targetLower: Double,
        targetUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> ClosedRange<Int>? {
        var prefixLower = 0.0
        var prefixUpper = 0.0
        var first: Int?
        var last: Int?
        for index in cells.indices {
            try consume(cells[index].depth, tolerance: tolerance)
            let endLower = max(0, (prefixLower + cells[index].lowerBound).nextDown)
            let endUpper = (prefixUpper + cells[index].upperBound).nextUp
            if endUpper >= targetLower,
               prefixLower <= targetUpper {
                first = first ?? index
                last = index
            }
            prefixLower = endLower
            prefixUpper = endUpper
        }
        guard let first, let last else { return nil }
        return first...last
    }

    private func cell(
        curve: Curve3D,
        interval: ScalarInterval,
        depth: Int,
        bezierPatch: RationalBezierCurvePatch3D?,
        tolerance: ModelingTolerance
    ) throws -> Cell {
        if let originalPreparation {
            try reserve(count: 1, stride: MemoryLayout<Cell>.stride,
                depth: depth, tolerance: tolerance)
            return try originalCell(prepared: originalPreparation, interval: interval,
                depth: depth, tolerance: tolerance)
        }
        let start = try curve.point(
            at: interval.lower,
            tolerance: tolerance
        )
        let end = try curve.point(
            at: interval.upper,
            tolerance: tolerance
        )
        let chord = (end - start).length
        let arcLengthUpperBound: Double
        let speedLowerBound: Double
        let secondDerivativeMagnitudeUpperBound: Double
        let thirdDerivativeBound: Double?
        if let bezierPatch {
            let derivativeBound = try RationalBezierCurveDerivativeBound(
                coordinates: [
                    bezierPatch.controlPoints.map({ $0.x }),
                    bezierPatch.controlPoints.map({ $0.y }),
                    bezierPatch.controlPoints.map({ $0.z }),
                ],
                weights: bezierPatch.weights,
                parameterWidth: interval.width,
                tolerance: tolerance
            )
            secondDerivativeMagnitudeUpperBound = hypot(
                hypot(derivativeBound.second[0], derivativeBound.second[1]),
                derivativeBound.second[2]
            ).nextUp
            thirdDerivativeBound = hypot(
                hypot(derivativeBound.third[0], derivativeBound.third[1]),
                derivativeBound.third[2]
            ).nextUp
            let midpointDerivative: Vector3D
            if case let .bSpline(spline) = curve {
                midpointDerivative = try spline.parameterDerivatives(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            } else {
                midpointDerivative = try curve.differentialGeometry(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            }
            let derivativeRadius = (
                secondDerivativeMagnitudeUpperBound * interval.width * 0.5
            ).nextUp
            speedLowerBound = max(
                0.0,
                (midpointDerivative.length - derivativeRadius).nextDown
            )
            arcLengthUpperBound = (
                (midpointDerivative.length + derivativeRadius).nextUp
                    * interval.width
            ).nextUp
        } else {
            let bounds = try curve.tessellationIntervalBounds(
                interval,
                tolerance: tolerance
            )
            arcLengthUpperBound = bounds.arcLengthUpperBound
            speedLowerBound = bounds.speedLowerBound
            secondDerivativeMagnitudeUpperBound =
                bounds.secondDerivativeMagnitudeUpperBound
            thirdDerivativeBound = try thirdDerivativeMagnitudeUpperBound(
                curve: curve,
                interval: interval,
                tolerance: tolerance
            )
        }
        let floatingPointMargin = max(
            Double.ulpOfOne * max(chord, 1.0) * 64.0,
            chord.ulp * 8.0
        )
        var lowerBound = max(0.0, chord - floatingPointMargin)
        var upperBound = max(
            lowerBound,
            arcLengthUpperBound.nextUp
        )
        if speedLowerBound > 0.0,
           secondDerivativeMagnitudeUpperBound.isFinite,
           let thirdDerivativeBound {
            let midpointDerivative: Vector3D
            if case let .bSpline(spline) = curve {
                midpointDerivative = try spline.parameterDerivatives(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            } else {
                midpointDerivative = try curve.differentialGeometry(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            }
            let midpointEstimate = midpointDerivative.length * interval.width
            let speedSecondDerivativeBound = (
                secondDerivativeMagnitudeUpperBound
                    * secondDerivativeMagnitudeUpperBound
                    / speedLowerBound
                + thirdDerivativeBound
            ).nextUp
            let midpointError = (
                speedSecondDerivativeBound
                    * interval.width
                    * interval.width
                    * interval.width
                    / 24.0
            ).nextUp
            let midpointFloatingPointMargin = max(
                Double.ulpOfOne
                    * max(abs(midpointEstimate), abs(midpointError))
                    * 64.0,
                midpointEstimate.ulp * 8.0
            )
            lowerBound = max(
                lowerBound,
                midpointEstimate
                    - midpointError
                    - midpointFloatingPointMargin
            )
            upperBound = min(
                upperBound,
                midpointEstimate
                    + midpointError
                    + midpointFloatingPointMargin
            )
            upperBound = max(lowerBound, upperBound)
        }
        return Cell(
            interval: interval,
            lowerBound: lowerBound,
            upperBound: upperBound,
            depth: depth,
            bezierPatch: bezierPatch
        )
    }

    private func initialCells(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance,
        initialDepth: Int = 0
    ) throws -> [Cell] {
        if let originalPreparation {
            return [try originalCell(prepared: originalPreparation, interval: interval,
                depth: initialDepth, tolerance: tolerance)]
        }
        guard case let .bSpline(spline) = curve else {
            return [try cell(
                curve: curve,
                interval: interval,
                depth: 0,
                bezierPatch: nil,
                tolerance: tolerance
            )]
        }
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: spline,
            intersecting: interval,
            tolerance: tolerance
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline arc-length interval has no rational Bezier span."
            )
        }
        return try sourcePatches.compactMap { source -> Cell? in
            let lower = max(interval.lower, source.lower)
            let upper = min(interval.upper, source.upper)
            guard upper > lower else { return nil }
            let patch = lower == source.lower && upper == source.upper
                ? source
                : try source.trimmed(
                    from: lower,
                    to: upper,
                    tolerance: tolerance
                )
            return try cell(
                curve: curve,
                interval: ScalarInterval(lower: lower, upper: upper),
                depth: 0,
                bezierPatch: patch,
                tolerance: tolerance
            )
        }
    }

    private func validateOriginalInterval(_ curve: Curve3D, interval: ScalarInterval,
        remainingSourceDepth: Int, tolerance: ModelingTolerance) throws {
        try consume(0, tolerance: tolerance)
        func descend(_ source: Curve3D, _ range: ScalarInterval) throws {
            guard remainingSourceDepth > 0 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Arc-length domain admission exhausted source depth.")
            }
            try validateOriginalInterval(source, interval: range,
                remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance)
        }
        switch curve {
        case .parameterImage(let image):
            try descend(image.source, image.originalInterval(interval,
                consumeWork: { try consume(0, tolerance: tolerance) }))
        case .rigidImage(let image): try descend(image.source, interval)
        case .affineImage(let image): try descend(image.source, interval)
        case .originalAffineWord(let image): try descend(image.source, interval)
        default:
            guard try curve.parameterDomain.containsSpan(from: interval.lower,
                to: interval.upper, tolerance: tolerance) else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Bounded original arc length exceeds the authored curve domain.")
            }
        }
    }

    /// nil leaves the ordinary native-owner proof in charge of this family.
    private func mappedChartSmoothness(_ curve: Curve3D, over interval: ScalarInterval,
        depth: Int, tolerance: ModelingTolerance, sourceDepth: Int? = nil) throws -> Bool? {
        try consume(depth, tolerance: tolerance)
        guard let maximumDepth = callerMaximumDepth, let maximumSpans = callerMaximumSpans,
              let work = callerWork, depth <= maximumDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original chart smoothness exhausted its retained invocation depth.")
        }
        let selectedSource = sourceDepth ?? callerSourceDepth
        func descend(_ source: Curve3D, over range: ScalarInterval) throws -> Bool? {
            if let selectedSource {
                guard selectedSource > 0 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Original arc chart recursion exhausted its selected source depth.")
                }
                return try mappedChartSmoothness(source, over: range, depth: depth,
                    tolerance: tolerance, sourceDepth: selectedSource - 1)
            }
            return try mappedChartSmoothness(source, over: range, depth: depth + 1, tolerance: tolerance)
        }
        switch curve {
        case .originalGuideTraversalChain(let chain):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Arc/Sweep delegates exact local
            // station-map smoothness to the chain issuer. Unknown original joins
            // and unavailable stricter nonnative algebra transport remain lower
            // gaps; neither synthetic owners nor a hull authorize their success.
            return try chain.hasSmoothNativeInterval(over: interval, tolerance: tolerance,
                maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
                remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
                consumeWork: { try work(depth) }, consumeStorage: callerStorage,
                maximumAlgebraicDepth: callerMaximumAlgebraicDepth)
        case .originalPolyline(let polyline):
            return try polyline.hasSmoothNativeInterval(over: interval, tolerance: tolerance,
                maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
                remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
                consumeWork: { try work(depth) }, consumeStorage: callerStorage,
                maximumAlgebraicDepth: callerMaximumAlgebraicDepth)
        case .originalGuideEndpointConnector(let corrected):
            return try corrected.hasSmoothNativeInterval(over: interval, tolerance: tolerance,
                maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
                remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
                consumeWork: { try work(depth) }, consumeStorage: callerStorage,
                maximumAlgebraicDepth: callerMaximumAlgebraicDepth)
        case .originalConstructionChart(let image):
            return try image.hasSmoothNativeInterval(over: interval, tolerance: tolerance,
                maximumSpanCount: maximumSpans, maximumSubdivisionDepth: maximumDepth - depth,
                remainingSourceDepth: selectedSource ?? (maximumDepth - depth),
                consumeWork: { try work(depth) }, consumeStorage: callerStorage,
                maximumAlgebraicDepth: callerMaximumAlgebraicDepth)
        case .rigidImage(let image):
            return try descend(image.source, over: interval)
        case .affineImage(let image):
            return try descend(image.source, over: interval)
        case .originalAffineWord(let image):
            return try descend(image.source, over: interval)
        case .parameterImage(let image):
            let native = try image.originalInterval(interval, consumeWork: { try work(depth) })
            return try descend(image.source, over: native)
        default: return nil
        }
    }

    private func hasSmoothTaylorAuthority(_ curve: Curve3D, depth: Int,
        tolerance: ModelingTolerance, sourceDepth: Int? = nil) throws -> Bool {
        try consume(depth, tolerance: tolerance)
        let selectedSource = sourceDepth ?? callerSourceDepth
        func descend(_ source: Curve3D) throws -> Bool {
            if let selectedSource {
                guard selectedSource > 0 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Arc Taylor family traversal exhausted selected source depth.")
                }
                return try hasSmoothTaylorAuthority(source, depth: depth, tolerance: tolerance,
                    sourceDepth: selectedSource - 1)
            }
            return try hasSmoothTaylorAuthority(source, depth: depth, tolerance: tolerance)
        }
        switch curve {
        case .line, .circle, .bSpline:
            // Native spline tightening also requires exactly one positive-width owner.
            return true
        case .analytic(.line), .analytic(.circle), .analytic(.arc),
             .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola):
            return true
        case .parameterImage(let image):
            return try descend(image.source)
        case .rigidImage(let image):
            return try descend(image.source)
        case .affineImage(let image):
            return try descend(image.source)
        case .originalAffineWord(let image):
            return try descend(image.source)
        case .originalConstructionChart:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Unknown lifted/implicit owning
            // joins remain outside Arc/Sweep smoothness authority. Construction
            // charts delegate to mappedChartSmoothness before this family selector;
            // a synthetic hull alone never proves a smooth original join.
            return false
        case .originalAngularTransport:
            // Its admitted direct conic phase law is smooth on each original
            // interval. Actual prepared jets and one positive owner still prove
            // speed and Taylor bounds; no binary-pi or scalar shortcut applies.
            return true
        case .originalEndpointConnector:
            // Its exact polynomial correction preserves each smooth construction
            // owner. The corrected original jet, and exactly one positive-width
            // owner, still establish all speed and Taylor quantities below.
            return true
        case .surfaceLift(let lift):
            switch lift.parameterCurve {
            case .constantU, .constantV, .affine, .harmonic: break
            default: return false
            }
            switch lift.surface {
            case .plane, .cylinder,
                 .analytic(.plane), .analytic(.cylinder), .analytic(.sphere),
                 .analytic(.cone), .analytic(.torus): return true
            default: return false
            }
        default:
            // A union jet does not establish smoothness across a lifted source join.
            return false
        }
    }

    private func originalCell(prepared: PreparedCurveDifferentialEncloser,
        interval: ScalarInterval, depth: Int, tolerance: ModelingTolerance) throws -> Cell {
        try consume(depth, tolerance: tolerance)
        guard let callerMaximumDepth, let callerWork, let callerMaximumSpans else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original arc-length cells require their invocation allowance.")
        }
        let remaining = callerMaximumDepth - depth
        let nested: () throws -> Void = { try callerWork(depth) }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The byte-admitted arc route forwards
        // actual native jet scratch/result bytes alongside owned integration buffers.
        // Supported implicit owning-cell bytes now use the original lower port.
        // General family temporary admission and cross-owner smoothness still
        // need their actual producers; no aggregate hull closes those source gaps.
        let receipt = try prepared.closedNativeJets(over: interval, tolerance: tolerance,
            maximumSpanCount: callerMaximumSpans, maximumSubdivisionDepth: remaining,
            remainingSourceDepth: callerSourceDepth ?? remaining, consumeWork: nested, consumeStorage: callerStorage)
        func magnitude(_ x: OutwardScalarInterval, _ y: OutwardScalarInterval,
            _ z: OutwardScalarInterval) -> OutwardScalarInterval {
            let vector = IntervalVector3DBounds(x: x, y: y, z: z)
            return OutwardScalarInterval(lower: vector.lengthLowerBound,
                upper: vector.lengthUpperBound)
        }
        var speedLower = Double.infinity, speedUpper = 0.0
        var second = 0.0, third = 0.0, owningCount = 0
        for span in receipt.spans {
            try consume(depth, tolerance: tolerance)
            let jet = span.jet
            let speed = magnitude(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU)
            speedLower = min(speedLower, speed.lower)
            speedUpper = max(speedUpper, speed.upper)
            second = max(second, magnitude(jet.x.secondDerivativeUU,
                jet.y.secondDerivativeUU, jet.z.secondDerivativeUU).upper)
            third = max(third, magnitude(jet.x.thirdDerivativeUUU,
                jet.y.thirdDerivativeUUU, jet.z.thirdDerivativeUUU).upper)
            if span.parameters.width > 0 { owningCount += 1 }
        }
        let width = OutwardScalarInterval.exact(interval.upper) - .exact(interval.lower)
        var length = OutwardScalarInterval(lower: speedLower, upper: speedUpper) * width
        // A whole-cell Taylor estimate is valid only within one smooth native owner.
        let smooth: Bool
        if let mapped = try mappedChartSmoothness(prepared.curve, over: interval,
            depth: depth, tolerance: tolerance) {
            smooth = mapped
        } else {
            if owningCount == 1 {
                smooth = try hasSmoothTaylorAuthority(prepared.curve, depth: depth, tolerance: tolerance)
            } else { smooth = false }
        }
        if smooth, speedLower > 0, second.isFinite, third.isFinite {
            let middle = OutwardScalarInterval.exact(interval.lower) + width * .exact(0.5)
            let singleton = try prepared.closedNativeJets(
                over: ScalarInterval(lower: middle.lower, upper: middle.upper), tolerance: tolerance,
                maximumSpanCount: callerMaximumSpans, maximumSubdivisionDepth: remaining,
                remainingSourceDepth: callerSourceDepth ?? remaining, consumeWork: nested, consumeStorage: callerStorage)
            var middleLower = Double.infinity, middleUpper = 0.0
            for span in singleton.spans {
                try consume(depth, tolerance: tolerance)
                let jet = span.jet
                let value = magnitude(jet.x.derivativeU, jet.y.derivativeU, jet.z.derivativeU)
                middleLower = min(middleLower, value.lower)
                middleUpper = max(middleUpper, value.upper)
            }
            guard let acceleration = (OutwardScalarInterval.exact(second) * .exact(second))
                .divided(by: .exact(speedLower)) else {
                throw KernelError(phase: .geometry, code: .intersectionFailure,
                    tolerance: tolerance, message: "Original arc-length speed lower bound is singular.")
            }
            let curvature = acceleration + .exact(third)
            let error = (curvature * width * width * width)
                .divided(by: .exact(24))
            if let error, error.isFinite {
                let estimate = OutwardScalarInterval(lower: middleLower, upper: middleUpper) * width
                let taylor = OutwardScalarInterval(lower: (estimate.lower - error.upper).nextDown,
                    upper: (estimate.upper + error.upper).nextUp)
                if let tighter = length.intersection(with: taylor) { length = tighter }
                else {
                    throw KernelError(phase: .geometry, code: .intersectionFailure,
                        tolerance: tolerance, message: "Original arc-length bounds disagree.")
                }
            }
        }
        guard length.isFinite, length.upper >= 0 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original arc-length cell bounds are nonfinite.")
        }
        return Cell(interval: interval, lowerBound: max(0, length.lower),
            upperBound: max(0, length.upper), depth: depth, bezierPatch: nil)
    }

    private func thirdDerivativeMagnitudeUpperBound(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        switch curve {
        case let .parameterImage(image):
            guard let source = try thirdDerivativeMagnitudeUpperBound(curve: image.source,
                interval: image.originalInterval(interval), tolerance: tolerance) else { return nil }
            let scale = abs(image.gain)
            return (source * scale * scale * scale).nextUp

        case .line, .analytic(.line), .analytic(.parabola):
            return 0.0
        case let .circle(circle):
            return circle.radius.nextUp
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            return radius.nextUp
        case let .analytic(.ellipse(_, _, _, majorRadius, minorRadius)):
            return max(majorRadius, minorRadius).nextUp
        case let .analytic(.hyperbola(hyperbola)):
            let parameter = max(abs(interval.lower), abs(interval.upper))
            let value = hypot(
                hyperbola.transverseRadius * sinh(parameter),
                hyperbola.conjugateRadius * cosh(parameter)
            )
            return value.isFinite ? value.nextUp : nil
        case let .analytic(.planeTorus(curve)):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromParameter: interval.lower,
                toParameter: interval.upper,
                tolerance: tolerance
            ).third
        case let .bSpline(spline):
            let patches = try BSplineCurveBezierDecomposer().curvePatches(
                curve: spline,
                intersecting: interval,
                tolerance: tolerance
            )
            guard patches.isEmpty == false else { return nil }
            var result = 0.0
            for source in patches {
                let lower = max(interval.lower, source.lower)
                let upper = min(interval.upper, source.upper)
                guard upper > lower else { continue }
                let patch = lower == source.lower && upper == source.upper
                    ? source
                    : try source.trimmed(
                        from: lower,
                        to: upper,
                        tolerance: tolerance
                    )
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map({ $0.x }),
                        patch.controlPoints.map({ $0.y }),
                        patch.controlPoints.map({ $0.z }),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                result = max(
                    result,
                    hypot(
                        hypot(bound.third[0], bound.third[1]),
                        bound.third[2]
                    ).nextUp
                )
            }
            return result
        case let .rigidImage(image):
            return try thirdDerivativeMagnitudeUpperBound(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            )
        case let .affineImage(image):
            guard let sourceBound = try thirdDerivativeMagnitudeUpperBound(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            ) else {
                return nil
            }
            let transformedBound = (
                sourceBound * image.transform.linearMagnitudeUpperBound
            ).nextUp
            return transformedBound.isFinite ? transformedBound : nil
        case .implicit, .surfaceLift, .certifiedIntersection, .originalAffineWord,
             .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            // A flat original affine word has no legacy scalar derivative bound.
            // Its original first-jet enclosure supplies the integral bound instead.
            return nil
        }
    }
}
