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

enum SmallLinearSystem4 {
    static func solve(matrix: [[Double]], rightHandSide: [Double], admission: SurfaceSurfaceQueryAdmission) throws -> [Double]? {
        guard matrix.count == 4,
              matrix.allSatisfy({ $0.count == 4 }),
              rightHandSide.count == 4 else {
            return nil
        }
        try admission.reserve(count: 20, stride: MemoryLayout<Double>.stride)
        try admission.reserve(count: 4, stride: MemoryLayout<Array<Double>>.stride)
        var augmented: [[Double]] = []
        augmented.reserveCapacity(4)
        for row in 0..<4 {
            try admission.step()
            var values = matrix[row]
            values.reserveCapacity(5)
            values.append(rightHandSide[row])
            augmented.append(values)
        }
        for column in 0..<4 {
            try admission.step()
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
                try admission.step()
                let factor = augmented[row][column]
                for index in column..<5 {
                    augmented[row][index] -= factor * augmented[column][index]
                }
            }
        }
        try admission.reserve(count: 4, stride: MemoryLayout<Double>.stride)
        let result = augmented.map { $0[4] }
        return result.allSatisfy({ $0.isFinite }) ? result : nil
    }

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
        return result.allSatisfy({ $0.isFinite }) ? result : nil
    }
}
