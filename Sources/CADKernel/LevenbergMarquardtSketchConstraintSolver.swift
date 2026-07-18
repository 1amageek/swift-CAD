import Foundation
import CADCore
import CADIR
import CADModeling

public struct LevenbergMarquardtSketchConstraintSolver: SketchConstraintSolving {
    private let resolver: ParameterResolving
    private let options: SketchConstraintSolverOptions

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        options: SketchConstraintSolverOptions = SketchConstraintSolverOptions()
    ) {
        self.resolver = resolver
        self.options = options
    }

    public func solve(
        _ sketch: Sketch,
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> SketchConstraintSolveResult {
        try tolerance.validate()
        try options.validate()
        try sketch.validate(tolerance: tolerance)
        let system = try SketchVariableSystem(
            sketch: sketch,
            parameters: parameters,
            resolver: resolver
        )
        guard system.values.isEmpty == false else {
            return SketchConstraintSolveResult(
                sketch: sketch,
                status: .fullyConstrained,
                remainingDegreesOfFreedom: 0,
                redundantEquationCount: 0,
                maximumNormalizedResidual: 0.0,
                iterations: 0
            )
        }

        var values = system.values
        var damping = options.initialDamping
        var iterations = 0
        var singular = false
        var evaluation = try equations(
            sketch: sketch,
            system: system,
            values: values,
            parameters: parameters,
            tolerance: tolerance
        )

        while iterations < options.maximumIterations && evaluation.isSatisfied == false {
            iterations += 1
            let normal = normalEquations(evaluation: evaluation, damping: damping)
            guard let step = solveLinearSystem(normal.matrix, rightHandSide: normal.rightHandSide) else {
                singular = true
                break
            }
            let stepNorm = sqrt(step.reduce(0.0) { $0 + $1 * $1 })
            guard stepNorm.isFinite else {
                singular = true
                break
            }
            if stepNorm <= options.minimumStep {
                break
            }
            let candidateValues = zip(values, step).map(+)
            let candidate = try equations(
                sketch: sketch,
                system: system,
                values: candidateValues,
                parameters: parameters,
                tolerance: tolerance
            )
            if candidate.squaredNorm < evaluation.squaredNorm {
                values = candidateValues
                evaluation = candidate
                damping = max(damping * 0.25, 1.0e-12)
            } else {
                damping = min(damping * 8.0, 1.0e12)
            }
        }

        let rank = matrixRank(evaluation.jacobian)
        let remainingDegreesOfFreedom = max(0, values.count - rank)
        let redundantEquationCount = max(0, evaluation.residuals.count - rank)
        let status: SketchConstraintSolveStatus
        if singular {
            status = .singular
        } else if evaluation.isSatisfied == false {
            status = .conflicting
        } else if redundantEquationCount > 0 {
            status = .overConstrained
        } else if remainingDegreesOfFreedom > 0 {
            status = .underConstrained
        } else {
            status = .fullyConstrained
        }
        return SketchConstraintSolveResult(
            sketch: system.applying(values, to: sketch),
            status: status,
            remainingDegreesOfFreedom: remainingDegreesOfFreedom,
            redundantEquationCount: redundantEquationCount,
            maximumNormalizedResidual: evaluation.maximumNormalizedResidual,
            iterations: iterations
        )
    }

    private func equations(
        sketch: Sketch,
        system: SketchVariableSystem,
        values: [Double],
        parameters: ResolvedParameterTable,
        tolerance: ModelingTolerance
    ) throws -> EquationEvaluation {
        let variables = values.indices.map { ForwardScalar.variable(values[$0], at: $0, count: values.count) }
        var equations: [ResidualEquation] = []
        for constraint in sketch.constraints {
            try append(
                constraint: constraint,
                sketch: sketch,
                system: system,
                variables: variables,
                tolerance: tolerance,
                to: &equations
            )
        }
        for dimension in sketch.dimensions {
            try append(
                dimension: dimension,
                system: system,
                variables: variables,
                parameters: parameters,
                to: &equations
            )
        }
        return EquationEvaluation(equations: equations, tolerance: tolerance)
    }

    private func append(
        constraint: SketchConstraint,
        sketch: Sketch,
        system: SketchVariableSystem,
        variables: [ForwardScalar],
        tolerance: ModelingTolerance,
        to equations: inout [ResidualEquation]
    ) throws {
        switch constraint {
        case let .coincident(first, second):
            let firstPoint = try system.point(first, variables: variables)
            let secondPoint = try system.point(second, variables: variables)
            equations.append(.distance(firstPoint.x - secondPoint.x))
            equations.append(.distance(firstPoint.y - secondPoint.y))
        case let .horizontal(entityID):
            let line = try system.line(entityID, variables: variables)
            equations.append(.distance(line.end.y - line.start.y))
        case let .vertical(entityID):
            let line = try system.line(entityID, variables: variables)
            equations.append(.distance(line.end.x - line.start.x))
        case let .parallel(firstID, secondID):
            let first = try system.line(firstID, variables: variables).direction
            let second = try system.line(secondID, variables: variables).direction
            equations.append(.angle(try normalizedCross(first, second, tolerance: tolerance)))
        case let .perpendicular(firstID, secondID):
            let first = try system.line(firstID, variables: variables).direction
            let second = try system.line(secondID, variables: variables).direction
            equations.append(.angle(try normalizedDot(first, second, tolerance: tolerance)))
        case let .equalLength(firstID, secondID):
            let first = try system.line(firstID, variables: variables).direction.length
            let second = try system.line(secondID, variables: variables).direction.length
            equations.append(.distance(first - second))
        case let .tangent(firstID, secondID):
            let tangent = try system.tangentResidual(
                firstID,
                secondID,
                variables: variables,
                tolerance: tolerance
            )
            equations.append(.distance(tangent))
        case let .concentric(firstID, secondID):
            let first = try system.circular(firstID, variables: variables)
            let second = try system.circular(secondID, variables: variables)
            equations.append(.distance(first.center.x - second.center.x))
            equations.append(.distance(first.center.y - second.center.y))
        case let .equalRadius(firstID, secondID):
            equations.append(.distance(
                try system.circular(firstID, variables: variables).radius
                    - system.circular(secondID, variables: variables).radius
            ))
        case let .smoothSplineControlPoint(entityID, index):
            let points = try system.splinePoints(entityID, variables: variables)
            let incoming = points[index] - points[index - 1]
            let outgoing = points[index + 1] - points[index]
            equations.append(.angle(try normalizedCross(incoming, outgoing, tolerance: tolerance)))
        case let .splineEndpointTangent(splineID, endpoint, lineID):
            let tangent = try system.splineTangent(splineID, endpoint: endpoint, variables: variables)
            let line = try system.line(lineID, variables: variables).direction
            equations.append(.angle(try normalizedCross(tangent, line, tolerance: tolerance)))
        case let .tangentSplineEndpoints(first, second):
            try appendSplineEndpointPair(
                first: first,
                second: second,
                smooth: false,
                system: system,
                variables: variables,
                tolerance: tolerance,
                to: &equations
            )
        case let .smoothSplineEndpoints(first, second):
            try appendSplineEndpointPair(
                first: first,
                second: second,
                smooth: true,
                system: system,
                variables: variables,
                tolerance: tolerance,
                to: &equations
            )
        case let .fixed(reference):
            for (current, initial, kind) in try system.fixedComponents(reference, variables: variables) {
                equations.append(ResidualEquation(value: current - initial, kind: kind))
            }
        }
    }

    private func appendSplineEndpointPair(
        first: SketchSplineEndpointReference,
        second: SketchSplineEndpointReference,
        smooth: Bool,
        system: SketchVariableSystem,
        variables: [ForwardScalar],
        tolerance: ModelingTolerance,
        to equations: inout [ResidualEquation]
    ) throws {
        let firstPoint = try system.splineEndpoint(first, variables: variables)
        let secondPoint = try system.splineEndpoint(second, variables: variables)
        equations.append(.distance(firstPoint.x - secondPoint.x))
        equations.append(.distance(firstPoint.y - secondPoint.y))
        let firstTangent = try system.splineTangent(first.splineID, endpoint: first.endpoint, variables: variables)
        let secondTangent = try system.splineTangent(second.splineID, endpoint: second.endpoint, variables: variables)
        equations.append(.angle(try normalizedCross(firstTangent, secondTangent, tolerance: tolerance)))
        if smooth {
            equations.append(.distance(firstTangent.length - secondTangent.length))
        }
    }

    private func append(
        dimension: SketchDimension,
        system: SketchVariableSystem,
        variables: [ForwardScalar],
        parameters: ResolvedParameterTable,
        to equations: inout [ResidualEquation]
    ) throws {
        switch dimension {
        case let .distance(from, to, expression):
            let first = try system.point(from, variables: variables)
            let second = try system.point(to, variables: variables)
            let target = try target(expression, kind: .length, parameters: parameters)
            equations.append(.distance((second - first).length - target))
        case let .angle(from, to, expression):
            let target = try target(expression, kind: .angle, parameters: parameters)
            let measured = try system.angle(from: from, to: to, variables: variables)
            equations.append(.angle(normalizedAngle(measured - target)))
        case let .radius(entityID, expression):
            let target = try target(expression, kind: .length, parameters: parameters)
            equations.append(.distance(try system.circular(entityID, variables: variables).radius - target))
        case let .diameter(entityID, expression):
            let target = try target(expression, kind: .length, parameters: parameters)
            equations.append(.distance(try system.circular(entityID, variables: variables).radius * 2.0 - target))
        }
    }

    private func target(
        _ expression: CADExpression,
        kind: QuantityKind,
        parameters: ResolvedParameterTable
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
        guard quantity.kind == kind else {
            throw UnitError.expectedQuantity(operation: "sketch.constraint", expected: kind, actual: quantity.kind)
        }
        return quantity.value
    }

    private func normalizedCross(
        _ first: ForwardVector2,
        _ second: ForwardVector2,
        tolerance: ModelingTolerance
    ) throws -> ForwardScalar {
        let denominator = first.length * second.length
        guard denominator.value > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .evaluation,
                code: .singularSystem,
                residual: denominator.value,
                tolerance: tolerance,
                message: "Sketch angular constraint contains a degenerate direction."
            )
        }
        return first.cross(second) / denominator
    }

    private func normalizedDot(
        _ first: ForwardVector2,
        _ second: ForwardVector2,
        tolerance: ModelingTolerance
    ) throws -> ForwardScalar {
        let denominator = first.length * second.length
        guard denominator.value > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .evaluation,
                code: .singularSystem,
                residual: denominator.value,
                tolerance: tolerance,
                message: "Sketch angular constraint contains a degenerate direction."
            )
        }
        return first.dot(second) / denominator
    }

    private func normalEquations(
        evaluation: EquationEvaluation,
        damping: Double
    ) -> (matrix: [[Double]], rightHandSide: [Double]) {
        let variableCount = evaluation.jacobian.first?.count ?? 0
        var matrix = Array(repeating: Array(repeating: 0.0, count: variableCount), count: variableCount)
        var rightHandSide = Array(repeating: 0.0, count: variableCount)
        for row in evaluation.jacobian.indices {
            for column in 0..<variableCount {
                rightHandSide[column] -= evaluation.jacobian[row][column] * evaluation.residuals[row]
                for other in column..<variableCount {
                    matrix[column][other] += evaluation.jacobian[row][column] * evaluation.jacobian[row][other]
                }
            }
        }
        for row in 0..<variableCount {
            for column in 0..<row {
                matrix[row][column] = matrix[column][row]
            }
            matrix[row][row] += damping
        }
        return (matrix, rightHandSide)
    }

    private func solveLinearSystem(
        _ matrix: [[Double]],
        rightHandSide: [Double]
    ) -> [Double]? {
        guard matrix.count == rightHandSide.count else { return nil }
        var matrix = matrix
        var result = rightHandSide
        for pivot in matrix.indices {
            guard let selected = (pivot..<matrix.count).max(by: {
                abs(matrix[$0][pivot]) < abs(matrix[$1][pivot])
            }), abs(matrix[selected][pivot]) > 1.0e-18 else {
                return nil
            }
            if selected != pivot {
                matrix.swapAt(selected, pivot)
                result.swapAt(selected, pivot)
            }
            let divisor = matrix[pivot][pivot]
            for column in pivot..<matrix.count {
                matrix[pivot][column] /= divisor
            }
            result[pivot] /= divisor
            for row in matrix.indices where row != pivot {
                let factor = matrix[row][pivot]
                guard factor != 0.0 else { continue }
                for column in pivot..<matrix.count {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
                result[row] -= factor * result[pivot]
            }
        }
        return result.allSatisfy(\.isFinite) ? result : nil
    }

    private func matrixRank(_ input: [[Double]]) -> Int {
        guard input.isEmpty == false, let columnCount = input.first?.count else { return 0 }
        var matrix = input
        var rank = 0
        for column in 0..<columnCount where rank < matrix.count {
            guard let pivot = (rank..<matrix.count).max(by: {
                abs(matrix[$0][column]) < abs(matrix[$1][column])
            }), abs(matrix[pivot][column]) > 1.0e-9 else {
                continue
            }
            matrix.swapAt(rank, pivot)
            let divisor = matrix[rank][column]
            for index in column..<columnCount {
                matrix[rank][index] /= divisor
            }
            for row in matrix.indices where row != rank {
                let factor = matrix[row][column]
                for index in column..<columnCount {
                    matrix[row][index] -= factor * matrix[rank][index]
                }
            }
            rank += 1
        }
        return rank
    }

    private func normalizedAngle(_ scalar: ForwardScalar) -> ForwardScalar {
        ForwardScalar(
            value: atan2(sin(scalar.value), cos(scalar.value)),
            derivatives: scalar.derivatives
        )
    }
}

