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
        consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?
    ) throws {
        try Task.checkCancellation()
        try consumeWork(0)
        self.stableID = stableID
        self.surface = surface
        self.orientation = orientation
        self.loops = loops
        self.parentSubshapeIDs = try AdmittedSewingProvenance.canonical(parentSubshapeIDs,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        do {
            try surface.validate(tolerance: tolerance)
        } catch {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Sewing face patch \(stableID) has an invalid support surface. \(error)"
            )
        }
        guard stableID.isEmpty == false,
              loops.isEmpty == false,
              loops.filter({ $0.role == .outer }).count == 1,
              Set(loops.map(\.stableID)).count == loops.count,
              parentSubshapeIDs.allSatisfy(\.isValid) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing face patch requires one outer loop and valid stable provenance."
            )
        }
        for loop in loops {
            do {
                try loop.validate(on: surface, tolerance: tolerance)
            } catch let error as KernelError {
                throw KernelError(
                    phase: error.phase,
                    code: error.code,
                    residual: error.residual,
                    tolerance: tolerance,
                    message: "Sewing face patch \(stableID) contains invalid loop \(loop.stableID). \(error.message)"
                )
            } catch {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Sewing face patch \(stableID) contains invalid loop \(loop.stableID). \(error)"
                )
            }
        }
    }

    /// Admits the original patch value invariants with the composing caller's allowance.
    public func validate(tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int = 32,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil) throws {
        try OriginalSewingPatchValidator(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage).validate(self, tolerance: tolerance)
    }
}
