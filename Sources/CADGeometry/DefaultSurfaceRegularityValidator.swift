import CADCore
import Foundation

/// Certifies surface regularity with outward-rounded differential enclosures.
public struct DefaultSurfaceRegularityValidator: SurfaceRegularityValidating, Sendable {
    private struct Cell: Sendable {
        let parameters: SurfaceParameterBox
        let depth: Int
    }

    public let maximumSubdivisionDepth: Int
    public let maximumCellCount: Int

    public init(
        maximumSubdivisionDepth: Int = 32,
        maximumCellCount: Int = 1_048_576
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
    }

    public func validate(
        _ surface: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try parameters.validate(for: surface, tolerance: tolerance)
        guard maximumSubdivisionDepth > 0, maximumCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface regularity limits must be positive."
            )
        }

        var remainingCells = maximumCellCount
        var stack = [Cell(parameters: parameters, depth: 0)]
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Surface regularity exhausted its certified cell budget."
                )
            }
            remainingCells -= 1

            do {
                let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
                    of: surface,
                    over: cell.parameters,
                    tolerance: tolerance
                )
                if certifiesRegularity(jet, tolerance: tolerance) {
                    continue
                }
            } catch let error as KernelError where error.code == .singularSystem {
                // A wide interval may include zero through dependency even
                // when each smaller cell is regular. Subdivision preserves
                // the proof contract instead of accepting a midpoint sample.
            }

            let midpointU = cell.parameters.u.midpoint
            let midpointV = cell.parameters.v.midpoint
            let differential = try surface.parameterDerivatives(
                atU: midpointU,
                v: midpointV,
                tolerance: tolerance
            )
            if isSingular(differential, tolerance: tolerance) {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "The surface parameterization contains a singular tangent frame."
                )
            }
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Surface regularity could not certify a cell within the subdivision limit."
                )
            }
            stack.append(contentsOf: try subdivided(cell).reversed())
        }
    }

    private func certifiesRegularity(
        _ jet: SurfaceIntervalVectorJet,
        tolerance: ModelingTolerance
    ) -> Bool {
        let tangentU = jet.differentiatedUThroughSecondOrder()
        let tangentV = jet.differentiatedVThroughSecondOrder()
        let tangentUSquared = tangentU.dot(tangentU).value
        let tangentVSquared = tangentV.dot(tangentV).value
        let normalSquared = tangentU.cross(tangentV).dot(
            tangentU.cross(tangentV)
        ).value
        let minimumTangentSquared = (tolerance.distance * tolerance.distance).nextUp
        guard tangentUSquared.lower > minimumTangentSquared,
              tangentVSquared.lower > minimumTangentSquared else {
            return false
        }
        let sineTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        let maximumMetricProduct = (
            tangentUSquared.upper * tangentVSquared.upper
        ).nextUp
        let minimumNormalSquared = (
            sineTolerance * sineTolerance * maximumMetricProduct
        ).nextUp
        return normalSquared.lower > minimumNormalSquared
    }

    private func isSingular(
        _ differential: SurfaceParameterDerivatives,
        tolerance: ModelingTolerance
    ) -> Bool {
        let tangentULength = differential.tangentU.length
        let tangentVLength = differential.tangentV.length
        guard tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance else {
            return true
        }
        let sine = differential.tangentU.cross(differential.tangentV).length
            / (tangentULength * tangentVLength)
        let sineTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        return sine.isFinite == false || sine <= sineTolerance
    }

    private func subdivided(_ cell: Cell) throws -> [Cell] {
        let u = cell.parameters.u
        let v = cell.parameters.v
        let middleU = u.midpoint
        let middleV = v.midpoint
        guard middleU > u.lower, middleU < u.upper,
              middleV > v.lower, middleV < v.upper else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Surface regularity reached the representable parameter resolution."
            )
        }
        let lowerU = try ScalarInterval(lower: u.lower, upper: middleU)
        let upperU = try ScalarInterval(lower: middleU, upper: u.upper)
        let lowerV = try ScalarInterval(lower: v.lower, upper: middleV)
        let upperV = try ScalarInterval(lower: middleV, upper: v.upper)
        let depth = cell.depth + 1
        return [
            Cell(parameters: SurfaceParameterBox(u: lowerU, v: lowerV), depth: depth),
            Cell(parameters: SurfaceParameterBox(u: upperU, v: lowerV), depth: depth),
            Cell(parameters: SurfaceParameterBox(u: lowerU, v: upperV), depth: depth),
            Cell(parameters: SurfaceParameterBox(u: upperU, v: upperV), depth: depth),
        ]
    }
}
