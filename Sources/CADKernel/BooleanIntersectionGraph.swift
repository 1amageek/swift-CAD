import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections

public struct BooleanIntersectionGraph: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(in: model, tolerance: tolerance, using: &execution)
    }

    public func validate(in model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
      do {
        try execution.consumeWork(1)
        try tolerance.validate()
        var candidates: Set<BooleanFacePairCandidate> = []
        for pair in facePairs {
            try execution.consumeWork(1)
            guard try OriginalParameterQueryStorage.insert(pair, in: &candidates, using: &execution) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean intersection graph contains duplicate face-pair candidates."
            )
            }
        }
        for intersection in faceIntersections {
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            switch intersection.geometry {
            case let .curve(value):
                residual = value.maximumResidual
            case let .point(value):
                residual = value.residual
            // FIXME(INCOMPLETE_IMPLEMENTATION): Boolean material clipping must
            // consume the original source/UV relation before symbolic SSI can
            // enter its numeric residual validator. No complete Boolean claim
            // is valid from this representation gate alone.
            case .originalCoaxial, .originalBoundedSphereCone, .originalFullSphereCone, .originalFullConeCone, .originalApexSphereCone, .originalCommonApexCone, .originalCoincidentCone:
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Boolean material clipping requires the original symbolic source relation.")
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
            try execution.consumeWork(1)
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
                tolerance: tolerance,
                using: &execution
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Boolean boundary contact edge does not belong to its curve-owning face."
                )
            }
            if case let .points(intersections) = contact.geometry {
                var valid = intersections.isEmpty == false
                var maximumResidual: Double?
                for intersection in intersections {
                    try execution.consumeWork(1)
                    valid = valid && intersection.residual <= tolerance.distance
                    maximumResidual = max(maximumResidual ?? intersection.residual,
                        intersection.residual)
                }
                guard valid else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        residual: maximumResidual,
                        tolerance: tolerance,
                        message: "Boolean boundary contact failed residual verification."
                    )
                }
            }
        }

      } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
    }

    private func face(
        _ faceID: FaceID,
        contains edgeID: EdgeID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        guard let face = model.faces[faceID] else { return false }
        for loopID in face.loops {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean intersection graph found a missing face loop."
                )
            }
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                if coedge.edgeID == edgeID { return true }
            }
        }
        return false
    }
}

#if !hasFeature(Embedded)
extension BooleanIntersectionGraph: Codable {}
#endif
