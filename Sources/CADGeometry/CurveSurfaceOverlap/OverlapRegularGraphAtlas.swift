import CADCore

/// Differential authority for an original, closed native target chart box.
enum OverlapRegularGraphAtlas: Sendable, Equatable {
    enum Axis: Sendable, Equatable { case u, v }
    case smooth
    case collar(axis: Axis, knot: Double)

    var isSmooth: Bool {
        if case .smooth = self { return true }
        return false
    }

    static func authority(over box: SurfaceParameterBox, surface: BSplineSurface3D,
                          tolerance: ModelingTolerance, budget: inout OverlapProofBudget) throws -> Self {
        var result = Self.smooth
        for (axis, knots, degree, interval) in [(Axis.u, surface.uKnots, surface.uDegree, box.u),
                                              (Axis.v, surface.vKnots, surface.vDegree, box.v)] {
            try budget.work(knots.count)
            var index = degree + 1
            while index < knots.count - degree - 1 {
                let value = knots[index]
                var end = index + 1
                while end < knots.count, knots[end] == value { end += 1 }
                if value >= interval.lower, value <= interval.upper {
                    let continuity = degree - (end - index)
                    // FIXME(INCOMPLETE_IMPLEMENTATION): multiple low-continuity knots
                    // and tensor corners have no complete atlas
                    // authority in intersectionResult. They must fail until all owning
                    // branches, derivative capabilities and joins are certified.
                    if continuity < 2 {
                        guard (continuity == 0 || continuity == 1), result.isSmooth else {
                            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                                message: "The regular graph atlas admits only one original C0 or C1 target knot per closed chart box.")
                        }
                        result = .collar(axis: axis, knot: value)
                    }
                }
                index = end
            }
        }
        return result
    }
}
