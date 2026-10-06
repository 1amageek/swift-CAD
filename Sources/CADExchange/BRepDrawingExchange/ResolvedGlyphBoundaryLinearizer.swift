import CADCore
import CADGeometry
import CADKernel

/// Bounded paper-point proposals retain each original algebraic root span.
struct ResolvedGlyphBoundaryLinearizer {
    func linearize(_ boundary: OriginalPlanarNonzeroBoundary, maximumDeviation: Double,
                   resources: SharedExchangeResourceAccountant) throws -> [[Point2D]] {
        guard maximumDeviation.isFinite, maximumDeviation > 0 else {
            throw ExportError.invalidMesh("Resolved glyph requires an explicit paper-point deviation.")
        }
        func jet(_ span: OriginalCurveRootSpan3D, _ a: Double, _ b: Double) throws -> SurfaceIntervalVectorJet {
            try resources.checkTime()
            return try span.preparedIntervalJet(over: .init(lower: min(a,b), upper: max(a,b)),
                tolerance: span.certificationTolerance, consumeWork: { try resources.recordIterations() },
                consumeStorage: { try resources.recordBytes($0) },
                maximumSpanCount: resources.limits.maximumEntities,
                maximumSubdivisionDepth: resources.limits.maximumCurveSubdivisionDepth,
                remainingSourceDepth: resources.limits.maximumNesting)
        }
        func point(_ enclosure: SurfaceIntervalVectorJet) throws -> Point2D {
            guard enclosure.x.value.isFinite, enclosure.y.value.isFinite,
                  enclosure.z.value.lower <= 0, enclosure.z.value.upper >= 0 else {
                throw ExportError.invalidMesh("Resolved glyph original point enclosure is not a finite paper-plane point.")
            }
            return .init(x: enclosure.x.value.midpoint, y: enclosure.y.value.midpoint)
        }
        func error(_ enclosure: SurfaceIntervalVectorJet, _ point: Point2D) -> Double {
            IntervalVector3DBounds(x: enclosure.x.value - .exact(point.x),
                y: enclosure.y.value - .exact(point.y), z: .exact(0)).lengthUpperBound
        }
        try resources.recordEntities(boundary.loops.count)
        try resources.recordBytes(boundary.loops.count * MemoryLayout<[Point2D]>.stride)
        var result: [[Point2D]] = []
        for loop in boundary.loops {
            guard !loop.uses.isEmpty else { throw ExportError.invalidMesh("Resolved glyph boundary contains an empty loop.") }
            try resources.recordEntities(loop.uses.count)
            try resources.recordBytes(loop.uses.count * MemoryLayout<Point2D>.stride)
            var joins: [Point2D] = []
            for index in loop.uses.indices {
                try resources.recordIterations()
                let previous = loop.uses[(index + loop.uses.count - 1) % loop.uses.count]
                let next = loop.uses[index]
                let last = try jet(previous.forward ? previous.span : previous.span.reversed(), 1, 1)
                let first = try jet(next.forward ? next.span : next.span.reversed(), 0, 0)
                guard let x = last.x.value.intersection(with: first.x.value),
                      let y = last.y.value.intersection(with: first.y.value) else {
                    throw ExportError.invalidMesh("Resolved glyph exact-event endpoint enclosures disagree.")
                }
                joins.append(.init(x: x.midpoint, y: y.midpoint))
            }
            try resources.recordEntities(); try resources.recordBytes(MemoryLayout<Point2D>.stride)
            var points = [joins[0]]
            for index in loop.uses.indices {
                let use = loop.uses[index], span = use.forward ? use.span : use.span.reversed()
                let first = joins[index], last = joins[(index + 1) % joins.count]
                try resources.recordEntities(); try resources.recordBytes(MemoryLayout<(Double, Double, Point2D, Point2D, Int)>.stride)
                var pending = [(0.0, 1.0, first, last, 0)]
                while let (a, b, pa, pb, depth) = pending.popLast() {
                    try resources.recordIterations(); try resources.checkTime()
                    let whole = try jet(span, a, b)
                    let ea = error(try jet(span, a, a), pa), eb = error(try jet(span, b, b), pb)
                    let second = IntervalVector3DBounds(x: whole.x.secondDerivativeUU,
                        y: whole.y.secondDerivativeUU, z: .exact(0)).lengthUpperBound
                    let width = OutwardScalarInterval.exact(b) - .exact(a)
                    let bound = OutwardScalarInterval.exact(second) * width * width / .exact(8) + .exact(max(ea,eb))
                    guard second.isFinite, ea.isFinite, eb.isFinite, bound.isFinite else {
                        throw ExportError.invalidMesh("Resolved glyph chord error cannot be bounded.")
                    }
                    let minimumPublicationDepth = loop.uses.count == 1 ? 2 : loop.uses.count == 2 ? 1 : 0
                    if bound.upper <= maximumDeviation, pa != pb, depth >= minimumPublicationDepth {
                        try resources.recordEntities(); try resources.recordBytes(MemoryLayout<Point2D>.stride)
                        points.append(pb)
                    } else {
                        guard depth < resources.limits.maximumCurveSubdivisionDepth else {
                            throw ExportError.invalidMesh("Resolved glyph chord exceeds the caller subdivision/deviation allowance.")
                        }
                        let middle = a * 0.5 + b * 0.5
                        guard middle > a, middle < b else { throw ExportError.invalidMesh("Resolved glyph parameter resolution is exhausted.") }
                        let pm = try point(jet(span, middle, middle))
                        try resources.recordEntities(2)
                        try resources.recordBytes(2 * MemoryLayout<(Double, Double, Point2D, Point2D, Int)>.stride)
                        pending.append((middle,b,pm,pb,depth+1)); pending.append((a,middle,pa,pm,depth+1))
                    }
                }
            }
            guard points.first == points.last else { throw ExportError.invalidMesh("Resolved glyph publication lost its exact-event closure.") }
            result.append(points)
        }
        return result
    }
}
