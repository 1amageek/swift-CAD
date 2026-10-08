import KernelFixtures
@main struct KernelBenchmark { static func main() throws { try KernelFixtures.benchmark(); try KernelFixtures.pscBenchmark() } }
