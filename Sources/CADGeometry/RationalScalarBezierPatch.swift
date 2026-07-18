import CADCore

struct RationalScalarBezierPatch: Sendable {
    let numerator: [[Double]]
    let weights: [[Double]]
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double

    var distanceBounds: (lower: Double, upper: Double) {
        var lower = Double.greatestFiniteMagnitude
        var upper = -Double.greatestFiniteMagnitude
        for rowIndex in numerator.indices {
            for columnIndex in numerator[rowIndex].indices {
                let distance = numerator[rowIndex][columnIndex] / weights[rowIndex][columnIndex]
                lower = min(lower, distance)
                upper = max(upper, distance)
            }
        }
        return (lower, upper)
    }

    func subdivided() -> [RationalScalarBezierPatch] {
        let numeratorQuadrants = subdivided(controlNet: numerator)
        let weightQuadrants = subdivided(controlNet: weights)
        let uMiddle = uLower + (uUpper - uLower) * 0.5
        let vMiddle = vLower + (vUpper - vLower) * 0.5
        let bounds = [
            (uLower, uMiddle, vLower, vMiddle),
            (uMiddle, uUpper, vLower, vMiddle),
            (uLower, uMiddle, vMiddle, vUpper),
            (uMiddle, uUpper, vMiddle, vUpper),
        ]
        return bounds.indices.map { index in
            RationalScalarBezierPatch(
                numerator: numeratorQuadrants[index],
                weights: weightQuadrants[index],
                uLower: bounds[index].0,
                uUpper: bounds[index].1,
                vLower: bounds[index].2,
                vUpper: bounds[index].3
            )
        }
    }

    private func subdivided(controlNet: [[Double]]) -> [[[Double]]] {
        var uLowerRows: [[Double]] = []
        var uUpperRows: [[Double]] = []
        uLowerRows.reserveCapacity(controlNet.count)
        uUpperRows.reserveCapacity(controlNet.count)
        for row in controlNet {
            let halves = split(row)
            uLowerRows.append(halves.lower)
            uUpperRows.append(halves.upper)
        }
        let lowerUHalves = splitColumns(uLowerRows)
        let upperUHalves = splitColumns(uUpperRows)
        return [
            lowerUHalves.lower,
            upperUHalves.lower,
            lowerUHalves.upper,
            upperUHalves.upper,
        ]
    }

    private func splitColumns(_ controlNet: [[Double]]) -> (lower: [[Double]], upper: [[Double]]) {
        guard let columnCount = controlNet.first?.count else {
            return ([], [])
        }
        var lower = Array(
            repeating: Array(repeating: 0.0, count: columnCount),
            count: controlNet.count
        )
        var upper = lower
        for columnIndex in 0..<columnCount {
            let column = controlNet.map { $0[columnIndex] }
            let halves = split(column)
            for rowIndex in controlNet.indices {
                lower[rowIndex][columnIndex] = halves.lower[rowIndex]
                upper[rowIndex][columnIndex] = halves.upper[rowIndex]
            }
        }
        return (lower, upper)
    }

    private func split(_ values: [Double]) -> (lower: [Double], upper: [Double]) {
        guard values.count > 1 else {
            return (values, values)
        }
        var levels: [[Double]] = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                (previous[index] + previous[index + 1]) * 0.5
            })
        }
        let lower = levels.map { $0[0] }
        let upper = levels.reversed().map { $0[$0.count - 1] }
        return (lower, upper)
    }
}
