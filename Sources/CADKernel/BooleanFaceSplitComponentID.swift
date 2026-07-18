import CADCore

public struct BooleanFaceSplitComponentID: Codable, Hashable, Sendable, Comparable {
    public let ordinal: Int

    public init(ordinal: Int) {
        self.ordinal = ordinal
    }

    public static func < (
        lhs: BooleanFaceSplitComponentID,
        rhs: BooleanFaceSplitComponentID
    ) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    public func validate(tolerance: ModelingTolerance) throws {
        guard ordinal >= 0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean split component ordinal must be nonnegative."
            )
        }
    }
}
