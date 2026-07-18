import CADCore
import CADIR
import CADTopology

public struct OrthogonalSolidPointClassifier: SolidPointClassifying {
    public init() {}

    public func classify(
        _ point: Point3D,
        in bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SolidPointClassification {
        try point.validate()
        let operand = try OrthogonalSolidOperand(bodyID: bodyID, in: model, tolerance: tolerance)
        guard contains(point, in: operand.cells, tolerance: tolerance.distance) else {
            return .outside
        }
        let offset = tolerance.distance * 4.0
        let probes = [
            Vector3D(x: offset, y: 0.0, z: 0.0),
            Vector3D(x: -offset, y: 0.0, z: 0.0),
            Vector3D(x: 0.0, y: offset, z: 0.0),
            Vector3D(x: 0.0, y: -offset, z: 0.0),
            Vector3D(x: 0.0, y: 0.0, z: offset),
            Vector3D(x: 0.0, y: 0.0, z: -offset),
        ]
        let isInterior = probes.allSatisfy { probe in
            contains(point + probe, in: operand.cells, tolerance: tolerance.distance)
        }
        return isInterior ? .inside : .boundary
    }

    private func contains(
        _ point: Point3D,
        in cells: [AxisAlignedBox],
        tolerance: Double
    ) -> Bool {
        cells.contains { cell in
            point.x >= cell.minimum.x - tolerance && point.x <= cell.maximum.x + tolerance
                && point.y >= cell.minimum.y - tolerance && point.y <= cell.maximum.y + tolerance
                && point.z >= cell.minimum.z - tolerance && point.z <= cell.maximum.z + tolerance
        }
    }
}
