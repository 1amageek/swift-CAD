import CADCore
import CADTopology

public struct DefaultFaceDeletionTopologyTransformer: FaceDeletionTopologyTransforming {
    private let repairer: any BRepRepairing

    public init(
        repairer: any BRepRepairing = DefaultBRepRepairer()
    ) {
        self.repairer = repairer
    }

    public func transformedModel(
        deleting faceIDs: Set<FaceID>,
        from bodyID: BodyID,
        featureID: FeatureID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BRepModel {
        guard faceIDs.isEmpty == false else {
            throw failure(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete requires at least one face target."
            )
        }
        guard var body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing Face Delete body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw failure(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete requires a solid target body."
            )
        }
        let targetBodyFaceIDs = try collectFaceIDs(in: body, model: model)
        guard faceIDs.isSubset(of: targetBodyFaceIDs) else {
            throw failure(
                .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                "Face delete target faces must all belong to the target body."
            )
        }

        var transformed = model
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        var remainingShells: [ShellID] = []
        for shellID in body.shellIDs {
            guard let shell = transformed.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            let remainingFaceIDs = shell.faceIDs.filter { faceIDs.contains($0) == false }
            guard remainingFaceIDs.isEmpty == false else {
                throw failure(
                    .invalidInput,
                    featureID: featureID,
                    tolerance: tolerance,
                    "Face delete must leave at least one face in every source shell."
                )
            }
            let components = try connectedFaceComponents(
                remainingFaceIDs,
                model: transformed
            )
            for (componentIndex, component) in components.enumerated() {
                let componentShellID = componentIndex == 0
                    ? shellID
                    : topologyIDs.nextShellID()
                transformed.shells[componentShellID] = Shell(
                    id: componentShellID,
                    faceIDs: component,
                    orientation: shell.orientation
                )
                remainingShells.append(componentShellID)
            }
        }

        for faceID in faceIDs.sorted() {
            guard transformed.faces.removeValue(forKey: faceID) != nil else {
                throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
            }
        }
        body.topology = .sheet(shellIDs: remainingShells)
        transformed.bodies[bodyID] = body

        let repair = try repairer.repair(
            transformed,
            request: BRepRepairRequest(
                actions: [.pruneUnreferencedTopology],
                validationRequest: BRepValidationRequest(scopes: [.references])
            ),
            tolerance: tolerance
        )
        return repair.model
    }

    private func connectedFaceComponents(
        _ faceIDs: [FaceID],
        model: BRepModel
    ) throws -> [[FaceID]] {
        let faceSet = Set(faceIDs)
        var edgeFaces: [EdgeID: [FaceID]] = [:]
        for faceID in faceIDs.sorted() {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Missing Face Delete face \(faceID).")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Missing Face Delete loop \(loopID).")
                }
                for coedge in loop.coedges {
                    edgeFaces[coedge.edgeID, default: []].append(faceID)
                }
            }
        }

        var adjacency: [FaceID: Set<FaceID>] = Dictionary(
            uniqueKeysWithValues: faceIDs.map { ($0, Set<FaceID>()) }
        )
        for incidentFaces in edgeFaces.values {
            let retainedFaces = incidentFaces.filter { faceSet.contains($0) }.sorted()
            for faceID in retainedFaces {
                adjacency[faceID, default: []].formUnion(retainedFaces.filter { $0 != faceID })
            }
        }

        var pending = faceSet
        var components: [[FaceID]] = []
        while let seed = pending.min() {
            var stack = [seed]
            var component = Set<FaceID>()
            pending.remove(seed)
            while let faceID = stack.popLast() {
                guard component.insert(faceID).inserted else { continue }
                let neighbors = adjacency[faceID, default: []]
                    .filter { pending.contains($0) }
                    .sorted(by: >)
                for neighbor in neighbors {
                    pending.remove(neighbor)
                    stack.append(neighbor)
                }
            }
            components.append(component.sorted())
        }
        return components.sorted { lhs, rhs in
            guard let left = lhs.first, let right = rhs.first else {
                return lhs.count < rhs.count
            }
            return left < right
        }
    }

    private func collectFaceIDs(
        in body: Body,
        model: BRepModel
    ) throws -> Set<FaceID> {
        var result: Set<FaceID> = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing Face Delete shell \(shellID).")
            }
            result.formUnion(shell.faceIDs)
        }
        return result
    }

    private func failure(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
