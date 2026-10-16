import CADCore
import CADGeometry
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
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.consumeWork(patches.count)
        try execution.retainStorage(count: patches.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: patches.count, stride: MemoryLayout<String>.stride)
        guard stableID.isEmpty == false,
              patches.isEmpty == false,
              Set(patches.map { $0.stableID }).count == patches.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep sewing shell requires uniquely identified face patches."
            )
        }
        for patch in patches {
            try execution.consumeWork(1)
            do {
                try patch.validate(tolerance: tolerance, using: &execution)
            } catch {
                throw contextualizedSewingFailure(error, tolerance: tolerance,
                    context: execution.context, message: "B-rep sewing shell \(stableID) contains invalid patch \(patch.stableID).")
            }
        }
    }


}
