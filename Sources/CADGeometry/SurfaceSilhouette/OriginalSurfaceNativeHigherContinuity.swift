import CADCore

/// Requested-order exact source partial equality on every selected native edge.
struct OriginalSurfaceNativeHigherContinuity {
    struct Usage: RationalAlgebraAdmitting {
        let consume: () throws -> Void
        let maximumDepth: Int
        let maximumAlgebraicDepth: Int
        let consumeStorage: ((Int) throws -> Void)?
        init(consume: @escaping () throws -> Void, maximumDepth: Int,
            consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int = 32) {
            self.consume = consume; self.maximumDepth = maximumDepth; self.consumeStorage = consumeStorage
            self.maximumAlgebraicDepth = maximumAlgebraicDepth
        }
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw rationalAlgebraFailure("Original higher join work count is negative.") }
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consume() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else { throw rationalAlgebraFailure("Original higher join storage bytes overflow.") }
            try consumeStorage?(bytes.partialValue)
            try consumeExactWork(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth else {
                throw rationalAlgebraFailure("Original higher join exceeded the supplied proof depth.")
            }
            try consumeExactWork(1)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumAlgebraicDepth else {
                throw rationalAlgebraFailure("Original higher source exceeded the independent coefficient depth.")
            }
            try consumeExactWork(1)
        }
    }
    private struct Edge: Hashable {
        let alongU: Bool
        let station: Double
        let transverse: ScalarInterval
    }

    static func prove(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, throughOrder: Int, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int = 32) throws {
        try proveOriginal(source: source, spans: spans, over: query, throughOrder: throughOrder,
            requiredPartials: nil, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    static func prove(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, requiredPartials: [(uOrder: Int, vOrder: Int)],
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int = 32) throws {
        guard !requiredPartials.isEmpty else { throw rationalAlgebraFailure("Original continuity needs explicitly requested partials.") }
        var order = 0
        for required in requiredPartials {
            try consumeWork()
            let total = try rationalAlgebraCount(required.uOrder, required.vOrder)
            order = max(order, total)
        }
        try proveOriginal(source: source, spans: spans, over: query, throughOrder: order,
            requiredPartials: requiredPartials, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    private static func proveOriginal(source: BSplineSurface3D,
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        over query: SurfaceParameterBox, throughOrder: Int,
        requiredPartials: [(uOrder: Int, vOrder: Int)]?, maximumSubdivisionDepth: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws {
        guard (0...32).contains(maximumAlgebraicDepth) else {
            throw rationalAlgebraFailure("Original join coefficient depth exceeds the intrinsic caller policy.")
        }
        try withoutActuallyEscaping(consumeWork) { borrowed in
            var usage = Usage(consume: borrowed, maximumDepth: maximumSubdivisionDepth,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            var edges: [Edge: [Int]] = [:]
            var laws: [Int: OriginalRationalSurfaceDerivativeLaw] = [:]
            func law(_ index: Int, usage: inout Usage) throws -> OriginalRationalSurfaceDerivativeLaw {
                if let retained = laws[index] { return retained }
                let span = spans[index]
                let local = try SurfaceParameterBox(
                    u: ScalarInterval(lower: max(query.u.lower, span.uBounds.lower), upper: min(query.u.upper, span.uBounds.upper)),
                    v: ScalarInterval(lower: max(query.v.lower, span.vBounds.lower), upper: min(query.v.upper, span.vBounds.upper)))
                let original = try OriginalRationalSurfacePolynomial(source: source, native: span,
                    domain: local, view: .zero, tolerance: tolerance, usage: &usage)
                let retained = try OriginalRationalSurfaceDerivativeLaw(original: original,
                    throughOrder: throughOrder, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: (Int, OriginalRationalSurfaceDerivativeLaw).self, usage: &usage)
                laws[index] = retained
                return retained
            }
            for index in spans.indices {
                let span = spans[index]
                for axis in 0..<2 {
                    let alongU = axis == 0
                    let bounds = alongU ? span.uBounds : span.vBounds
                    let transverse = alongU ? span.vBounds : span.uBounds
                    let range = alongU ? query.u : query.v
                    for side in 0..<2 {
                        let station = side == 0 ? bounds.lower : bounds.upper
                        guard station >= range.lower, station <= range.upper else { continue }
                        let edge = Edge(alongU: alongU, station: station, transverse: transverse)
                        for other in edges[edge, default: []] {
                            try usage.consumeExactWork(1)
                            let previous = spans[other]
                            if previous.uSpanIndex == span.uSpanIndex, previous.vSpanIndex == span.vSpanIndex,
                                previous.uCycle == span.uCycle, previous.vCycle == span.vCycle { continue }
                            let first = try law(other, usage: &usage), second = try law(index, usage: &usage)
                            let differences = try first.equalityNumerators(with: second, requiredPartials: requiredPartials, usage: &usage)
                            let exactStation = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
                            let transverseQuery = alongU ? query.v : query.u
                            let lo = max(transverse.lower, transverseQuery.lower), hi = min(transverse.upper, transverseQuery.upper)
                            for difference in differences {
                                let restriction = try difference.restricted(alongU: alongU, station: exactStation, usage: &usage)
                                let equal: Bool
                                if lo == hi {
                                    equal = try restriction.evaluated(atU: .originalDouble(lo, usage: &usage), v: .zero, usage: &usage).isZero
                                } else { equal = restriction.isZero }
                                guard equal else {
                                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                                        message: "Original requested surface partial is discontinuous at this selected native join.")
                                }
                            }
                        }
                        if edges[edge] == nil {
                            try RationalAlgebraStorage.retain(1, of: (Edge, [Int]).self, usage: &usage)
                        }
                        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                        edges[edge, default: []].append(index)
                    }
                }
            }
        }
    }
}
