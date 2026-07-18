import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

struct EvaluationFixtureCombiner {
    static func combine(
        _ fixtures: [(brep: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage])]
    ) throws -> (brep: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage]) {
        let brep = try BRepModelCombiner().combined(fixtures.map(\.brep))
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var lineage: [SubshapeID: TopologyLineage] = [:]
        for fixture in fixtures {
            for (subshapeID, reference) in fixture.subshapes.entries {
                guard subshapes.updateValue(reference, forKey: subshapeID) == nil else {
                    throw KernelError(
                        phase: .validation,
                        code: .invalidInput,
                        subshapeID: subshapeID,
                        tolerance: .standard,
                        message: "Combined test fixture has a duplicate subshape ID."
                    )
                }
            }
            for (subshapeID, entry) in fixture.lineage {
                guard lineage.updateValue(entry, forKey: subshapeID) == nil else {
                    throw KernelError(
                        phase: .validation,
                        code: .invalidInput,
                        subshapeID: subshapeID,
                        tolerance: .standard,
                        message: "Combined test fixture has duplicate lineage."
                    )
                }
            }
        }
        return (brep, SubshapeIndex(subshapes), lineage)
    }
}