private struct ResidualEquation {
    enum Kind: Equatable {
        case distance
        case angle
    }

    let value: ForwardScalar
    let kind: Kind

    static func distance(_ value: ForwardScalar) -> Self {
        Self(value: value, kind: .distance)
    }

    static func angle(_ value: ForwardScalar) -> Self {
        Self(value: value, kind: .angle)
    }
}

private struct EquationEvaluation {
    let residuals: [Double]
    let jacobian: [[Double]]
    let squaredNorm: Double
    let maximumNormalizedResidual: Double
    let isSatisfied: Bool

    init(equations: [ResidualEquation], tolerance: ModelingTolerance) {
        residuals = equations.map(\.value.value)
        jacobian = equations.map(\.value.derivatives)
        squaredNorm = residuals.reduce(0.0) { $0 + $1 * $1 }
        maximumNormalizedResidual = zip(equations, residuals).map { equation, residual in
            let scale = equation.kind == .distance ? tolerance.distance : tolerance.angle
            return abs(residual) / scale
        }.max() ?? 0.0
        isSatisfied = maximumNormalizedResidual <= 1.0
    }
}

private struct ForwardScalar {
    let value: Double
    let derivatives: [Double]

    static func variable(_ value: Double, at index: Int, count: Int) -> Self {
        var derivatives = Array(repeating: 0.0, count: count)
        derivatives[index] = 1.0
        return Self(value: value, derivatives: derivatives)
    }

