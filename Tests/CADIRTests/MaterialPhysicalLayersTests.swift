import CADCore
import Foundation
import Testing
@testable import CADIR

/// A material's physical layers round-trip, default to no effect and reject values out of range.
@Suite struct MaterialPhysicalLayersTests {
    private func plain() -> Material {
        Material(name: "Plain", baseColor: ColorRGBA(r: 0.2, g: 0.3, b: 0.4, a: 1), metallic: 0.1, roughness: 0.6, opacity: 1)
    }

    @Test func layersRoundTripAndOlderMaterialsDecodeWithoutEffect() throws {
        var material = plain()
        material.ior = 2.4
        material.clearcoat = 0.8
        material.sheenColor = ColorRGBA(r: 1, g: 0, b: 0, a: 1)
        material.iridescence = 0.5
        material.thickness = 0.002
        material.transmission = 0.9
        material.density = 7850
        try material.validate()
        let decoded = try JSONDecoder().decode(Material.self, from: JSONEncoder().encode(material))
        #expect(decoded == material)

        let original = plain()
        var legacy = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["ior", "clearcoat", "clearcoatRoughness", "sheen", "sheenColor", "sheenRoughness", "specularColor",
                    "specularIntensity", "iridescence", "iridescenceIOR", "thickness", "transmission", "density"] {
            legacy.removeValue(forKey: key)
        }
        let old = try JSONDecoder().decode(Material.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old == original)
        #expect(old.ior == 1.5)
        #expect(old.clearcoat == 0 && old.sheen == 0 && old.iridescence == 0 && old.transmission == 0)
        #expect(old.specularIntensity == 1)
        #expect(old.density == nil)
    }

    @Test func layersOutOfRangeAreRejected() {
        let edits: [(inout Material) -> Void] = [
            { $0.ior = 0.9 }, { $0.ior = 3.5 }, { $0.clearcoat = 1.2 }, { $0.sheenRoughness = -0.1 },
            { $0.specularColor = ColorRGBA(r: 2, g: 0, b: 0, a: 1) }, { $0.iridescenceIOR = .nan },
            { $0.thickness = -1 }, { $0.transmission = 1.5 }, { $0.density = 0 }, { $0.density = .infinity },
        ]
        for edit in edits {
            var material = plain()
            edit(&material)
            #expect(throws: MaterialError.self) { try material.validate() }
        }
    }
}
