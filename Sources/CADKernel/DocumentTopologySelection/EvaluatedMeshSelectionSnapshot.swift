import CADCore
import CADIR
import CADTopology

/// Immutable provenance retained with the mesh mounted by a display consumer.
public struct EvaluatedMeshSelectionSnapshot: Sendable {
    public let bodyID: BodyID
    public let sourceDocument: CADDocument
    private let brep: BRepModel
    private let mesh: Mesh
    private let configuration: DocumentEvaluationConfiguration
    private let subshapeEntries: [SubshapeID: TopologyReference]

    public init(bodyID: BodyID, evaluated: EvaluatedDocument) throws {
        let tolerance = evaluated.configuration.tolerance
        try CurrentTaskCancellationChecker().checkCancellation()
        guard let body = evaluated.brep.bodies[bodyID], let mesh = evaluated.meshes[bodyID] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: tolerance,
                              message: "Mesh selection requires its evaluated body and actual mesh.")
        }
        try mesh.validate(tolerance: tolerance)
        var ownedFaces = Set<FaceID>()
        for shellID in body.shellIDs {
            guard let shell = evaluated.brep.shells[shellID] else {
                throw TopologyError.missingReference("Mesh selection body shell is absent.")
            }
            for faceID in shell.faceIDs {
                try CurrentTaskCancellationChecker().checkCancellation()
                guard evaluated.brep.faces[faceID] != nil else {
                    throw TopologyError.missingReference("Mesh selection body face is absent.")
                }
                ownedFaces.insert(faceID)
            }
        }
        guard !mesh.faceRuns.isEmpty,
              mesh.faceRuns.allSatisfy({ ownedFaces.contains($0.faceID) }) else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                              message: "Mesh selection requires complete current body-owned face runs.")
        }
        self.bodyID = bodyID
        self.sourceDocument = evaluated.document
        self.brep = evaluated.brep
        self.mesh = mesh
        self.configuration = evaluated.configuration
        self.subshapeEntries = evaluated.subshapes.entries
    }

    public func validateCurrent(_ current: EvaluatedDocument) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard current.document == sourceDocument, current.configuration == configuration,
              current.brep == brep, current.meshes[bodyID] == mesh,
              current.subshapes.entries == subshapeEntries else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance,
                message: "A display mesh selection belongs to a different evaluated snapshot.")
        }
    }

    public func faceID(forTriangle triangle: Int, in current: EvaluatedDocument) throws -> FaceID {
        try CurrentTaskCancellationChecker().checkCancellation()
        try validateCurrent(current)
        guard triangle >= 0, triangle < mesh.indices.count / 3 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: configuration.tolerance,
                              message: "Mesh selection triangle is outside the retained mesh.")
        }
        var start = 0
        for run in mesh.faceRuns {
            try CurrentTaskCancellationChecker().checkCancellation()
            let end = start.addingReportingOverflow(run.triangleCount)
            guard !end.overflow, run.triangleCount > 0 else {
                throw KernelError(phase: .topology, code: .invalidInput, tolerance: configuration.tolerance,
                                  message: "Mesh selection face-run arithmetic is invalid.")
            }
            if triangle < end.partialValue { return run.faceID }
            start = end.partialValue
        }
        throw KernelError(phase: .topology, code: .missingReference, tolerance: configuration.tolerance,
                          message: "The retained mesh has no face owner for the selected triangle.")
    }

    public func subshapeID(forTriangle triangle: Int, in current: EvaluatedDocument) throws -> SubshapeID {
        let face = try faceID(forTriangle: triangle, in: current)
        var result: SubshapeID?
        for (id, reference) in subshapeEntries where reference == .face(face) {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard result == nil else {
                throw KernelError(phase: .evaluation, code: .ambiguousSelection,
                    tolerance: configuration.tolerance, message: "The selected face has multiple live subshape identities.")
            }
            result = id
        }
        guard let result else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance, message: "The selected face has no persistent subshape identity.")
        }
        return result
    }
}
