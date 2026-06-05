import CADUSD

struct USDCMatrix4x4: Sendable, Equatable {
    var values: [Double]

    init(values: [Double]) {
        precondition(values.count == 16)
        self.values = values
    }

    static var identity: USDCMatrix4x4 {
        USDCMatrix4x4(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    static func translation(_ vector: USDCVector3D) -> USDCMatrix4x4 {
        USDCMatrix4x4(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            vector.x, vector.y, vector.z, 1,
        ])
    }

    static func scale(_ vector: USDCVector3D) -> USDCMatrix4x4 {
        USDCMatrix4x4(values: [
            vector.x, 0, 0, 0,
            0, vector.y, 0, 0,
            0, 0, vector.z, 0,
            0, 0, 0, 1,
        ])
    }

    func concatenating(_ rhs: USDCMatrix4x4) -> USDCMatrix4x4 {
        var output = [Double](repeating: 0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                var value = 0.0
                for index in 0..<4 {
                    value += values[row * 4 + index] * rhs.values[index * 4 + column]
                }
                output[row * 4 + column] = value
            }
        }
        return USDCMatrix4x4(values: output)
    }

    func transform(_ point: USDPoint3D) throws -> USDPoint3D {
        let x = point.x * values[0] + point.y * values[4] + point.z * values[8] + values[12]
        let y = point.x * values[1] + point.y * values[5] + point.z * values[9] + values[13]
        let z = point.x * values[2] + point.y * values[6] + point.z * values[10] + values[14]
        let w = point.x * values[3] + point.y * values[7] + point.z * values[11] + values[15]
        guard x.isFinite, y.isFinite, z.isFinite, w.isFinite else {
            throw USDImportError.invalidData("USDC transform produced a non-finite point.")
        }
        guard w != 0 else {
            throw USDImportError.invalidData("USDC transform produced a point with zero homogeneous weight.")
        }
        return USDPoint3D(x: x / w, y: y / w, z: z / w)
    }
}
