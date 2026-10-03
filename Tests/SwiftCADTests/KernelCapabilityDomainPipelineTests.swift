import CADCore
import CADIR
import CADKernel
import CADTopology
import Foundation
import SwiftCAD
import Testing

@Suite("Capability domains through the public pipeline")
struct KernelCapabilityDomainPipelineTests {
    @Test(.timeLimit(.minutes(1)))
    func thePublishedObliqueDraftConditionMatchesRealEvaluation() throws {
        let pipeline = CADPipeline(tolerance: .standard)
        let domain = try pipeline.capabilities().domain(operation: "extrude")
        #expect(domain.capability.status == .partial)
        #expect(domain.limitations(affecting: .transformation).contains {
            $0.sourcePath.hasSuffix("ExactProfileExtrudeBodyBuilder.swift")
                && $0.condition.contains("oblique")
        })
        let oblique = try draftedDocument(direction: .vector(Vector3D(x: 1, y: 0, z: 1)))
        do {
            _ = try pipeline.evaluate(oblique)
            Issue.record("The published unimplemented oblique draft must be refused.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.category == .unsupportedDomain)
        }
        let normal = try draftedDocument(direction: .normal)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(normal)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let slope = tan(5 * Double.pi / 180)
        let expected = 0.02 * 0.01 * 0.01 - slope * (0.02 + 0.01) * 0.01 * 0.01
            + 4 * slope * slope * pow(0.01, 3) / 3
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expected) < 1.0e-12)
    }

    private func draftedDocument(direction: ExtrudeDirection) throws -> CADDocument {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) {
            $0.rectangle(
                width: .constant(.length(0.02, unit: .meter)),
                height: .constant(.length(0.01, unit: .meter))
            )
        }
        _ = try builder.extrude(
            profile, distance: .constant(.length(0.01, unit: .meter)),
            direction: direction, draftAngle: .constant(.angle(5, unit: .degree))
        )
        return try builder.build()
    }
}
