import CADCore
import CADGeometry
import Foundation

package struct ExactPatternTransform: Hashable, Sendable {
    package let basisX: Vector3D
    package let basisY: Vector3D
    package let basisZ: Vector3D
    package let translation: Vector3D

    package init(
        basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D
    ) {
        self.basisX = basisX
        self.basisY = basisY
        self.basisZ = basisZ
        self.translation = translation
    }

    package static func translated(by offset: Vector3D) -> ExactPatternTransform {
        ExactPatternTransform(
            basisX: .unitX,
            basisY: .unitY,
            basisZ: .unitZ,
            translation: offset
        )
    }

    package static func rotated(
        around origin: Point3D,
        direction: Vector3D,
        angle: Double,
        tolerance: ModelingTolerance
    ) throws -> ExactPatternTransform {
        let axis = try direction.normalized(tolerance: tolerance.distance)
        guard angle.isFinite else {
            throw GeometryError.invalidCoordinate(angle)
        }
        let basisX = rotate(.unitX, around: axis, angle: angle)
        let basisY = rotate(.unitY, around: axis, angle: angle)
        let basisZ = rotate(.unitZ, around: axis, angle: angle)
        let rotatedOrigin = apply(
            point: origin,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: .zero
        )
        return ExactPatternTransform(
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: origin - rotatedOrigin
        )
    }

    package static func mirrored(
        across origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> ExactPatternTransform {
        let unit = try normal.normalized(tolerance: tolerance.distance)
        let basisX = Vector3D.unitX - unit * (2.0 * unit.x)
        let basisY = Vector3D.unitY - unit * (2.0 * unit.y)
        let basisZ = Vector3D.unitZ - unit * (2.0 * unit.z)
        let mirroredOrigin = apply(
            point: origin,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: .zero
        )
        return ExactPatternTransform(
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: origin - mirroredOrigin
        )
    }

    package static func followingPath(
        anchor: Point3D,
        referenceDirection: Vector3D,
        pathPoint: Point3D,
        pathTangent: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> ExactPatternTransform {
        let source = try referenceDirection.normalized(tolerance: tolerance.distance)
        let target = try pathTangent.normalized(tolerance: tolerance.distance)
        let dot = min(1.0, max(-1.0, source.dot(target)))
        let cross = source.cross(target)
        let rotation: ExactPatternTransform
        if cross.length > tolerance.angle {
            rotation = try rotated(
                around: anchor,
                direction: cross,
                angle: acos(dot),
                tolerance: tolerance
            )
        } else if dot >= 0.0 {
            rotation = .translated(by: .zero)
        } else {
            let helper = abs(source.x) <= abs(source.y) && abs(source.x) <= abs(source.z)
                ? Vector3D.unitX
                : (abs(source.y) <= abs(source.z) ? .unitY : .unitZ)
            rotation = try rotated(
                around: anchor,
                direction: source.cross(helper),
                angle: .pi,
                tolerance: tolerance
            )
        }
        return ExactPatternTransform(
            basisX: rotation.basisX,
            basisY: rotation.basisY,
            basisZ: rotation.basisZ,
            translation: rotation.translation + (pathPoint - anchor)
        )
    }

    package func applying(to point: Point3D) -> Point3D {
        Self.apply(
            point: point,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: translation
        )
    }

    package func applying(to vector: Vector3D) -> Vector3D {
        basisX * vector.x + basisY * vector.y + basisZ * vector.z
    }

    package func applying(
        to surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let transformed = BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { row in
                row.map(applying(to:))
            },
            weights: surface.weights
        )
        try transformed.validate(tolerance: tolerance)
        return transformed
    }

    private static func rotate(
        _ vector: Vector3D,
        around axis: Vector3D,
        angle: Double
    ) -> Vector3D {
        let cosine = cos(angle)
        let sine = sin(angle)
        return vector * cosine
            + axis.cross(vector) * sine
            + axis * (axis.dot(vector) * (1.0 - cosine))
    }

    private static func apply(
        point: Point3D,
        basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D
    ) -> Point3D {
        .origin
            + basisX * point.x
            + basisY * point.y
            + basisZ * point.z
            + translation
    }
}
