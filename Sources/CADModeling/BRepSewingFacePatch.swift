import CADCore
import CADGeometry
import CADIR
import CADTopology

/// One exact trimmed face patch in a sewing request.
public struct BRepSewingFacePatch: Sendable {
    public let stableID: String
    public let surface: Surface3D
    public let orientation: Orientation
    public let loops: [BRepSewingLoop]
    public let parentSubshapeIDs: [SubshapeID]

    public init(
        stableID: String,
        surface: Surface3D,
        orientation: Orientation,
        loops: [BRepSewingLoop],
        parentSubshapeIDs: [SubshapeID] = []
    ) {
        self.stableID = stableID
        self.surface = surface
        self.orientation = orientation
        self.loops = loops
        self.parentSubshapeIDs = Array(Set(parentSubshapeIDs)).sorted()
    }

    package init(
        stableID: String, surface: Surface3D, orientation: Orientation,
        loops: [BRepSewingLoop], parentSubshapeIDs: [SubshapeID] = [],
        using execution: inout OriginalQueryExecution
    ) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.consumeWork(1)
        self.stableID = stableID
        self.surface = surface
        self.orientation = orientation
        self.loops = loops
        self.parentSubshapeIDs = try AdmittedSewingProvenance.canonical(parentSubshapeIDs,
            using: &execution)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        do {
            try surface.validate(tolerance: tolerance, using: &execution)
} catch {
            throw contextualizedSewingFailure(error, tolerance: tolerance, context: execution.context,
                message: "Sewing face patch \(stableID) has an invalid support surface.")
        }
        try execution.consumeWork(loops.count)
        try execution.consumeWork(loops.count)
        try execution.consumeWork(parentSubshapeIDs.count)
        try execution.retainStorage(count: loops.count, stride: MemoryLayout<BRepSewingLoop>.stride)
        try execution.retainStorage(count: loops.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: loops.count, stride: MemoryLayout<String>.stride)
        guard stableID.isEmpty == false,
              loops.isEmpty == false,
              loops.filter({ $0.role == .outer }).count == 1,
              Set(loops.map { $0.stableID }).count == loops.count,
              parentSubshapeIDs.allSatisfy({ $0.isValid }) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing face patch requires one outer loop and valid stable provenance."
            )
        }
        for loop in loops {
            try execution.consumeWork(1)
            do {
                try loop.validate(on: surface, tolerance: tolerance, using: &execution)
            } catch {
                throw contextualizedSewingFailure(error, tolerance: tolerance,
                    context: execution.context, message: "Sewing face patch \(stableID) contains invalid loop \(loop.stableID).")
            }
        }
    }

    /// Admits the original patch value invariants with the composing caller's allowance.
    public func validate(tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int = 32,
        using execution: inout OriginalQueryExecution) throws {
        try OriginalSewingPatchValidator(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth).validate(self, tolerance: tolerance,
                using: &execution)
    }


}
