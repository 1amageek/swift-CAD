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

    func certifiedAxisAlignedZeroSegment() -> (first: Point2D, second: Point2D)? {
        guard numerator.isEmpty == false,
              let firstRow = numerator.first,
              firstRow.isEmpty == false else {
            return nil
        }
        let scale = max(
            1.0,
            numerator.flatMap { $0 }.map(abs).max() ?? 1.0
        )
        let coefficientTolerance = Double.ulpOfOne * scale * 4_096.0
        if let fraction = linearRootFraction(
            coefficients: numerator.map { $0[0] },
            repeatedValues: numerator,
            repeatedAlongRows: true,
            tolerance: coefficientTolerance
        ) {
            let v = vLower + (vUpper - vLower) * fraction
            return (
                Point2D(x: uLower, y: v),
                Point2D(x: uUpper, y: v)
            )
        }
        if let fraction = linearRootFraction(
            coefficients: firstRow,
            repeatedValues: numerator,
            repeatedAlongRows: false,
            tolerance: coefficientTolerance
        ) {
            let u = uLower + (uUpper - uLower) * fraction
            return (
                Point2D(x: u, y: vLower),
                Point2D(x: u, y: vUpper)
            )
        }
        return nil
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

    private func linearRootFraction(
        coefficients: [Double],
        repeatedValues: [[Double]],
        repeatedAlongRows: Bool,
        tolerance: Double
    ) -> Double? {
        guard coefficients.count >= 2,
              coefficients.allSatisfy(\.isFinite) else {
            return nil
        }
        if repeatedAlongRows {
            guard repeatedValues.allSatisfy({ row in
                guard let first = row.first else { return false }
                return row.allSatisfy { abs($0 - first) <= tolerance }
            }) else {
                return nil
            }
        } else {
            guard let firstRow = repeatedValues.first,
                  repeatedValues.allSatisfy({ row in
                      row.count == firstRow.count
                          && row.indices.allSatisfy {
                              abs(row[$0] - firstRow[$0]) <= tolerance
                          }
                  }) else {
                return nil
            }
        }
        let first = coefficients[0]
        let last = coefficients[coefficients.count - 1]
        let degree = Double(coefficients.count - 1)
        for index in coefficients.indices {
            let expected = first + (last - first) * Double(index) / degree
            guard abs(coefficients[index] - expected) <= tolerance else {
                return nil
            }
        }
        let slope = last - first
        guard abs(slope) > tolerance else { return nil }
        let root = -first / slope
        guard root.isFinite,
              root >= 0.0,
              root <= 1.0 else {
            return nil
        }
        return root
    }
}
