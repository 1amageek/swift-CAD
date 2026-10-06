import CADCore
import CADGeometry

/// Convex distance to a chord bounds every point in the original position rectangle.
enum DrawingChordBoxBound {
    static func upperBound(_ box: CoordinateEnclosure3D, from first: Point2D, to last: Point2D,
        usage: inout DrawingExchangeUsage) throws -> Double {
        guard box.x.lower.isFinite, box.x.upper.isFinite, box.y.lower.isFinite, box.y.upper.isFinite else {
            throw ExportError.invalidMesh("Original drawing position enclosure is nonfinite.")
        }
        var bound = 0.0
        let dx = last.x - first.x, dy = last.y - first.y
        let norm = dx * dx + dy * dy
        for column in 0..<2 {
            let x = column == 0 ? box.x.lower : box.x.upper
            for row in 0..<2 {
                let y = row == 0 ? box.y.lower : box.y.upper
                try usage.charge(work: 1)
                let candidate = norm.isFinite && norm > 0 ? ((x-first.x)*dx + (y-first.y)*dy) / norm : 0
                let t = candidate.isFinite ? min(1, max(0, candidate)) : 0
                // t proposes one actual chord station. Outward arithmetic retains
                // its full binary law; it does not assert an exact nearest station.
                let qx = OutwardScalarInterval.exact(first.x) + (.exact(last.x)-.exact(first.x)) * .exact(t)
                let qy = OutwardScalarInterval.exact(first.y) + (.exact(last.y)-.exact(first.y)) * .exact(t)
                let distance = IntervalVector3DBounds(x: .exact(x)-qx, y: .exact(y)-qy, z: .exact(0)).lengthUpperBound
                guard distance.isFinite else { throw ExportError.invalidMesh("Original drawing chord distance is not finite.") }
                bound = max(bound, distance)
            }
        }
        return bound
    }
}
