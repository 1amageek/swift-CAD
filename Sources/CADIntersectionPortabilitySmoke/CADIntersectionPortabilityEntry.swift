import CADCore

@main
struct CADIntersectionPortabilityEntry {
    static func main() async throws {
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) {
            try OriginalRealRelationProof.run()
            try await OriginalRealRelationProof.cancellation()
            print("ORIGINAL_REAL_RELATION_PORTABILITY_OK")
            try OriginalPointRelationProof.run()
            try await OriginalPointRelationProof.cancellation()
            print("ORIGINAL_POINT_RELATION_PORTABILITY_OK")
        } else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Original point proof requires platform Synchronization.Mutex support.")
        }
    }
}
