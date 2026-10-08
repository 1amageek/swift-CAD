import KernelFixtures
import Testing
@Suite(.timeLimit(.minutes(1))) struct KernelTests {
    @Test func principalSubresultants() throws { try KernelFixtures.psc() }
    @Test func heapProducts() throws { try KernelFixtures.heap() }
}
