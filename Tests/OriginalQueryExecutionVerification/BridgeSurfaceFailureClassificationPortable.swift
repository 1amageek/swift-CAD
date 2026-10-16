import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@main
struct BridgeSurfaceFailureClassificationPortable {
    static func main() throws {
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderPublishesANonemptyBridge()
        print("PASS actualRuledBuilderPublishesANonemptyBridge")
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderWorkRefusalKeepsItsCauseAndFeatureContext()
        print("PASS actualRuledBuilderWorkRefusalKeepsItsCauseAndFeatureContext")
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderStorageRefusalKeepsItsCauseAndFeatureContext()
        print("PASS actualRuledBuilderStorageRefusalKeepsItsCauseAndFeatureContext")
        try BridgeSurfaceFailureClassificationChecks.actualRuledBuilderCancellationKeepsItsCause()
        print("PASS actualRuledBuilderCancellationKeepsItsCause")
    }
}
