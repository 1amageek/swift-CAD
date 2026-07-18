import Foundation

enum SmallLinearSystem4 {
    static func solve(matrix: [[Double]], rightHandSide: [Double]) -> [Double]? {
        guard matrix.count == 4,
              matrix.allSatisfy({ $0.count == 4 }),
              rightHandSide.count == 4 else {
            return nil
        }
        var augmented = matrix.indices.map { row in
            matrix[row] + [rightHandSide[row]]
        }
        for column in 0..<4 {
            guard let pivotRow = (column..<4).max(by: {
                abs(augmented[$0][column]) < abs(augmented[$1][column])
            }), abs(augmented[pivotRow][column]) > 1.0e-14 else {
                return nil
            }
            if pivotRow != column {
                augmented.swapAt(pivotRow, column)
            }
            let pivot = augmented[column][column]
            for index in column..<5 {
                augmented[column][index] /= pivot
            }
            for row in 0..<4 where row != column {
                let factor = augmented[row][column]
                for index in column..<5 {
                    augmented[row][index] -= factor * augmented[column][index]
                }
            }
        }
        let result = augmented.map { $0[4] }
        return result.allSatisfy(\.isFinite) ? result : nil
    }
}
