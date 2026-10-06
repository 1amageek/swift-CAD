import CADCore
import CADIR
import CADModeling
import CADTopology

/// Complete source-to-output correspondence with material shell and cavity boundary ownership.
public struct BooleanTopologyHistory: Sendable {
    public struct Component: Sendable {
        public let bodyID: BodyID
        public let outerShellID: ShellID
        public let voidShellIDs: [ShellID]
        public let outerBoundarySources: [SubshapeID]
        public let cavityBoundarySources: [ShellID: [SubshapeID]]
    }

    public let outputsBySource: [SubshapeID: [SubshapeID]]
    public let causalOutputsBySource: [SubshapeID: [SubshapeID]]
    public let generated: [SubshapeID]
    public let deleted: [SubshapeID]
    public let components: [Component]

    public init(result: EvaluationResult, inputSubshapes: [SubshapeID: TopologyReference],
                tolerance: ModelingTolerance) throws {
        var outputs: [SubshapeID: [SubshapeID]] = [:]
        var causal: [SubshapeID: [SubshapeID]] = [:]
        var generated: [SubshapeID] = []
        for id in result.subshapes.keys.sorted() {
            guard let output = result.subshapes[id], let history = result.lineage[id],
                  history.isStructurallyValid else {
                throw KernelError(phase: .topology, code: .topologyFailure, subshapeID: id,
                    tolerance: tolerance, message: "Boolean history requires valid lineage for every published subshape.")
            }
            var existingSource = false
            for parent in history.parents {
                causal[parent, default: []].append(id)
                if let input = inputSubshapes[parent], Self.sameDimension(input, output) {
                    outputs[parent, default: []].append(id)
                    existingSource = true
                }
            }
            if !existingSource { generated.append(id) }
        }
        outputsBySource = outputs.mapValues { Array(Set($0)).sorted() }
        causalOutputsBySource = causal.mapValues { Array(Set($0)).sorted() }
        self.generated = generated
        deleted = result.removedSubshapeIDs.filter { inputSubshapes[$0] != nil && outputs[$0] == nil }.sorted()
        var sourcesByFace: [FaceID: Set<SubshapeID>] = [:]
        for (id, reference) in result.subshapes {
            guard case let .face(faceID) = reference else { continue }
            sourcesByFace[faceID, default: []].formUnion(result.lineage[id]?.parents ?? [])
        }
        func boundarySources(_ shellID: ShellID) throws -> [SubshapeID] {
            guard let shell = result.brep.shells[shellID] else {
                throw TopologyError.missingReference("Boolean history material shell is missing.")
            }
            return Array(Set(shell.faceIDs.flatMap { Array(sourcesByFace[$0] ?? []) })).sorted()
        }
        var components: [Component] = []
        let resultBodies = Set(result.subshapes.values.compactMap { reference -> BodyID? in
            if case let .body(id) = reference { return id }; return nil
        })
        for bodyID in resultBodies.sorted() {
            guard let body = result.brep.bodies[bodyID] else {
                throw TopologyError.missingReference("Boolean history output body is missing.")
            }
            for component in body.solidComponents ?? [] {
                var cavities: [ShellID: [SubshapeID]] = [:]
                for shellID in component.voidShellIDs { cavities[shellID] = try boundarySources(shellID) }
                components.append(Component(bodyID: bodyID, outerShellID: component.outerShellID,
                    voidShellIDs: component.voidShellIDs,
                    outerBoundarySources: try boundarySources(component.outerShellID), cavityBoundarySources: cavities))
            }
        }
        self.components = components
    }

    private static func sameDimension(_ first: TopologyReference, _ second: TopologyReference) -> Bool {
        switch (first, second) {
        case (.body, .body), (.face, .face), (.edge, .edge), (.vertex, .vertex): true
        default: false
        }
    }
}
