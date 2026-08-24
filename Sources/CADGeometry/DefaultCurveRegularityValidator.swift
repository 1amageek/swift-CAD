import CADCore
import Foundation

/// Certifies curve regularity with outward-rounded differential enclosures.
public struct DefaultCurveRegularityValidator: CurveRegularityValidating, Sendable {
    private struct Cell: Sendable {
        let parameters: ScalarInterval
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
        _ curve: Curve3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard try curve.parameterDomain.containsSpan(
            from: parameters.lower,
            to: parameters.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve regularity interval lies outside the curve domain."
            )
        }
        guard maximumSubdivisionDepth > 0, maximumCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve regularity limits must be positive."
            )
        }

        let encloser = DefaultCurveDifferentialEncloser()
        var remainingCells = maximumCellCount
        var stack = [Cell(parameters: parameters, depth: 0)]
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Curve regularity exhausted its certified cell budget."
                )
            }
            remainingCells -= 1

            do {
                let enclosure = try encloser.enclosure(
                    of: curve,
                    over: cell.parameters,
                    tolerance: tolerance
                )
                if certifiesRegularity(
                    enclosure.firstDerivative,
                    tolerance: tolerance
                ) {
                    continue
                }
            } catch let error as KernelError where error.code == .singularSystem {
                // A wide interval can contain a dependency-induced zero. A
                // smaller interval must prove regularity before it is accepted.
            }

            try rejectObservedSingularity(
                curve,
                parameters: cell.parameters,
                tolerance: tolerance
            )
            guard cell.depth < maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Curve regularity could not certify a cell within the subdivision limit."
                )
            }
            stack.append(contentsOf: try subdivided(cell).reversed())
        }
    }

    private func certifiesRegularity(
        _ derivative: CoordinateEnclosure3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let minimumSquaredLength = (
            squaredMinimumAbsoluteValue(in: derivative.x)
                + squaredMinimumAbsoluteValue(in: derivative.y)
                + squaredMinimumAbsoluteValue(in: derivative.z)
        ).nextDown
        return minimumSquaredLength
            > (tolerance.distance * tolerance.distance).nextUp
    }

    private func squaredMinimumAbsoluteValue(in interval: ScalarInterval) -> Double {
        let minimum: Double
        if interval.lower <= 0.0, interval.upper >= 0.0 {
            minimum = 0.0
        } else {
            minimum = min(abs(interval.lower), abs(interval.upper)).nextDown
        }
        return (minimum * minimum).nextDown
    }

    private func rejectObservedSingularity(
        _ curve: Curve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws {
        var previous: Double?
        for parameter in [parameters.lower, parameters.midpoint, parameters.upper] {
            if let previous, parameter == previous { continue }
            do {
                let geometry = try curve.differentialGeometry(
                    at: parameter,
                    tolerance: tolerance
                )
                guard geometry.firstDerivative.length > tolerance.distance else {
                    throw singularity(tolerance: tolerance)
                }
            } catch let error as KernelError where error.code == .singularGeometry {
                throw singularity(tolerance: tolerance)
            } catch let error as GeometryError {
                if case .invalidVectorLength = error {
                    throw singularity(tolerance: tolerance)
                }
                throw error
            }
            previous = parameter
        }
    }

    private func subdivided(_ cell: Cell) throws -> [Cell] {
        let middle = cell.parameters.midpoint
        guard middle > cell.parameters.lower,
              middle < cell.parameters.upper else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "Curve regularity reached the representable parameter resolution."
            )
        }
        let depth = cell.depth + 1
        return [
            Cell(
                parameters: try ScalarInterval(
                    lower: cell.parameters.lower,
                    upper: middle
                ),
                depth: depth
            ),
            Cell(
                parameters: try ScalarInterval(
                    lower: middle,
                    upper: cell.parameters.upper
                ),
                depth: depth
            ),
        ]
    }

    private func singularity(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularGeometry,
            tolerance: tolerance,
            message: "The curve parameterization contains a singular tangent."
        )
    }
}
