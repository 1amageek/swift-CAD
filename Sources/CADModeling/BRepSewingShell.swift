import CADCore
import CADIR
import CADTopology

/// One oriented shell in a sewing request.
public struct BRepSewingShell: Sendable {
    public let stableID: String
    public let patches: [BRepSewingFacePatch]
    public let orientation: Orientation

    public init(
        stableID: String,
        patches: [BRepSewingFacePatch],
        orientation: Orientation = .forward
    ) {
        self.stableID = stableID
        self.patches = patches
        self.orientation = orientation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        guard stableID.isEmpty == false,
              patches.isEmpty == false,
              Set(patches.map(\.stableID)).count == patches.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep sewing shell requires uniquely identified face patches."
            )
        }
        for patch in patches {
            try patch.validate(tolerance: tolerance)
        }
    }
}
