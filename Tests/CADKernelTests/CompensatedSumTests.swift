import Testing
@testable import CADKernel

@Suite("Compensated sum")
struct CompensatedSumTests {
    @Test
    func preservesSmallResidualAcrossLargeCancellation() {
        var sum = CompensatedSum()

        sum.add(1.0e16)
        sum.add(1.0)
        sum.add(-1.0e16)

        #expect(sum.value == 1.0)
    }
}