    static func constant(_ value: Double, count: Int) -> Self {
        Self(value: value, derivatives: Array(repeating: 0.0, count: count))
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(value: lhs.value + rhs.value, derivatives: zip(lhs.derivatives, rhs.derivatives).map(+))
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(value: lhs.value - rhs.value, derivatives: zip(lhs.derivatives, rhs.derivatives).map(-))
    }

    static prefix func - (value: Self) -> Self {
        Self(value: -value.value, derivatives: value.derivatives.map(-))
    }

    static func * (lhs: Self, rhs: Self) -> Self {
        Self(
            value: lhs.value * rhs.value,
            derivatives: zip(lhs.derivatives, rhs.derivatives).map {
                $0 * rhs.value + lhs.value * $1
            }
        )
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        Self(value: lhs.value * rhs, derivatives: lhs.derivatives.map { $0 * rhs })
    }

    static func - (lhs: Self, rhs: Double) -> Self {
        Self(value: lhs.value - rhs, derivatives: lhs.derivatives)
    }

    static func / (lhs: Self, rhs: Self) -> Self {
        let denominator = rhs.value * rhs.value
        return Self(
            value: lhs.value / rhs.value,
            derivatives: zip(lhs.derivatives, rhs.derivatives).map {
                ($0 * rhs.value - lhs.value * $1) / denominator
            }
        )
    }

