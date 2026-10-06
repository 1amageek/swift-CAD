import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel
import SwiftCAD

/// Reblend source records intent; unsupported geometry must fail before Wrap publishes a body.
@Suite("Wrap Reblend request admission")
struct WrapReblendRequestAdmissionTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func reblendBooleanRoundTripsAndCopiesIndependently(requested: Bool) throws {
        let original = WrapOptions(reblends: requested)
        let encoded = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let fields = try #require(object as? [String: Any])
        #expect(fields["reblends"] as? Bool == requested)
        let decoded = try JSONDecoder().decode(WrapOptions.self, from: encoded)
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
        var copy = decoded
        copy.reblends.toggle()
        #expect(original.reblends == requested)
        #expect(copy.reblends != original.reblends)
    }

    @Test(.timeLimit(.minutes(1)))
    func earlierOptionsWithoutReblendDefaultToFalse() throws {
        let original = WrapOptions(scaleU: 2, offsetV: 0.125, mirrors: true)
        #expect(!original.reblends)
        let encoded = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: encoded)
        var fields = try #require(object as? [String: Any])
        fields.removeValue(forKey: "reblends")
        let legacy = try JSONSerialization.data(withJSONObject: fields)
        #expect(try JSONDecoder().decode(WrapOptions.self, from: legacy) == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedReblendBooleanIsNotSilentlyIgnored() throws {
        let encoded = try JSONEncoder().encode(WrapOptions())
        let object = try JSONSerialization.jsonObject(with: encoded)
        let original = try #require(object as? [String: Any])
        let invalidValues: [Any] = ["true", 1, [Bool]()]
        for invalid in invalidValues {
            var fields = original
            fields["reblends"] = invalid
            let malformed = try JSONSerialization.data(withJSONObject: fields)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(WrapOptions.self, from: malformed)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func publicReblendRequestFailsWithItsFeatureIDAndPreservesSource() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let sheet = try builder.bSplineSurface(BSplineSurface3D(
            uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [
                [Point3D(x: 0, y: 0, z: 0), Point3D(x: 0.02, y: 0, z: 0)],
                [Point3D(x: 0, y: 0.03, z: 0), Point3D(x: 0.02, y: 0.03, z: 0)],
            ]
        ))
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let source = try builder.build(name: "Reblend request source")
        let sourceCopy = source
        let evaluated = try evaluator.evaluate(source)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        let originalBRep = evaluated.brep
        let faceID = try #require(evaluated.subshapes.entries.keys.sorted().first { id in
            guard id.featureID == sheet, case .face? = evaluated.subshapes[id] else { return false }
            return true
        })
        let face = try builder.stableSubshape(faceID)
        let requestedFeatureID = try builder.wrap(sheet, from: face, onto: face, options: WrapOptions(reblends: true))
        let requested = try builder.build(name: "Reblend request")
        let restored = try JSONDecoder().decode(CADDocument.self, from: JSONEncoder().encode(requested))
        #expect(restored == requested)
        let restoredNode = try #require(restored.designGraph.nodes[requestedFeatureID])
        guard case let .wrap(restoredWrap) = restoredNode.operation else {
            Issue.record("The restored request must retain its Wrap operation.")
            return
        }
        #expect(restoredWrap.options.reblends)
        do {
            _ = try evaluator.evaluate(restored)
            Issue.record("A Reblend request must not publish ordinary deformed rounds as recomputed rounds.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.category == .unsupportedDomain)
            #expect(error.featureID == requestedFeatureID)
            #expect(error.phase == .evaluation)
        }
        #expect(source == sourceCopy)
        #expect(evaluated.document == source)
        #expect(evaluated.brep == originalBRep)
        let preserved = try evaluator.evaluate(source)
        try preserved.brep.validate(level: .exact, tolerance: .standard)
        #expect(preserved.brep.bodies.count == 1)
        #expect(preserved.brep.faces.count == 1)
    }
}
