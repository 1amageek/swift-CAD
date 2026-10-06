import CADCore
import CADGeometry

/// Partitions original indexed parameter triangles at retained native knot planes.
struct TrimmedNativePartition: Sendable {
    struct Triangle: Sendable {
        let first: Int
        let second: Int
        let third: Int
    }
    struct Result: Sendable {
        let parameters: [SurfaceParameter]
        let triangles: [Triangle]
        let owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
    }
    private struct Cut: Hashable { let axis: Int; let coordinate: Double }
    private struct Crossing: Hashable { let first: Int; let second: Int; let cut: Cut }

    func partition(parameters input: [SurfaceParameter], triangles original: [Triangle],
        spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan],
        budget: TessellationProofBudget, tolerance: ModelingTolerance) throws -> Result {
        var parameters = input
        var triangles = original
        var cuts = Set<Cut>()
        for span in spans {
            try budget.charge()
            cuts.insert(Cut(axis: 0, coordinate: span.uBounds.lower))
            cuts.insert(Cut(axis: 0, coordinate: span.uBounds.upper))
            cuts.insert(Cut(axis: 1, coordinate: span.vBounds.lower))
            cuts.insert(Cut(axis: 1, coordinate: span.vBounds.upper))
        }
        let orderedCuts = cuts.sorted {
            $0.axis == $1.axis ? $0.coordinate < $1.coordinate : $0.axis < $1.axis
        }
        var crossings: [Crossing: Int] = [:]
        func coordinate(_ index: Int, _ axis: Int) -> Double {
            axis == 0 ? parameters[index].u : parameters[index].v
        }
        func crossing(_ first: Int, _ second: Int, _ cut: Cut) throws -> Int {
            let a = coordinate(first, cut.axis), b = coordinate(second, cut.axis)
            if a == cut.coordinate { return first }
            if b == cut.coordinate { return second }
            let key = Crossing(first: min(first, second), second: max(first, second), cut: cut)
            if let retained = crossings[key] { return retained }
            try budget.charge()
            let low = parameters[key.first], high = parameters[key.second]
            let lowAxis = coordinate(key.first, cut.axis), highAxis = coordinate(key.second, cut.axis)
            let fraction = (cut.coordinate - lowAxis) / (highAxis - lowAxis)
            guard fraction.isFinite, fraction > 0, fraction < 1, parameters.count < 262_144 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original native trim partition requires a finite interior station within its existing storage ceiling.")
            }
            let other = cut.axis == 0 ? low.v + (high.v-low.v)*fraction : low.u + (high.u-low.u)*fraction
            guard other.isFinite else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original native trim partition exceeded finite station arithmetic.")
            }
            let value = cut.axis == 0 ? SurfaceParameter(u: cut.coordinate, v: other)
                : SurfaceParameter(u: other, v: cut.coordinate)
            let index = parameters.count
            parameters.append(value)
            crossings[key] = index
            return index
        }
        func nonzero(_ a: Int, _ b: Int, _ c: Int) throws -> Bool {
            let first = parameters[a], second = parameters[b], third = parameters[c]
            return try RobustPredicates.orientation2D(
                Point2D(x: second.u, y: second.v), Point2D(x: third.u, y: third.v),
                relativeTo: Point2D(x: first.u, y: first.v), determinantTolerance: 0,
                consumeWork: { try budget.charge() },
                consumeStorage: { try budget.chargeStorageBytes($0) }) != .zero
        }
        for cut in orderedCuts {
            try Task.checkCancellation()
            var next: [Triangle] = []
            for triangle in triangles {
                try budget.charge()
                let polygon = [triangle.first, triangle.second, triangle.third]
                let values = polygon.map { coordinate($0, cut.axis) }
                guard values.contains(where: { $0 < cut.coordinate }),
                    values.contains(where: { $0 > cut.coordinate }) else {
                    next.append(triangle); continue
                }
                for upper in [false, true] {
                    var clipped: [Int] = []
                    for index in polygon.indices {
                        let a = polygon[index], b = polygon[(index+1)%polygon.count]
                        let firstInside = upper ? coordinate(a,cut.axis) >= cut.coordinate : coordinate(a,cut.axis) <= cut.coordinate
                        let secondInside = upper ? coordinate(b,cut.axis) >= cut.coordinate : coordinate(b,cut.axis) <= cut.coordinate
                        if firstInside { clipped.append(a) }
                        if firstInside != secondInside { clipped.append(try crossing(a,b,cut)) }
                    }
                    var unique: [Int] = []
                    for index in clipped where unique.last != index { unique.append(index) }
                    if unique.count > 1, unique.first == unique.last { unique.removeLast() }
                    if unique.count >= 3 {
                        for index in 1..<(unique.count-1) where try nonzero(unique[0],unique[index],unique[index+1]) {
                            guard next.count < 262_144 else {
                                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                                    tolerance: tolerance, message: "Original native trim partition exceeded its existing triangle ceiling.")
                            }
                            next.append(Triangle(first: unique[0], second: unique[index], third: unique[index+1]))
                        }
                    }
                }
            }
            triangles = next
        }
        var owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
        for triangle in triangles {
            try budget.charge()
            let vertices = [parameters[triangle.first], parameters[triangle.second], parameters[triangle.third]]
            let lowerU = vertices.map(\.u).min()!, upperU = vertices.map(\.u).max()!
            let lowerV = vertices.map(\.v).min()!, upperV = vertices.map(\.v).max()!
            var owner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan?
            for span in spans {
                try budget.charge()
                if span.uBounds.lower <= lowerU, span.uBounds.upper >= upperU,
                    span.vBounds.lower <= lowerV, span.vBounds.upper >= upperV {
                    guard owner == nil else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                            message: "A nonzero original trim triangle requires one native owning side.")
                    }
                    owner = span
                }
            }
            guard let owner else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Original trim partition did not cover a retained triangle with one native owning side.")
            }
            owners.append(owner)
        }
        return Result(parameters: parameters, triangles: triangles, owners: owners)
    }
}
