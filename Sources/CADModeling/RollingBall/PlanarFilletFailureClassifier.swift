import CADCore
import CADGeometry

package struct PlanarFilletFailureClassifier: Sendable {
    package init() {}

    package func exceedsReach(radius: Double, from start: Point3D, to end: Point3D) -> Bool {
        guard radius.isFinite, radius > 0 else { return false }
        func squared(_ first: Double, _ second: Double) -> OutwardScalarInterval {
            let delta = OutwardScalarInterval.exact(first) - .exact(second)
            let upper = delta.absoluteUpperBound
            return OutwardScalarInterval(lower: 0, upper: (upper * upper).nextUp)
        }
        let distance = squared(start.x, end.x) + squared(start.y, end.y) + squared(start.z, end.z)
        let request = OutwardScalarInterval.exact(radius) * .exact(radius)
        return request.lower > distance.upper
    }

    package func removedFaceCode(polygon: [Point3D], origin: Point3D,
                                 normal: Vector3D, offset: Double) -> KernelErrorCode {
        guard !polygon.isEmpty, offset.isFinite else { return .topologyFailure }
        for point in polygon {
            func component(_ coordinate: Double, _ anchor: Double, _ direction: Double) -> OutwardScalarInterval {
                (.exact(coordinate) - .exact(anchor)) * .exact(direction)
            }
            let side = component(point.x, origin.x, normal.x)
                + component(point.y, origin.y, normal.y) + component(point.z, origin.z, normal.z)
            guard side.upper <= offset else { return .topologyFailure }
        }
        return .filletFaceDisappeared
    }
}