    var squareRoot: Self {
        let root = sqrt(max(value, 0.0))
        guard root > 1.0e-18 else {
            return Self(value: root, derivatives: Array(repeating: 0.0, count: derivatives.count))
        }
        return Self(value: root, derivatives: derivatives.map { $0 / (2.0 * root) })
    }

    var sine: Self {
        Self(value: sin(value), derivatives: derivatives.map { cos(value) * $0 })
    }

    var cosine: Self {
        Self(value: cos(value), derivatives: derivatives.map { -sin(value) * $0 })
    }

    static func atan2(_ y: Self, _ x: Self) -> Self {
        let denominator = x.value * x.value + y.value * y.value
        return Self(
            value: Foundation.atan2(y.value, x.value),
            derivatives: zip(y.derivatives, x.derivatives).map {
                (x.value * $0 - y.value * $1) / denominator
            }
        )
    }
}

private struct ForwardVector2 {
    let x: ForwardScalar
    let y: ForwardScalar

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    func dot(_ other: Self) -> ForwardScalar {
        x * other.x + y * other.y
    }

    func cross(_ other: Self) -> ForwardScalar {
        x * other.y - y * other.x
    }

    var length: ForwardScalar {
        (x * x + y * y).squareRoot
    }
}

private struct ForwardLine {
    let start: ForwardVector2
    let end: ForwardVector2

