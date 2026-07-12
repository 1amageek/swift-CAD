import Foundation
import CADCore
import CADIR
import CADKernel
import SwiftCAD
import Testing

struct CADCommandPipelineTests {
    @Test
    func pipelineExposesSharedCapabilitiesAndQueries() throws {
        let pipeline = CADPipeline()
        let catalog = pipeline.capabilities()
        try catalog.validate()
        #expect(catalog.capability(id: "API-PARITY-001") != nil)

        let query = KernelQuery.lineage(
            SubshapeID(featureID: FeatureID(), role: "face", ordinal: 0)
        )
        let encoded = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(KernelQuery.self, from: encoded) == query)
    }

    @Test
    func builderUsesCommandApplierForFeatureInsertion() throws {
        let document = try CADDocument.millimeters(named: "Command path") { builder in
            let profile = try builder.sketch(on: .xy) { sketch in
                sketch.rectangle(
                    width: .constant(.length(10.0, unit: .millimeter)),
                    height: .constant(.length(5.0, unit: .millimeter))
                )
            }
            try builder.extrude(
                profile,
                distance: .constant(.length(2.0, unit: .millimeter))
            )
        }
        #expect(document.designGraph.order.count == 2)
        #expect(document.designGraph.dependencies.count == 1)
    }
}
