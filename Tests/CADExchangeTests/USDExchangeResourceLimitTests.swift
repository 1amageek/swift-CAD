import Foundation
import Testing
import CADCore
import OpenUSD
@testable import CADExchange

@Suite("USD Exchange Resource Limits")
struct USDExchangeResourceLimitTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsInputBeforeParsingWhenByteLimitIsExceeded() {
        let exchange = USDExchange(
            tolerance: .standard,
            resourceLimits: limits(maximumBytes: 8)
        )

        expectResourceLimit {
            _ = try exchange.import(BorrowedBytes(Data(resourceLimitUSDA.utf8)), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsTextBeforeParsingWhenNestingLimitIsExceeded() {
        let nestedUSDA = """
        #usda 1.0
        def Xform "Outer" {
            def Xform "Inner" {
            }
        }
        """
        let exchange = USDExchange(
            tolerance: .standard,
            resourceLimits: limits(maximumNesting: 1)
        )

        expectResourceLimit {
            _ = try exchange.import(BorrowedBytes(Data(nestedUSDA.utf8)), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsInputBeforeParsingWhenIterationLimitIsExceeded() {
        let exchange = USDExchange(
            tolerance: .standard,
            resourceLimits: limits(maximumIterations: 8)
        )

        expectResourceLimit {
            _ = try exchange.import(BorrowedBytes(Data(resourceLimitUSDA.utf8)), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMaterializedMeshWhenEntityLimitIsExceeded() {
        let exchange = USDExchange(
            tolerance: .standard,
            resourceLimits: limits(maximumEntities: 4)
        )

        expectResourceLimit {
            _ = try exchange.import(BorrowedBytes(Data(resourceLimitUSDA.utf8)), as: .usda)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nestingPreflightIgnoresDelimitedTextAndAssetPaths() throws {
        let source = """
        #usda 1.0
        def Xform "Outer" {
            string note = "{{{{"
            asset source = @textures/{{{{/albedo.png@
            # {{{{
        }
        """
        let configuredLimits = limits(maximumNesting: 1)
        let budget = ExchangeProcessingBudget(
            maximumDuration: configuredLimits.maximumProcessingDuration
        )

        try USDImportResourceValidator(limits: configuredLimits).validateInput(
            USDByteStorage(data: Data(source.utf8)).wholeSlice,
            isText: true,
            format: .usda,
            budget: budget
        )
    }

    private func limits(
        maximumBytes: Int = 10_000,
        maximumEntities: Int = 1_000,
        maximumNesting: Int = 32,
        maximumIterations: Int = 10_000
    ) -> ExchangeResourceLimits {
        ExchangeResourceLimits(
            maximumBytes: maximumBytes,
            maximumEntities: maximumEntities,
            maximumNesting: maximumNesting,
            maximumIterations: maximumIterations,
            maximumProcessingDuration: .seconds(1)
        )
    }

    private func expectResourceLimit(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("USD import must enforce the configured resource limit.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        } catch {
            Issue.record("USD resource limits must return KernelError.resourceLimitExceeded.")
        }
    }
}

private let resourceLimitUSDA = """
#usda 1.0
(
    defaultPrim = "Triangle"
    metersPerUnit = 1
    upAxis = "Z"
)

def Mesh "Triangle"
{
    point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
    int[] faceVertexCounts = [3]
    int[] faceVertexIndices = [0, 1, 2]
    uniform token subdivisionScheme = "none"
}
"""
