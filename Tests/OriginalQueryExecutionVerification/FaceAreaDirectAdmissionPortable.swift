import CADCore
import CADGeometry
import CADTopology

// Compile with FaceAreaDirectAdmissionTests.swift and -D FACE_AREA_DIRECT_PORTABLE.
@main
struct FaceAreaDirectAdmissionPortable {
    static func main() throws {
        try FaceAreaDirectAdmissionChecks.supportedSurfacesRetainTheirIndependentAreaAndCentroid()
        print("PASS supportedSurfacesRetainTheirIndependentAreaAndCentroid")
        try FaceAreaDirectAdmissionChecks.workAndStorageUseTheCumulativeCallerBoundary()
        print("PASS workAndStorageUseTheCumulativeCallerBoundary")
        try FaceAreaDirectAdmissionChecks.entryAndInProgressCancellationRetainTheCallerCause()
        print("PASS entryAndInProgressCancellationRetainTheCallerCause")
        try FaceAreaDirectAdmissionChecks.sourceAxesGuardsAndResultLifetimeRemainIndependent()
        print("PASS sourceAxesGuardsAndResultLifetimeRemainIndependent")
    }
}
