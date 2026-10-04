/// Caller-owned bounds on one complete native position certification operation.
public struct NativeSurfacePositionCertificationLimits: Equatable, Sendable {
    public let maximumCertificationBoxes: Int
    public let maximumScalarCount: Int
    public let maximumWorkUnits: Int

    public static let standard = Self(maximumCertificationBoxes: 65_536,
        maximumScalarCount: 1_048_576, maximumWorkUnits: 16_777_216)

    public init(maximumCertificationBoxes: Int, maximumScalarCount: Int, maximumWorkUnits: Int) {
        self.maximumCertificationBoxes = maximumCertificationBoxes
        self.maximumScalarCount = maximumScalarCount
        self.maximumWorkUnits = maximumWorkUnits
    }

    func validate() throws {
        guard maximumCertificationBoxes > 0, maximumScalarCount > 0, maximumWorkUnits > 0 else {
            throw GeometryConversionError.invalidInput("Native position certification requires positive finite resource limits.")
        }
    }
}
