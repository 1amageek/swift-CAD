import Testing
import Darwin

@Suite("Original parameter-image edge classification")
struct ParameterImageEdgeClassificationTests {
    @Test(.timeLimit(.minutes(1)))
    func originalParameterImageEndpointsRunOnCooperativeWorkers() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask {
                let stackBytes = pthread_get_stacksize_np(pthread_self())
                let isMainThread = pthread_main_np() != 0
                print("OBSERVED classifier worker stack bytes=\(stackBytes) mainThread=\(isMainThread)")
                #expect(!isMainThread)
                #expect(stackBytes > 0 && stackBytes <= 557_056)
                try ParameterImageEdgeClassificationChecks.run()
            } }
            try await group.waitForAll()
        }
    }
}
