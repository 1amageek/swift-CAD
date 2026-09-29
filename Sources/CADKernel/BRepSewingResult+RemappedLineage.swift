import CADCore
import CADIR
import CADModeling
import CADTopology

extension BRepSewingResult {
    /// The sewer's lineage carried over to the identities `builtSubshapes` publish for the same
    /// topology, keeping only entries with parents.
    func lineage(remappedTo builtSubshapes: [SubshapeID: TopologyReference]) -> [SubshapeID: TopologyLineage] {
        let sewnIdentityByReference = Dictionary(
            subshapes.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        return Dictionary(uniqueKeysWithValues: builtSubshapes.compactMap { output, reference in
            guard let sewnIdentity = sewnIdentityByReference[reference],
                  let lineage = lineage[sewnIdentity],
                  lineage.parents.isEmpty == false else {
                return nil
            }
            return (output, TopologyLineage(output: output, parents: lineage.parents, relation: lineage.relation))
        })
    }
}
