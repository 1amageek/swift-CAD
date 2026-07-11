import Foundation
import Testing
@testable import CADCore

@Suite("Persistent map")
struct PersistentMapTests {
    @Test(.timeLimit(.minutes(1)))
    func copyMutationPreservesPriorSnapshot() {
        let ids = (0..<256).map { _ in ParameterID() }
        var original = PersistentMap<ParameterID, Int>(
            uniqueKeysWithValues: ids.enumerated().map { index, id in
                (id, index)
            }
        )
        var changed = original

        changed[ids[128]] = 900
        changed.removeValue(forKey: ids[64])
        original[ParameterID()] = 256

        #expect(changed[ids[128]] == 900)
        #expect(original[ids[128]] == 128)
        #expect(changed[ids[64]] == nil)
        #expect(original[ids[64]] == 64)
        #expect(changed.count == 255)
        #expect(original.count == 257)
    }

    @Test(.timeLimit(.minutes(1)))
    func codableRoundTripPreservesEntries() throws {
        let values: PersistentMap<ParameterID, Int> = [
            ParameterID(): 1,
            ParameterID(): 2,
            ParameterID(): 3,
        ]

        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode(
            PersistentMap<ParameterID, Int>.self,
            from: data
        )

        #expect(decoded == values)
    }

    @Test(.timeLimit(.minutes(1)))
    func filterReturnsIndependentPersistentMap() {
        let values = PersistentMap<Int, Int>(
            uniqueKeysWithValues: (0..<100).map { ($0, $0 * 2) }
        )

        let filtered = values.filter { $0.key.isMultiple(of: 2) }

        #expect(filtered.count == 50)
        #expect(filtered[24] == 48)
        #expect(filtered[25] == nil)
        #expect(values.count == 100)
    }
}
