import CADUSD
import Foundation

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

    static func rotationX(angleInDegrees angle: Double) throws -> USDCMatrix4x4 {
        let radians = try radians(fromDegrees: angle)
        let sine = sin(radians)
        let cosine = cos(radians)
        return USDCMatrix4x4(values: [
            1, 0, 0, 0,
            0, cosine, sine, 0,
            0, -sine, cosine, 0,
            0, 0, 0, 1,
        ])
    }

    static func rotationY(angleInDegrees angle: Double) throws -> USDCMatrix4x4 {
        let radians = try radians(fromDegrees: angle)
        let sine = sin(radians)
        let cosine = cos(radians)
        return USDCMatrix4x4(values: [
            cosine, 0, -sine, 0,
            0, 1, 0, 0,
            sine, 0, cosine, 0,
            0, 0, 0, 1,
        ])
    }

    static func rotationZ(angleInDegrees angle: Double) throws -> USDCMatrix4x4 {
        let radians = try radians(fromDegrees: angle)
        let sine = sin(radians)
        let cosine = cos(radians)
        return USDCMatrix4x4(values: [
            cosine, sine, 0, 0,
            -sine, cosine, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    static func eulerRotation(order: String, anglesInDegrees angles: USDCVector3D) throws -> USDCMatrix4x4 {
        var transform = USDCMatrix4x4.identity
        for axis in order {
            let axisTransform: USDCMatrix4x4
            switch axis {
            case "X":
                axisTransform = try rotationX(angleInDegrees: angles.x)
            case "Y":
                axisTransform = try rotationY(angleInDegrees: angles.y)
            case "Z":
                axisTransform = try rotationZ(angleInDegrees: angles.z)
            default:
                throw USDImportError.invalidData("USDC Euler rotation order is malformed.")
            }
            transform = transform.concatenating(axisTransform)
        }
        return transform
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

    func transformNormal(_ normal: USDPoint3D) throws -> USDPoint3D {
        guard values[3] == 0, values[7] == 0, values[11] == 0 else {
            throw USDImportError.unsupportedFeature("USDC normal transforms require affine matrices.")
        }
        let m00 = values[0]
        let m01 = values[1]
        let m02 = values[2]
        let m10 = values[4]
        let m11 = values[5]
        let m12 = values[6]
        let m20 = values[8]
        let m21 = values[9]
        let m22 = values[10]
        let determinant =
            m00 * (m11 * m22 - m12 * m21) -
            m01 * (m10 * m22 - m12 * m20) +
            m02 * (m10 * m21 - m11 * m20)
        guard determinant.isFinite, determinant != 0 else {
            throw USDImportError.invalidData("USDC normal transform is singular.")
        }

        let inverse00 = (m11 * m22 - m12 * m21) / determinant
        let inverse01 = (m02 * m21 - m01 * m22) / determinant
        let inverse02 = (m01 * m12 - m02 * m11) / determinant
        let inverse10 = (m12 * m20 - m10 * m22) / determinant
        let inverse11 = (m00 * m22 - m02 * m20) / determinant
        let inverse12 = (m02 * m10 - m00 * m12) / determinant
        let inverse20 = (m10 * m21 - m11 * m20) / determinant
        let inverse21 = (m01 * m20 - m00 * m21) / determinant
        let inverse22 = (m00 * m11 - m01 * m10) / determinant

        let x = inverse00 * normal.x + inverse01 * normal.y + inverse02 * normal.z
        let y = inverse10 * normal.x + inverse11 * normal.y + inverse12 * normal.z
        let z = inverse20 * normal.x + inverse21 * normal.y + inverse22 * normal.z
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw USDImportError.invalidData("USDC transform produced a non-finite normal.")
        }
        let length = sqrt(x * x + y * y + z * z)
        guard length.isFinite, length > 0 else {
            throw USDImportError.invalidData("USDC transform produced a zero-length normal.")
        }
        return USDPoint3D(x: x / length, y: y / length, z: z / length)
    }

    private static func radians(fromDegrees angle: Double) throws -> Double {
        guard angle.isFinite else {
            throw USDImportError.invalidData("USDC rotation angle is not finite.")
        }
        return angle * .pi / 180
    }
}
