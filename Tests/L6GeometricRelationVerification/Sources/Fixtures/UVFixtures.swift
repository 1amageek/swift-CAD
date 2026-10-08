import L0
import L1
import L2
import L3
import L4
import L5
import L6

public enum UVFixtures {
    public static func verify() throws {
        typealias G = GeometryFixtures
        var setup = try G.ledger()
        let cs = try G.relation(cs: true, mode: 2, &setup), f = try G.field(of: cs, &setup)
        let zero = try f.integer(0, using: &setup), half = try f.dividing(f.integer(1, using: &setup), f.integer(2, using: &setup), using: &setup)
        let uv = ExactUV<G.B>(field: f, u: half, v: zero)
        var query = try G.ledger()
        let csFiber = try G.geometry.fiber(at: .secondSurfaceUV(uv), in: cs, limits: G.limits(), using: &query)
        try GeometricFailureFixtures.require(csFiber.components.count == 1 && csFiber.selection.cells.allSatisfy { $0.dimension == 0 })
        var invalid = false
        do { _ = try G.geometry.fiber(at: .firstSurfaceUV(uv), in: cs, limits: G.limits(), using: &query) }
        catch ExactGeometricRelationFailure.invalidStation { invalid = true }
        try GeometricFailureFixtures.require(invalid)
        var foldedSetup = try G.ledger()
        let ssi = try G.relation(cs: false, mode: 3, &foldedSetup), g = try G.field(of: ssi, &foldedSetup)
        let station = ExactUV<G.B>(field: g, u: try g.integer(1, using: &foldedSetup), v: try g.integer(0, using: &foldedSetup))
        for first in [true, false] {
            var a = try G.ledger()
            let fiber = try G.geometry.fiber(at: first ? .firstSurfaceUV(station) : .secondSurfaceUV(station),
                in: ssi, limits: G.limits(), using: &a)
            try GeometricFailureFixtures.require(fiber.components.count == 2 && fiber.selection.cells.allSatisfy { $0.dimension == 0 })
        }
        print("PASS: CS reciprocal UV and both SSI UV stations retain separate exact roots")
    }
}
