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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(samples: samples, surface: surface, tolerance: tolerance, using: &execution)
    }

    public init(samples: [SurfaceParameter], surface: Surface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard samples.count >= 3,
              try samples.allSatisfy({
                  try execution.consumeWork(1)
                  return $0.u.isFinite && $0.v.isFinite
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A closed surface-parameter loop requires at least three finite samples."
            )
        }
        let topology = try SurfaceParameterTopology(surface: surface, using: &execution)
        let uniqueSamples = try Self.removingRepeatedClosure(
            samples,
            topology: topology,
            tolerance: tolerance, using: &execution
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
        if let singularIndex = try uniqueSamples.firstIndex(where: {
            try execution.consumeWork(1)
            return try topology.isUSingular($0, tolerance: tolerance, using: &execution)
        }) {
            orderedSamples = try OriginalCoefficientAllocation.map(elements: uniqueSamples.indices, using: &execution) { index, _ in
                let remaining = uniqueSamples.count - singularIndex
                return uniqueSamples[index < remaining ? singularIndex + index : index - remaining]
            }
        } else {
            orderedSamples = uniqueSamples
        }
        let closedCount = try exactScalarCount(orderedSamples.count, 1, multiply: false)
        try OriginalCoefficientAllocation.reserve(count: closedCount, of: SurfaceParameter.self, using: &execution)
        var lifted: [SurfaceParameter] = []; lifted.reserveCapacity(closedCount)
        lifted.append(orderedSamples[0])
        for index in 1..<closedCount {
            try execution.consumeWork(1)
            let previousRaw = orderedSamples[index - 1]
            let currentRaw = orderedSamples[index == orderedSamples.count ? 0 : index]
            guard let previous = lifted.last else { continue }
            let crossesUSingularity = try topology.isUSingular(previousRaw, tolerance: tolerance, using: &execution)
                || topology.isUSingular(currentRaw, tolerance: tolerance, using: &execution)
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
        let startsAtUSingularity = try topology.isUSingular(orderedSamples[0], tolerance: tolerance, using: &execution)
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
        let points = try OriginalCoefficientAllocation.map(elements: lifted.dropLast(), using: &execution) { parameter, _ in
            Point2D(x: parameter.u, y: parameter.v)
        }
        let closesThroughUSingularity = startsAtUSingularity || (
            abs(uWinding) == 1
                && vWinding == 0
                && topology.uSingularVValues.isEmpty == false
        )
        let planarBoundary: [Point2D]?
        if uWinding == 0 && vWinding == 0 {
            planarBoundary = points
        } else if closesThroughUSingularity, vWinding == 0 {
            let mean = try Self.meanV(points, using: &execution)
            if let poleV = try topology.uSingularVValues.min(by: {
                try execution.consumeWork(1)
                return abs($0 - mean) < abs($1 - mean)
            }) {
                let count = try exactScalarCount(points.count, 2, multiply: false)
                try OriginalCoefficientAllocation.reserve(count: count, of: Point2D.self, using: &execution)
                var boundary: [Point2D] = []; boundary.reserveCapacity(count)
                for point in points { try execution.consumeWork(1); boundary.append(point) }
                boundary.append(Point2D(x: last.u, y: poleV))
                boundary.append(Point2D(x: first.u, y: poleV))
                planarBoundary = boundary
            } else { planarBoundary = nil }
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceParameter] {
        try execution.consumeWork(1)
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
        return try OriginalCoefficientAllocation.map(elements: samples.dropLast(), using: &execution) { value, _ in value }
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

    private static func meanV(_ points: [Point2D], using execution: inout OriginalQueryExecution) throws -> Double {
        var sum = 0.0
        for point in points { try execution.consumeWork(1); sum += point.y }
        return sum / Double(points.count)
    }


}
