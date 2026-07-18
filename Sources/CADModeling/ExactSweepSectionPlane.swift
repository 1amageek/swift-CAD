import CADCore
import CADGeometry
import CADIR

package struct ExactSweepSectionPlane: Sendable {
    package let plane: Plane3D
    private let frame: PlanarFaceFrame

    package init(
        _ sketchPlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws {
        let source: Plane3D
        switch sketchPlane {
        case .xy:
            source = Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            source = Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            source = Plane3D(origin: .origin, normal: .unitY)
        case .plane(let value):
            source = value
        }
        try source.validate(tolerance: tolerance)
        let plane = Plane3D(
            origin: source.origin,
            normal: try source.normal.normalized(
                tolerance: tolerance.distance
            )
        )
        self.plane = plane
        self.frame = try PlanarFaceFrame(
            plane: plane,
            tolerance: tolerance
        )
    }

    package func orthogonalProjection(_ point: Point3D) -> Point3D {
        point + plane.normal * (-(point - plane.origin).dot(plane.normal))
    }

    package func localOffset(
        from anchor: Point3D,
        to point: Point3D
    ) -> Point2D {
        localOffset(point - anchor)
    }

    package func localOffset(_ offset: Vector3D) -> Point2D {
        return Point2D(
            x: offset.dot(frame.u),
            y: offset.dot(frame.v)
        )
    }

    package func worldOffset(_ offset: Point2D) -> Vector3D {
        frame.u * offset.x + frame.v * offset.y
    }
}
