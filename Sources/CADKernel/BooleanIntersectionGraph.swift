import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BooleanIntersectionGraph: Codable, Hashable, Sendable {
    public let facePairs: [BooleanFacePairCandidate]
    public let boundaryContacts: [BooleanBoundaryContact]
    public let faceIntersections: [BooleanFaceSurfaceIntersection]

    public init(
        facePairs: [BooleanFacePairCandidate],
        boundaryContacts: [BooleanBoundaryContact],
        faceIntersections: [BooleanFaceSurfaceIntersection]
    ) {
        self.facePairs = facePairs
        self.boundaryContacts = boundaryContacts
        self.faceIntersections = faceIntersections
    }

    public func validate(in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard Set(facePairs).count == facePairs.count else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean intersection graph contains duplicate face-pair candidates."
            )
        }
        let candidates = Set(facePairs)
        for intersection in faceIntersections {
            guard candidates.contains(intersection.facePair),
                  model.faces[intersection.facePair.targetFaceID] != nil,
                  model.faces[intersection.facePair.toolFaceID] != nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean face intersection does not belong to a valid broad-phase pair."
                )
            }
            let residual: Double
            switch intersection.geometry {
            case let .curve(value):
                residual = value.maximumResidual
            case let .point(value):
                residual = value.residual
            case let .coincident(value):
                residual = value.residual
            }
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Boolean face intersection failed residual verification."
                )
            }
        }
        for contact in boundaryContacts {
            guard model.edges[contact.edgeID] != nil,
                  model.faces[contact.curveFaceID] != nil,
                  model.faces[contact.surfaceFaceID] != nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean intersection graph references missing topology."
                )
            }
            let candidate = BooleanFacePairCandidate(
                targetFaceID: contact.curveFaceID,
                toolFaceID: contact.surfaceFaceID
            )
            let reversedCandidate = BooleanFacePairCandidate(
                targetFaceID: contact.surfaceFaceID,
                toolFaceID: contact.curveFaceID
            )
            guard candidates.contains(candidate) || candidates.contains(reversedCandidate) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Boolean boundary contact does not belong to a broad-phase face pair."
                )
            }
            guard try face(
                contact.curveFaceID,
                contains: contact.edgeID,
                in: model,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Boolean boundary contact edge does not belong to its curve-owning face."
                )
            }
            if case let .points(intersections) = contact.geometry {
                guard intersections.isEmpty == false,
                      intersections.allSatisfy({ $0.residual <= tolerance.distance }) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        residual: intersections.map(\.residual).max(),
                        tolerance: tolerance,
                        message: "Boolean boundary contact failed residual verification."
                    )
                }
            }
        }
    }

    private func face(
        _ faceID: FaceID,
        contains edgeID: EdgeID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let face = model.faces[faceID] else { return false }
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean intersection graph found a missing face loop."
                )
            }
            if loop.coedges.contains(where: { $0.edgeID == edgeID }) {
                return true
            }
        }
        return false
    }
}
