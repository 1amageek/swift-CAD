import CADCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Independent original rail denominators and their common one-sided U partition.
struct SurfaceAreaNativeRuledPartition: Sendable {
    let surface: Surface3D
    let hasNativeJoins: Bool
    private let original: RuledSurface3D
    private let first: PreparedCurveDifferentialEncloser
    private let second: PreparedCurveDifferentialEncloser
    private let domains: [ScalarInterval]
    private let preparationTolerance: ModelingTolerance
    private let originalMaximumSubdivisionDepth: Int?
    private let originalRemainingSourceDepth: Int
    private let originalMaximumAlgebraicDepth: Int?

    init(original: RuledSurface3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, maximumSubdivisionDepth: Int? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int? = nil,
        consumeStorage: ((Int) throws -> Void)? = nil) throws {
        if let maximumSubdivisionDepth {
            try Surface3D.procedural(.ruled(original)).validateOriginalSource(tolerance:tolerance,
                remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
                consumeWork:{ _ in try consumeWork() },consumeStorage:consumeStorage,
                maximumAlgebraicDepth:maximumAlgebraicDepth)
        } else { try original.validate(tolerance: tolerance) }
        originalMaximumSubdivisionDepth = maximumSubdivisionDepth
        originalRemainingSourceDepth = remainingSourceDepth
        originalMaximumAlgebraicDepth = maximumAlgebraicDepth
        guard case let .closed(lower, upper) = original.uDomain else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled integration requires its finite U domain.")
        }
        self.original = original
        surface = .procedural(.ruled(original))
        preparationTolerance = tolerance
        try consumeStorage?(2 * MemoryLayout<Double>.stride)
        var breaks = [lower, upper]
        try Self.appendNativeBreaks(original.startBoundary, lower: lower, upper: upper,
            to: &breaks, tolerance: tolerance, consumeWork: consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        try Self.appendNativeBreaks(original.endBoundary, lower: lower, upper: upper,
            to: &breaks, tolerance: tolerance, consumeWork: consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        try breaks.sort { try consumeWork(); return $0 < $1 }
        try consumeStorage?(try Self.requestedBytes(breaks.count, MemoryLayout<ScalarInterval>.stride))
        var pieces: [ScalarInterval] = []
        pieces.reserveCapacity(breaks.count)
        for index in 1..<breaks.count where breaks[index - 1] < breaks[index] {
            try consumeWork()
            pieces.append(try ScalarInterval(lower: breaks[index - 1], upper: breaks[index]))
        }
        domains = pieces
        hasNativeJoins = pieces.count > 1
        func prepareRail(_ curve: Curve3D) throws -> PreparedCurveDifferentialEncloser {
            if let maximumSubdivisionDepth {
                return try PreparedCurveDifferentialEncloser(curve:curve,tolerance:tolerance,
                    remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,
                    consumeWork:consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
            }
            return try PreparedCurveDifferentialEncloser(curve:curve,tolerance:tolerance,consumeWork:consumeWork)
        }
        first = try prepareRail(original.startBoundary)
        second = try prepareRail(original.endBoundary)
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max,
        consumeWork: (Int) throws -> Void = { _ in try CurrentTaskCancellationChecker().checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()

        try validate(tolerance)
        guard hasNativeJoins else { return nil }
        try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self,consumeStorage:consumeStorage)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(domains.count)
        for (index, range) in domains.enumerated() {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            let a = max(range.lower, box.u.lower), b = min(range.upper, box.u.upper)
            guard a < b else { continue }
            guard result.count < maximumCount else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original ruled native domains exceed the shared cell budget.")
            }
            try consumeWork(0)
            result.append(.init(rectangle: SurfaceParameterBox(u: try ScalarInterval(lower: a, upper: b), v: box.v),
                radialRange: nil, index: index, source: surface, curve: nil, anchor: nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
        maximumCount: Int, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max,
        consumeWork: (Int) throws -> Void = { _ in try CurrentTaskCancellationChecker().checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()

        try validate(tolerance)
        guard hasNativeJoins, case .constantU(let end, let v0, let v1) = curve,
              min(anchor.v, v0, v1) >= 0, max(anchor.v, v0, v1) <= 1 else { return nil }
        let delta = end - anchor.u
        guard delta.isFinite, delta != 0 else { return nil }
        func cut(_ knot: Double) throws -> Double? {
            try consumeWork(0)
            let result = (knot - anchor.u) / delta
            guard result.isFinite else { return nil }
            return try SurfaceAreaTranslationCertificate.linearImageIsExactlyRepresented(origin:anchor.u,
                first:end,second:anchor.u,fraction:result,value:knot,maximumAlgebraicDepth:originalMaximumAlgebraicDepth,
                consumeWork:{ try consumeWork(0) },consumeStorage:consumeStorage) ? result : nil
        }
        try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self,consumeStorage:consumeStorage)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(domains.count)
        for (index, range) in domains.enumerated() {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            guard let a = try cut(range.lower), let b = try cut(range.upper) else { return nil }
            let lo = max(0, min(a, b)), hi = min(1, max(a, b))
            guard lo < hi else { continue }
            guard result.count < maximumCount else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original ruled fans exceed the shared cell budget.")
            }
            try consumeWork(0)
            result.append(.init(rectangle: SurfaceParameterBox(u: range, v: try ScalarInterval(lower: 0, upper: 1)),
                radialRange: try ScalarInterval(lower: lo, upper: hi), index: index,
                source: surface, curve: curve, anchor: anchor))
        }
        try result.sort { try consumeWork(0); return ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              try result.indices.dropFirst().allSatisfy({ try consumeWork(0); return result[$0 - 1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    func forEachJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil,
        _ consume: (SurfaceIntervalVectorJet, Int) throws -> Void) throws {
        try validate(tolerance)
        if let domain {
            guard domain.source == surface, domains.indices.contains(domain.index),
                  box.u.lower >= domain.rectangle.u.lower, box.u.upper <= domain.rectangle.u.upper else {
                throw Self.failure(.invalidInput, tolerance, "Original ruled ownership belongs to another domain or surface.")
            }
        }
        var found = false
        for (index, range) in domains.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            if let domain, domain.index != index { continue }
            let a = max(box.u.lower, range.lower), b = min(box.u.upper, range.upper)
            guard a <= b else { continue }
            if box.u.lower < box.u.upper, a == b { continue }
            let u = try ScalarInterval(lower: a, upper: b)
            func owning(_ prepared: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
                let receipt: PreparedCurveDifferentialEncloser.ClosedNativeJet
                if let depth = originalMaximumSubdivisionDepth {
                    receipt = try prepared.closedNativeJets(over:u,tolerance:tolerance,maximumSpanCount:262_144,
                        maximumSubdivisionDepth:depth,remainingSourceDepth:originalRemainingSourceDepth,
                        consumeWork:consumeWork,consumeStorage:consumeStorage)
                } else { receipt = try prepared.closedNativeJets(over:u,tolerance:tolerance,consumeWork:consumeWork) }
                var result: SurfaceIntervalVectorJet?
                for piece in receipt.spans {
                    try consumeWork()
                    if a < b, (piece.parameters.lower == piece.parameters.upper) { continue }
                    result = result.map { $0.union(piece.jet) } ?? piece.jet
                }
                guard let result else {
                    throw Self.failure(.classificationFailure, tolerance, "Original ruled rail lost its complete native range.")
                }
                return result
            }
            let aJet = try owning(first), bJet = try owning(second)
            // Each original scalar field composition is one visited fixed
            // third-order algebra node. These value structs retain no growing
            // scratch buffer; nominal slot fees cannot establish allocation.
            let v = SurfaceIntervalJet.parameterV(box.v)
            func coordinate(_ a: SurfaceIntervalJet, _ b: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
                try consumeWork()
                return a + (b + (-a)) * v
            }
            let jet = try SurfaceIntervalVectorJet(x:coordinate(aJet.x,bJet.x),
                y:coordinate(aJet.y,bJet.y),z:coordinate(aJet.z,bJet.z))
            let smooth = domain != nil || (box.u.lower >= range.lower && box.u.upper <= range.upper)
            try consume(jet, smooth ? 3 : 0)
            found = true
        }
        guard found else { throw Self.failure(.classificationFailure, tolerance, "Original ruled query has no native U coverage.") }
    }

    private static func requestedBytes(_ count: Int, _ stride: Int) throws -> Int {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original rail buffer byte count overflowed.")
        }
        return bytes.partialValue
    }

    private static func appendNativeBreaks(_ curve: Curve3D, lower: Double, upper: Double,
        to result: inout [Double], tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
        try consumeWork()
        switch curve {
        case .rigidImage(let image):
            try appendNativeBreaks(image.source, lower: lower, upper: upper, to: &result,
                tolerance: tolerance, consumeWork: consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        case .affineImage(let image):
            try appendNativeBreaks(image.source, lower: lower, upper: upper, to: &result,
                tolerance: tolerance, consumeWork: consumeWork,consumeStorage:consumeStorage,maximumAlgebraicDepth:maximumAlgebraicDepth)
        case .bSpline(let spline):
            let period = spline.knots[spline.controlPointCount] - spline.knots[spline.degree]
            for index in spline.degree...spline.controlPointCount {
                try consumeWork()
                let knot = spline.knots[index]
                if !spline.isPeriodic {
                    if knot > lower, knot < upper { try consumeWork(); try consumeStorage?(try requestedBytes(result.count+1,MemoryLayout<Double>.stride)); result.reserveCapacity(result.count+1); result.append(knot) }
                    continue
                }
                let first = ceil((lower - knot) / period), last = floor((upper - knot) / period)
                guard first.isFinite, last.isFinite, abs(first) <= 9_007_199_254_740_990,
                      abs(last) <= 9_007_199_254_740_990 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Original ruled cyclic knot lifts exceed finite resolution.")
                }
                var cycle = first
                while cycle <= last {
                    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
                    let value = knot + cycle * period
                    guard value.isFinite, try SurfaceAreaTranslationCertificate.linearImageIsExactlyRepresented(
                        origin:knot,first:spline.knots[spline.controlPointCount],second:spline.knots[spline.degree],fraction:cycle,value:value,
                        maximumAlgebraicDepth:maximumAlgebraicDepth,consumeWork:consumeWork,consumeStorage:consumeStorage) else {
                        throw failure(.resourceLimitExceeded,tolerance,"An original periodic rail join has no exact represented lift.")
                    }
                    if value > lower, value < upper { try consumeWork(); try consumeStorage?(try requestedBytes(result.count+1,MemoryLayout<Double>.stride)); result.reserveCapacity(result.count+1); result.append(value) }
                    cycle += 1
                }
            }
        default: break
        }
    }

    private func validate(_ tolerance: ModelingTolerance) throws {
        guard tolerance == preparationTolerance else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled partition requires its exact preparation tolerance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
        _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
