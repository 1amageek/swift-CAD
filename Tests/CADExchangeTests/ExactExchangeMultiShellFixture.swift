import CADCore
import CADModeling
import CADTopology

enum ExactExchangeMultiShellFixture {
    static func disconnectedSheetBody() throws -> BRepModel {
        var model = try BRepModelCombiner().combined([
            try ExactExchangeAdvancedAnalyticFixture.tiltedCylindricalSheet(),
            try ExactExchangeAdvancedAnalyticFixture.ellipticalSheet(),
        ])
        let bodyIDs = model.bodies.keys.sorted()
        guard bodyIDs.count == 2 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: .standard,
                message: "The exact multi-shell fixture requires two source sheet bodies."
            )
        }
        var shellIDs: [ShellID] = []
        for bodyID in bodyIDs {
            guard let body = model.bodies[bodyID], body.kind == .sheet else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: .standard,
                    message: "The exact multi-shell fixture source must contain only sheet bodies."
                )
            }
            shellIDs.append(contentsOf: body.shellIDs)
            model.bodies[bodyID] = nil
        }
        let bodyID = bodyIDs[0]
        model.bodies[bodyID] = Body(id: bodyID, sheetShellIDs: shellIDs)
        try model.validate(level: .exact, tolerance: .standard)
        return model
    }
}
