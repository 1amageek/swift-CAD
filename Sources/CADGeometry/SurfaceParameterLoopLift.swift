import Foundation
import CADCore

/// A deterministic lift of a closed surface-parameter loop into the chart's
/// universal cover, including its periodic winding class.
public struct SurfaceParameterLoopLift: Hashable, Sendable {
    public let points: [Point2D]
    public let uWinding: Int
    public let vWinding: Int
    public let closesThroughUSingularity: Bool
    public let planarBoundary: [Point2D]?

    public init(
        samples: [SurfaceParameter],
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard samples.count >= 3,
              samples.allSatisfy({
                  $0.u.isFinite && $0.v.isFinite
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A closed surface-parameter loop requires at least three finite samples."
            )
        }
        let topology = SurfaceParameterTopology(surface: surface)
        let uniqueSamples = Self.removingRepeatedClosure(
            samples,
            topology: topology,
            tolerance: tolerance
        )
        guard uniqueSamples.count >= 3 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A closed surface-parameter loop requires three distinct chart samples."
            )
        }
        let orderedSamples: [SurfaceParameter]
        if let singularIndex = uniqueSamples.firstIndex(where: {
            topology.isUSingular($0, tolerance: tolerance)
        }) {
            orderedSamples = Array(uniqueSamples[singularIndex...])
                + Array(uniqueSamples[..<singularIndex])
        } else {
            orderedSamples = uniqueSamples
        }
        let closedSamples = orderedSamples + [orderedSamples[0]]
        var lifted = [closedSamples[0]]
        lifted.reserveCapacity(closedSamples.count)
        for index in 1..<closedSamples.count {
            let previousRaw = closedSamples[index - 1]
            let currentRaw = closedSamples[index]
            guard let previous = lifted.last else { continue }
            let crossesUSingularity = topology.isUSingular(
                previousRaw,
                tolerance: tolerance
            ) || topology.isUSingular(
                currentRaw,
                tolerance: tolerance
            )
            lifted.append(SurfaceParameter(
                u: previous.u + (crossesUSingularity
                    ? 0.0
                    : try Self.periodicDelta(
                        from: previousRaw.u,
                        to: currentRaw.u,
                        period: topology.uPeriod,
                        tolerance: tolerance
                    )),
                v: previous.v + (try Self.periodicDelta(
                    from: previousRaw.v,
                    to: currentRaw.v,
                    period: topology.vPeriod,
                    tolerance: tolerance
                ))
            ))
        }
        guard let first = lifted.first, let last = lifted.last else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Closed surface-parameter lifting produced no chart path."
            )
        }
        let startsAtUSingularity = topology.isUSingular(
            closedSamples[0],
            tolerance: tolerance
        )
        let uWinding = startsAtUSingularity
            ? 0
            : try Self.winding(
                displacement: last.u - first.u,
                period: topology.uPeriod,
                tolerance: tolerance
            )
        let vWinding = try Self.winding(
            displacement: last.v - first.v,
            period: topology.vPeriod,
            tolerance: tolerance
        )
        let points = lifted.dropLast().map {
            Point2D(x: $0.u, y: $0.v)
        }
        let closesThroughUSingularity = startsAtUSingularity || (
            abs(uWinding) == 1
                && vWinding == 0
                && topology.uSingularVValues.isEmpty == false
        )
        let planarBoundary: [Point2D]?
        if uWinding == 0 && vWinding == 0 {
            planarBoundary = points
        } else if closesThroughUSingularity,
                  vWinding == 0,
                  let poleV = topology.uSingularVValues.min(by: {
                      abs($0 - Self.meanV(points)) < abs($1 - Self.meanV(points))
                  }) {
            planarBoundary = points + [
                Point2D(x: last.u, y: poleV),
                Point2D(x: first.u, y: poleV),
            ]
        } else {
            planarBoundary = nil
        }
        self.points = points
        self.uWinding = uWinding
        self.vWinding = vWinding
        self.closesThroughUSingularity = closesThroughUSingularity
        self.planarBoundary = planarBoundary
    }

    public var isContractible: Bool {
        planarBoundary != nil
    }

    private static func removingRepeatedClosure(
        _ samples: [SurfaceParameter],
        topology: SurfaceParameterTopology,
        tolerance: ModelingTolerance
    ) -> [SurfaceParameter] {
        guard let first = samples.first, let last = samples.last else {
            return samples
        }
        let uResidual = periodicResidual(
            first.u - last.u,
            period: topology.uPeriod
        )
        let vResidual = periodicResidual(
            first.v - last.v,
            period: topology.vPeriod
        )
        guard hypot(uResidual, vResidual)
            <= max(tolerance.distance, tolerance.angle) else {
            return samples
        }
        return Array(samples.dropLast())
    }

    private static func periodicDelta(
        from start: Double,
        to end: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let period else { return end - start }
        var delta = (end - start).truncatingRemainder(dividingBy: period)
        if delta > period * 0.5 {
            delta -= period
        } else if delta < -period * 0.5 {
            delta += period
        }
        guard abs(abs(delta) - period * 0.5)
            > max(tolerance.distance, tolerance.angle) else {
            throw KernelError(
                phase: .geometry,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "A closed surface-parameter loop contains an ambiguous half-period sample step."
            )
        }
        return delta
    }

    private static func winding(
        displacement: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Int {
        guard let period else {
            guard abs(displacement) <= max(tolerance.distance, tolerance.angle) else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    residual: abs(displacement),
                    tolerance: tolerance,
                    message: "A non-periodic surface-parameter loop does not close in its chart."
                )
            }
            return 0
        }
        let winding = (displacement / period).rounded()
        let residual = abs(displacement - winding * period)
        guard winding >= Double(Int.min),
              winding <= Double(Int.max),
              residual <= max(tolerance.distance, tolerance.angle) else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A periodic surface-parameter loop has a non-integral chart winding."
            )
        }
        return Int(winding)
    }

    private static func periodicResidual(
        _ displacement: Double,
        period: Double?
    ) -> Double {
        guard let period else { return displacement }
        var residual = displacement.truncatingRemainder(dividingBy: period)
        if residual > period * 0.5 {
            residual -= period
        } else if residual < -period * 0.5 {
            residual += period
        }
        return residual
    }

    private static func meanV(_ points: [Point2D]) -> Double {
        points.reduce(0.0) { $0 + $1.y } / Double(points.count)
    }
}
