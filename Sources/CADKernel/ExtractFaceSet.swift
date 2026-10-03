import CADCore
import CADIR
import CADModeling
import CADTopology

/// Chosen faces of one body, by the shell each lies on: what an extraction of faces copies, and
/// whether they close, which on a manifold body is exactly when they are every face of each
/// shell they lie on.
struct ExtractFaceSet {
    /// The chosen faces of each shell they lie on, shells in the body's order.
    let facesByShell: [(shellIndex: Int, shellID: ShellID, faceIndices: Set<Int>)]

    init(
        references: [StableSubshapeReference],
        body: Body,
        model: BRepModel,
        subshapes: SubshapeIndex,
        lineage: [SubshapeID: TopologyLineage],
        resolver: any StableSubshapeResolving,
        tolerance: ModelingTolerance
    ) throws {
        var chosen: [Int: Set<Int>] = [:]
        for reference in references {
            let topology = try resolver.topologyReference(
                for: reference, model: model, subshapes: subshapes, lineage: lineage, tolerance: tolerance
            )
            guard case let .face(faceID) = topology,
                  let shellIndex = body.shellIDs.firstIndex(where: { model.shells[$0]?.faceIDs.contains(faceID) == true }),
                  let faceIndex = model.shells[body.shellIDs[shellIndex]]?.faceIDs.firstIndex(of: faceID) else {
                throw KernelError(phase: .evaluation, code: .missingReference, tolerance: tolerance,
                    message: "An extracted face is not a face of the source body.")
            }
            guard chosen[shellIndex, default: []].insert(faceIndex).inserted else {
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                    message: "Extracted faces resolve to the same face.")
            }
        }
        facesByShell = chosen.keys.sorted().map { ($0, body.shellIDs[$0], chosen[$0] ?? []) }
    }

    /// The stable identities the face-patch extractor gives the chosen faces.
    var patchStableIDs: Set<String> {
        Set(facesByShell.flatMap { entry in entry.faceIndices.map { "shell:\(entry.shellIndex):face:\($0)" } })
    }

    /// Whether every shell a chosen face lies on is chosen whole, on a solid body, whose shells
    /// are closed: the faces close into a solid.
    func closes(body: Body, model: BRepModel) -> Bool {
        guard body.kind == .solid else { return false }
        return facesByShell.allSatisfy { entry in
            entry.faceIndices.count == model.shells[entry.shellID]?.faceIDs.count
        }
    }
}