    var direction: ForwardVector2 { end - start }
}

private struct ForwardCircle {
    let center: ForwardVector2
    let radius: ForwardScalar
}

private struct SketchVariableSystem {
    enum Layout {
        case point(Int, Int)
        case line(Int, Int, Int, Int)
        case circle(Int, Int, Int)
        case arc(Int, Int, Int, Int, Int)
        case spline([(Int, Int)])
    }

    let layouts: [SketchEntityID: Layout]
    let values: [Double]

    init(
        sketch: Sketch,
        parameters: ResolvedParameterTable,
        resolver: ParameterResolving
    ) throws {
        var layouts: [SketchEntityID: Layout] = [:]
        var values: [Double] = []

        func append(_ expression: CADExpression, kind: QuantityKind) throws -> Int {
            let quantity = try resolver.evaluate(expression, parameters: parameters, variables: [:])
            guard quantity.kind == kind else {
                throw UnitError.expectedQuantity(operation: "sketch.constraint.variable", expected: kind, actual: quantity.kind)
            }
            let index = values.count
            values.append(quantity.value)
            return index
        }

        for (entityID, entity) in sketch.entities.sorted(by: { $0.key < $1.key }) {
            switch entity {
            case let .point(point):
                layouts[entityID] = .point(
                    try append(point.x, kind: .length),
                    try append(point.y, kind: .length)
                )
            case let .line(line):
                layouts[entityID] = .line(
                    try append(line.start.x, kind: .length),
                    try append(line.start.y, kind: .length),
                    try append(line.end.x, kind: .length),
                    try append(line.end.y, kind: .length)
                )
            case let .circle(circle):
                layouts[entityID] = .circle(
                    try append(circle.center.x, kind: .length),
                    try append(circle.center.y, kind: .length),
                    try append(circle.radius, kind: .length)
                )
            case let .arc(arc):
                layouts[entityID] = .arc(
                    try append(arc.center.x, kind: .length),
                    try append(arc.center.y, kind: .length),
                    try append(arc.radius, kind: .length),
                    try append(arc.startAngle, kind: .angle),
                    try append(arc.endAngle, kind: .angle)
                )
            case let .spline(spline):
                var indices: [(Int, Int)] = []
                for point in spline.controlPoints {
                    indices.append((
                        try append(point.x, kind: .length),
                        try append(point.y, kind: .length)
                    ))
                }
                layouts[entityID] = .spline(indices)
            }
        }
        self.layouts = layouts
        self.values = values
    }

