import L0
import L1
import L2
import L3
import L4
import L5
import L6
import L6Fixtures

@main struct L6Proof {
    static func main() throws { try run() }
    nonisolated static func run() throws {
        typealias G = GeometryFixtures
        for cs in [true, false] {
            for mode in 0...6 {
                var a = try G.ledger()
                let raw = try G.original(cs: cs, mode: mode, &a)
                let beforeWork = a.work, beforeBytes = a.storageBytes
                let r = try G.geometry.resolve(raw, limits: G.limits(), using: &a)
                try GeometricFailureFixtures.require(r.isEmpty == (mode == 5))
                if cs && (mode == 2 || mode == 4 || mode == 6) {
                    try GeometricFailureFixtures.require(r.strata.contains { $0.imageDimension == 1 })
                }
                if !cs && mode == 6 {
                    try GeometricFailureFixtures.require(r.evidenceKind == .originalGraph && r.strata.allSatisfy { $0.imageDimension == 0 })
                }
                let work = a.work - beforeWork, bytes = a.storageBytes - beforeBytes
                var query = try G.ledger()
                if !r.isEmpty {
                    let point = try G.xyz(r, cs || mode != 3 ? 0 : 1, 0, 0, &query)
                    let fiber = try G.geometry.fiber(at: .xyz(point), in: r, limits: G.limits(), using: &query)
                    try GeometricFailureFixtures.require(!fiber.isEmpty)
                    if !cs && mode == 3 { try GeometricFailureFixtures.require(fiber.components.count == 4) }
                    if #available(macOS 26, *) {
                        try GeometricFailureFixtures.require(r.withStrata { $0.count } == r.strata.count)
                    }
                }
                print("PASS: cs=\(cs) mode=\(mode) strata=\(r.strata.count) incrementalWork=\(work) incrementalStorage=\(bytes) queryWork=\(query.work)")
            }
        }
        try GeometricFailureFixtures.verify()
        print("PASS: independent exact geometric relation composition")
    }
}
