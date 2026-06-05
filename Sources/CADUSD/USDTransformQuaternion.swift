struct USDTransformQuaternion: Sendable, Equatable {
    var real: Double
    var imaginaryX: Double
    var imaginaryY: Double
    var imaginaryZ: Double

    init(real: Double, imaginaryX: Double, imaginaryY: Double, imaginaryZ: Double) {
        self.real = real
        self.imaginaryX = imaginaryX
        self.imaginaryY = imaginaryY
        self.imaginaryZ = imaginaryZ
    }

    func rotationMatrix() throws -> USDTransformMatrix4x4 {
        guard real.isFinite, imaginaryX.isFinite, imaginaryY.isFinite, imaginaryZ.isFinite else {
            throw USDImportError.invalidData("USDA quaternion contains a non-finite component.")
        }
        let normSquared = real * real
            + imaginaryX * imaginaryX
            + imaginaryY * imaginaryY
            + imaginaryZ * imaginaryZ
        guard normSquared.isFinite else {
            throw USDImportError.invalidData("USDA quaternion norm is not finite.")
        }
        guard normSquared > 0 else {
            return .identity
        }
        let inverseNorm = 1 / normSquared.squareRoot()
        let w = real * inverseNorm
        let x = imaginaryX * inverseNorm
        let y = imaginaryY * inverseNorm
        let z = imaginaryZ * inverseNorm
        return USDTransformMatrix4x4(values: [
            1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0,
            2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0,
            2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0,
            0, 0, 0, 1,
        ])
    }
}