    func point(_ reference: SketchReference, variables: [ForwardScalar]) throws -> ForwardVector2 {
        switch reference {
        case let .entity(entityID):
            guard case let .point(x, y) = try layout(entityID) else {
                throw SketchError.invalidReference("Entity point reference must identify a point entity.")
            }
            return vector(x, y, variables: variables)
        case let .lineStart(entityID):
            return try line(entityID, variables: variables).start
        case let .lineEnd(entityID):
            return try line(entityID, variables: variables).end
        case let .circleCenter(entityID):
            return try circular(entityID, variables: variables).center
        case let .arcCenter(entityID):
            return try circular(entityID, variables: variables).center
        case let .arcStart(entityID):
            return try arcPoint(entityID, useStart: true, variables: variables)
        case let .arcEnd(entityID):
            return try arcPoint(entityID, useStart: false, variables: variables)
        case let .splineControlPoint(entityID, index):
            let points = try splinePoints(entityID, variables: variables)
            guard points.indices.contains(index) else {
                throw SketchError.invalidReference("Spline point reference is outside the control point array.")
            }
            return points[index]
        case .circleRadius, .arcRadius:
            throw SketchError.invalidReference("Radius reference is not a point.")
        }
    }

    func line(_ entityID: SketchEntityID, variables: [ForwardScalar]) throws -> ForwardLine {
        guard case let .line(startX, startY, endX, endY) = try layout(entityID) else {
            throw SketchError.invalidReference("Line constraint requires a line entity.")
        }
        return ForwardLine(
            start: vector(startX, startY, variables: variables),
            end: vector(endX, endY, variables: variables)
        )
    }

    func circular(_ entityID: SketchEntityID, variables: [ForwardScalar]) throws -> ForwardCircle {
        switch try layout(entityID) {
        case let .circle(x, y, radius), let .arc(x, y, radius, _, _):
            return ForwardCircle(center: vector(x, y, variables: variables), radius: variables[radius])
        case .point, .line, .spline:
            throw SketchError.invalidReference("Circular constraint requires a circle or arc entity.")
        }
    }

    func tangentResidual(
        _ firstID: SketchEntityID,
        _ secondID: SketchEntityID,
        variables: [ForwardScalar],
        tolerance: ModelingTolerance
    ) throws -> ForwardScalar {
        let lineID: SketchEntityID
        let circularID: SketchEntityID
        if case .line = try layout(firstID) {
            lineID = firstID
            circularID = secondID
        } else if case .line = try layout(secondID) {
            lineID = secondID
            circularID = firstID
        } else {
            throw SketchError.invalidReference("Tangent constraint requires one line and one circular entity.")
        }
        let line = try line(lineID, variables: variables)
        let circle = try circular(circularID, variables: variables)
        let direction = line.direction
        guard direction.length.value > tolerance.distance else {
            throw KernelError(
                phase: .evaluation,
                code: .singularSystem,
                residual: direction.length.value,
                tolerance: tolerance,
                message: "Tangent constraint contains a degenerate line."
            )
        }
        let signedArea = direction.cross(circle.center - line.start)
        let smoothAbsolute = (signedArea * signedArea + ForwardScalar.constant(
            tolerance.distance * tolerance.distance,
            count: variables.count
        )).squareRoot
        return smoothAbsolute / direction.length - circle.radius
    }

