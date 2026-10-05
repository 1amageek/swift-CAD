import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Plans only original nonperiodic, nonclamped rectangles; emission belongs to the module.
struct RectangularBSplineMesh {
    struct Grid {
        let uBounds: (lower: Double, upper: Double)
        let vBounds: (lower: Double, upper: Double)
        let steps: (u: Int, v: Int)
        let owningSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    }

    let tolerance: ModelingTolerance

    func requiresNativePanels(_ surface: BSplineSurface3D) throws -> Bool {
        try surface.validate(tolerance: tolerance)
        try Task.checkCancellation()
        func isClamped(_ knots: [Double], degree: Int, count: Int) -> Bool {
            let lower = knots[degree], upper = knots[count]
            return knots.prefix(degree + 1).allSatisfy { $0 == lower }
                && knots.suffix(degree + 1).allSatisfy { $0 == upper }
        }
        guard case .closed = surface.uDomain, case .closed = surface.vDomain else { return false }
        return !isClamped(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount)
            || !isClamped(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount)
    }

    func grids(for loop: Loop, surface: BSplineSurface3D,
               model: BRepModel, options: TessellationOptions) throws -> [Grid] {
        func continuous(_ knots: [Double], degree: Int, count: Int) -> Bool {
            let lower = knots[degree], upper = knots[count]
            var index = degree + 1
            while index < count {
                var end = index + 1
                while end < count, knots[end] == knots[index] { end += 1 }
                if knots[index] > lower, knots[index] < upper, end - index > degree { return false }
                index = end
            }
            return true
        }
        guard try requiresNativePanels(surface),
              continuous(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
              continuous(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount),
              surface.weights.allSatisfy({ $0.allSatisfy { $0 > 0 } }) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original nonclamped rectangle tessellation requires positive weights and at least C0 native continuity.")
        }
        let rectangle = try originalBSplineRectangleBounds(for: loop, on: surface, in: model)
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: surface, over: SurfaceParameterBox(
                u: ScalarInterval(lower: rectangle.u.lower, upper: rectangle.u.upper),
                v: ScalarInterval(lower: rectangle.v.lower, upper: rectangle.v.upper)), tolerance: tolerance)
        var uCounts: [Int: Int] = [:], vCounts: [Int: Int] = [:]
        for (index, panel) in panels.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            let counts = try certifiedBSplineGridStepCounts(bounds: panel.bounds,
                uBounds: (panel.parameters.u.lower, panel.parameters.u.upper),
                vBounds: (panel.parameters.v.lower, panel.parameters.v.upper), options: options)
            uCounts[panel.span.uSpanIndex] = max(uCounts[panel.span.uSpanIndex] ?? 1, counts.u)
            vCounts[panel.span.vSpanIndex] = max(vCounts[panel.span.vSpanIndex] ?? 1, counts.v)
        }
        var grids: [Grid] = []
        for (index, panel) in panels.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            guard let uSteps = uCounts[panel.span.uSpanIndex],
                  let vSteps = vCounts[panel.span.vSpanIndex] else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Native panel tessellation did not retain every compatible axis count.")
            }
            let u = (lower: panel.parameters.u.lower, upper: panel.parameters.u.upper)
            let v = (lower: panel.parameters.v.lower, upper: panel.parameters.v.upper)
            let checked = try certifiedBSplineGridStepCounts(bounds: panel.bounds,
                uBounds: u, vBounds: v, options: options, minimumSteps: (uSteps, vSteps))
            guard checked.u == uSteps, checked.v == vSteps else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Native panel tessellation could not certify its compatible retained stations.")
            }
            grids.append(Grid(uBounds: u, vBounds: v, steps: (uSteps, vSteps), owningSpan: panel.span))
        }
        guard !grids.isEmpty else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original rectangle tessellation retained no native panel.")
        }
        return grids
    }

    private func certifiedBSplineGridStepCounts(
        bounds: SurfaceTessellationDifferentialBounds,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        minimumSteps: (u: Int, v: Int) = (1, 1)
    ) throws -> (u: Int, v: Int) {
        let maximumStepCount = 65_536
        var uSteps = minimumSteps.u, vSteps = minimumSteps.v

        func product(_ lhs: Double, _ rhs: Double) -> Double {
            lhs == 0 || rhs == 0 ? 0 : (lhs * rhs).nextUp
        }
        func sum(_ lhs: Double, _ rhs: Double) -> Double {
            lhs == 0 && rhs == 0 ? 0 : (lhs + rhs).nextUp
        }
        // Use the same representable stations emission evaluates. A rounded uniform chart
        // interval may be wider than span/count; its actual largest gap owns the proof width.
        func maximumStep(_ bounds: (lower: Double, upper: Double), count: Int) throws -> Double {
            var previous = bounds.lower
            var maximum = 0.0
            for index in 1...count {
                if index & 0xFF == 0 { try Task.checkCancellation() }
                let next = Self.station(lowerBound: bounds.lower, upperBound: bounds.upper, index: index, count: count)
                guard next > previous else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "B-spline tessellation exhausted representable grid stations.")
                }
                maximum = max(maximum, (next - previous).nextUp)
                previous = next
            }
            return maximum
        }
        while true {
            try Task.checkCancellation()
            let du = try maximumStep(uBounds, count: uSteps)
            let dv = try maximumStep(vBounds, count: vSteps)
            let uu = product(bounds.secondDerivativeUUMagnitudeUpperBound, product(du, du))
            let uv = product(bounds.secondDerivativeUVMagnitudeUpperBound, product(du, dv))
            let vv = product(bounds.secondDerivativeVVMagnitudeUpperBound, product(dv, dv))
            let linear = sum(sum(uu, product(2, uv)), vv)
            let normalU = product(bounds.unitNormalDerivativeUMagnitudeUpperBound, du)
            let normalV = product(bounds.unitNormalDerivativeVMagnitudeUpperBound, dv)
            let angular = sum(normalU, normalV)
            let edgeU = product(bounds.tangentUMagnitudeUpperBound, du)
            let edgeV = product(bounds.tangentVMagnitudeUpperBound, dv)
            // The path along the two chart axes bounds every diagonal as well as both sides.
            let edge = sum(edgeU, edgeV)
            if linear <= options.linearTolerance, angular <= options.angularTolerance,
               options.maxEdgeLength.map({ edge <= $0 }) ?? true {
                return (uSteps, vSteps)
            }
            guard uSteps < maximumStepCount || vSteps < maximumStepCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "B-spline tessellation exceeded its certified grid budget.")
            }
            // Compare only the active normalized errors. An unconstrained axis length must not
            // redirect refinement away from the curvature or normal condition that is failing.
            var uNeed = (uu + uv) / options.linearTolerance + normalU / options.angularTolerance
            var vNeed = (vv + uv) / options.linearTolerance + normalV / options.angularTolerance
            if let maximumEdgeLength = options.maxEdgeLength {
                uNeed += edgeU / maximumEdgeLength
                vNeed += edgeV / maximumEdgeLength
            }
            if (uNeed >= vNeed && uSteps < maximumStepCount) || vSteps == maximumStepCount {
                uSteps = min(maximumStepCount, uSteps * 2)
            } else {
                vSteps = min(maximumStepCount, vSteps * 2)
            }
        }
    }

    private func originalBSplineRectangleBounds(
        for loop: Loop, on surface: BSplineSurface3D, in model: BRepModel
    ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double)) {
        func refusal() -> KernelError {
            KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "B-spline tessellation requires four connected original monotone rectangle sides within its native domain.")
        }
        struct Side {
            let axis: RectangularParameterAxis
            var start: SurfaceParameter
            var end: SurfaceParameter

            var increasing: Bool {
                axis == .u ? end.v > start.v : end.u > start.u
            }
        }
        guard loop.coedges.count >= 4 else {
            throw refusal()
        }
        var sides: [Side] = []
        var firstParameter: SurfaceParameter?
        var previousParameter: SurfaceParameter?
        var firstVertexID: VertexID?
        var previousVertexID: VertexID?
        for (index, coedge) in loop.coedges.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            guard let curve = coedge.surfaceParameterCurve,
                  let edge = model.edges[coedge.edgeID] else { throw refusal() }
            let axis: RectangularParameterAxis
            let start: SurfaceParameter
            let end: SurfaceParameter
            // The stored source endpoints own rectangle closure. Fraction interpolation
            // can round its last station away from the represented end of the pcurve.
            switch curve {
            case let .constantU(u, vStart, vEnd):
                axis = .u
                start = SurfaceParameter(u: u, v: vStart)
                end = SurfaceParameter(u: u, v: vEnd)
            case let .constantV(v, uStart, uEnd):
                axis = .v
                start = SurfaceParameter(u: uStart, v: v)
                end = SurfaceParameter(u: uEnd, v: v)
            default:
                throw refusal()
            }
            let startID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            let endID = coedge.orientation == .forward ? edge.endVertexID : edge.startVertexID
            guard [start.u, start.v, end.u, end.v].allSatisfy(\.isFinite),
                  (axis == .u ? start.u == end.u && start.v != end.v
                    : start.v == end.v && start.u != end.u) else { throw refusal() }
            if let previousParameter, let previousVertexID {
                guard previousParameter == start, previousVertexID == startID else { throw refusal() }
            } else {
                firstParameter = start
                firstVertexID = startID
            }
            let side = Side(axis: axis, start: start, end: end)
            if let previous = sides.last, previous.axis == axis {
                guard previous.increasing == side.increasing else { throw refusal() }
                sides[sides.count - 1].end = end
            } else {
                sides.append(side)
                // A loop may start inside a side, making at most five runs before
                // its first and last runs join. Further turns cannot be a rectangle.
                guard sides.count <= 5 else { throw refusal() }
            }
            previousParameter = end
            previousVertexID = endID
        }
        guard previousParameter == firstParameter, previousVertexID == firstVertexID else { throw refusal() }
        if let first = sides.first, let last = sides.last, first.axis == last.axis {
            guard first.increasing == last.increasing else { throw refusal() }
            sides[0].start = last.start
            sides.removeLast()
        }
        guard sides.count == 4, let first = sides.first else { throw refusal() }
        var minU = first.start.u, maxU = minU, minV = first.start.v, maxV = minV
        for side in sides {
            minU = min(minU, side.start.u, side.end.u)
            maxU = max(maxU, side.start.u, side.end.u)
            minV = min(minV, side.start.v, side.end.v)
            maxV = max(maxV, side.start.v, side.end.v)
        }
        guard maxU > minU, maxV > minV else { throw refusal() }
        for index in sides.indices {
            let side = sides[index]
            guard side.axis != sides[(index + 1) % 4].axis else { throw refusal() }
            switch side.axis {
            case .u:
                guard side.start.u == minU || side.start.u == maxU,
                      min(side.start.v, side.end.v) == minV,
                      max(side.start.v, side.end.v) == maxV else { throw refusal() }
            case .v:
                guard side.start.v == minV || side.start.v == maxV,
                      min(side.start.u, side.end.u) == minU,
                      max(side.start.u, side.end.u) == maxU else { throw refusal() }
            }
        }
        guard minU >= surface.uKnots[surface.uDegree],
              maxU <= surface.uKnots[surface.uControlPointCount],
              minV >= surface.vKnots[surface.vDegree],
              maxV <= surface.vKnots[surface.vControlPointCount] else { throw refusal() }
        return (u: (minU, maxU), v: (minV, maxV))
    }

    private enum RectangularParameterAxis: Equatable { case u, v }

    /// Proof widths and native-grid emission use identical stations, including exact endpoints.
    static func station(lowerBound: Double, upperBound: Double,
                        index: Int, count: Int) -> Double {
        if index == 0 { return lowerBound }
        if index == count { return upperBound }
        return lowerBound + (upperBound - lowerBound) * (Double(index) / Double(count))
    }
}
