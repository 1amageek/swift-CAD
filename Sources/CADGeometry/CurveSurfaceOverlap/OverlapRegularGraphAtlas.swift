import CADCore

/// Differential authority for an original, closed native target chart box.
enum OverlapRegularGraphAtlas: Sendable, Equatable {
    struct AxisKnots: Sendable, Equatable {
        let first: Double
        let last: Double
        let count: Int
    }

    case smooth
    case collar(u: AxisKnots?, v: AxisKnots?)

    var isSmooth: Bool {
        if case .smooth = self { return true }
        return false
    }

    static func authority(over box: SurfaceParameterBox, surface: BSplineSurface3D,
                          tolerance: ModelingTolerance, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Self {
        var u: AxisKnots?, v: AxisKnots?
        for (isU, knots, degree, interval) in [(true, surface.uKnots, surface.uDegree, box.u),
                                             (false, surface.vKnots, surface.vDegree, box.v)] {
            try policy.work(knots.count, using: &execution)
            var summary: AxisKnots?
            var index = degree + 1
            while index < knots.count - degree - 1 {
                let value = knots[index]
                var end = index + 1
                while end < knots.count, knots[end] == value { end += 1 }
                if value >= interval.lower, value <= interval.upper {
                    let continuity = degree - (end - index)
                    if continuity < 2 {
                        guard continuity == 0 || continuity == 1 else {
                            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                message: "An original knot does not provide C0 or C1 collar continuity.")
                        }
                        // Complete knots remain owned by the original surface.
                        // Only fixed-size transverse-axis metadata is retained.
                        summary = AxisKnots(first: summary?.first ?? value, last: value,
                            count: (summary?.count ?? 0) + 1)
                    }
                }
                index = end
            }
            if isU { u = summary } else { v = summary }
        }
        return u == nil && v == nil ? .smooth : .collar(u: u, v: v)
    }
}