    func splinePoints(
        _ entityID: SketchEntityID,
        variables: [ForwardScalar]
    ) throws -> [ForwardVector2] {
        guard case let .spline(indices) = try layout(entityID) else {
            throw SketchError.invalidReference("Spline constraint requires a spline entity.")
        }
        return indices.map { vector($0.0, $0.1, variables: variables) }
    }

    func splineEndpoint(
        _ reference: SketchSplineEndpointReference,
        variables: [ForwardScalar]
    ) throws -> ForwardVector2 {
        let points = try splinePoints(reference.splineID, variables: variables)
        guard let point = reference.endpoint == .start ? points.first : points.last else {
            throw SketchError.invalidReference("Spline endpoint requires control points.")
        }
        return point
    }

    func splineTangent(
        _ entityID: SketchEntityID,
        endpoint: SketchSplineEndpoint,
        variables: [ForwardScalar]
    ) throws -> ForwardVector2 {
        let points = try splinePoints(entityID, variables: variables)
        guard points.count >= 2 else {
            throw SketchError.invalidReference("Spline tangent requires at least two control points.")
        }
        switch endpoint {
        case .start: return points[1] - points[0]
        case .end: return points[points.count - 1] - points[points.count - 2]
        }
    }

    func angle(
        from first: SketchReference,
        to second: SketchReference,
        variables: [ForwardScalar]
    ) throws -> ForwardScalar {
        if case let .arcStart(firstID) = first,
           case let .arcEnd(secondID) = second,
           firstID == secondID,
           case let .arc(_, _, _, start, end) = try layout(firstID) {
            return variables[end] - variables[start]
        }
        if case let .arcEnd(firstID) = first,
           case let .arcStart(secondID) = second,
           firstID == secondID,
           case let .arc(_, _, _, start, end) = try layout(firstID) {
            return variables[start] - variables[end]
        }
        if case let .entity(firstID) = first,
           case let .entity(secondID) = second,
           case .line = try layout(firstID),
           case .line = try layout(secondID) {
            let firstVector = try line(firstID, variables: variables).direction
            let secondVector = try line(secondID, variables: variables).direction
            let cross = firstVector.cross(secondVector)
            let absoluteCross = (cross * cross + ForwardScalar.constant(
                1.0e-24,
                count: variables.count
            )).squareRoot
            return ForwardScalar.atan2(absoluteCross, firstVector.dot(secondVector))
        }
        let vector = try point(second, variables: variables) - point(first, variables: variables)
        return ForwardScalar.atan2(vector.y, vector.x)
    }

    func fixedComponents(
        _ reference: SketchReference,
        variables: [ForwardScalar]
    ) throws -> [(ForwardScalar, Double, ResidualEquation.Kind)] {
        let indices: [(Int, ResidualEquation.Kind)]
        switch reference {
        case let .entity(entityID):
            indices = try allIndices(for: entityID)
        case let .lineStart(entityID):
            guard case let .line(x, y, _, _) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(x, .distance), (y, .distance)]
        case let .lineEnd(entityID):
            guard case let .line(_, _, x, y) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(x, .distance), (y, .distance)]
        case let .circleCenter(entityID):
            guard case let .circle(x, y, _) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(x, .distance), (y, .distance)]
        case let .circleRadius(entityID):
            guard case let .circle(_, _, radius) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(radius, .distance)]
        case let .arcCenter(entityID):
            guard case let .arc(x, y, _, _, _) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(x, .distance), (y, .distance)]
        case let .arcRadius(entityID):
            guard case let .arc(_, _, radius, _, _) = try layout(entityID) else { throw invalidFixedReference() }
            indices = [(radius, .distance)]
        case let .splineControlPoint(entityID, index):
            guard case let .spline(points) = try layout(entityID), points.indices.contains(index) else {
                throw invalidFixedReference()
            }
            indices = [(points[index].0, .distance), (points[index].1, .distance)]
        case let .arcStart(entityID), let .arcEnd(entityID):
            let useStart: Bool
            if case .arcStart = reference {
                useStart = true
            } else {
                useStart = false
            }
            let current = try arcPoint(entityID, useStart: useStart, variables: variables)
            let initialVariables = values.map {
                ForwardScalar.constant($0, count: variables.count)
            }
            let initial = try arcPoint(entityID, useStart: useStart, variables: initialVariables)
            return [
                (current.x, initial.x.value, .distance),
                (current.y, initial.y.value, .distance),
            ]
        }
        return indices.map { (variables[$0.0], values[$0.0], $0.1) }
    }

    func applying(_ values: [Double], to sketch: Sketch) -> Sketch {
        var result = sketch
        for (entityID, layout) in layouts {
            guard let original = sketch.entities[entityID] else { continue }
            switch (original, layout) {
            case let (.point, .point(x, y)):
                result.entities[entityID] = .point(point(x, y, values: values))
            case let (.line, .line(startX, startY, endX, endY)):
                result.entities[entityID] = .line(SketchLine(
                    start: point(startX, startY, values: values),
                    end: point(endX, endY, values: values)
                ))
            case let (.circle, .circle(x, y, radius)):
                result.entities[entityID] = .circle(SketchCircle(
                    center: point(x, y, values: values),
                    radius: length(values[radius])
                ))
            case let (.arc, .arc(x, y, radius, start, end)):
                result.entities[entityID] = .arc(SketchArc(
                    center: point(x, y, values: values),
                    radius: length(values[radius]),
                    startAngle: angle(values[start]),
                    endAngle: angle(values[end])
                ))
            case let (.spline(spline), .spline(indices)):
                result.entities[entityID] = .spline(SketchSpline(
                    controlPoints: indices.map { point($0.0, $0.1, values: values) },
                    isClosed: spline.isClosed
                ))
            default:
                continue
            }
        }
        return result
    }

    private func arcPoint(
        _ entityID: SketchEntityID,
        useStart: Bool,
        variables: [ForwardScalar]
    ) throws -> ForwardVector2 {
        guard case let .arc(x, y, radius, start, end) = try layout(entityID) else {
            throw SketchError.invalidReference("Arc point reference requires an arc entity.")
        }
        let angle = variables[useStart ? start : end]
        return ForwardVector2(
            x: variables[x] + variables[radius] * angle.cosine,
            y: variables[y] + variables[radius] * angle.sine
        )
    }

    private func allIndices(for entityID: SketchEntityID) throws -> [(Int, ResidualEquation.Kind)] {
        switch try layout(entityID) {
        case let .point(x, y):
            return [(x, .distance), (y, .distance)]
        case let .line(startX, startY, endX, endY):
            return [(startX, .distance), (startY, .distance), (endX, .distance), (endY, .distance)]
        case let .circle(x, y, radius):
            return [(x, .distance), (y, .distance), (radius, .distance)]
        case let .arc(x, y, radius, start, end):
            return [(x, .distance), (y, .distance), (radius, .distance), (start, .angle), (end, .angle)]
        case let .spline(points):
            return points.flatMap { [($0.0, .distance), ($0.1, .distance)] }
        }
    }

    private func layout(_ entityID: SketchEntityID) throws -> Layout {
        guard let layout = layouts[entityID] else {
            throw SketchError.invalidReference("Constraint references a missing sketch entity.")
        }
        return layout
    }

    private func vector(_ x: Int, _ y: Int, variables: [ForwardScalar]) -> ForwardVector2 {
        ForwardVector2(x: variables[x], y: variables[y])
    }

    private func point(_ x: Int, _ y: Int, values: [Double]) -> SketchPoint {
        SketchPoint(x: length(values[x]), y: length(values[y]))
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private func angle(_ value: Double) -> CADExpression {
        .constant(.angle(value, unit: .radian))
    }

    private func invalidFixedReference() -> SketchError {
        .invalidReference("Fixed constraint reference does not match the entity kind.")
    }
}
