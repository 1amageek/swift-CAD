import Foundation
import CADCore

struct STEPParameterEllipse: Sendable, Hashable {
    let center: Point2D
    let majorDirection: Point2D
    let majorRadius: Double
    let minorRadius: Double

    init(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        tolerance: Double
    ) throws {
        let xx = cosine.x * cosine.x + sine.x * sine.x
        let xy = cosine.x * cosine.y + sine.x * sine.y
        let yy = cosine.y * cosine.y + sine.y * sine.y
        let discriminant = hypot(xx - yy, 2.0 * xy)
        let majorSquared = 0.5 * (xx + yy + discriminant)
        let minorSquared = 0.5 * (xx + yy - discriminant)
        guard majorSquared.isFinite,
              minorSquared.isFinite,
              majorSquared > tolerance * tolerance,
              minorSquared > tolerance * tolerance else {
            throw GeometryError.invalidDistance(sqrt(max(minorSquared, 0.0)))
        }

        let direction: Point2D
        if abs(xy) > tolerance * tolerance {
            direction = try Self.normalized(
                Point2D(x: xy, y: majorSquared - xx),
                tolerance: tolerance
            )
        } else if xx >= yy {
            direction = Point2D(x: 1.0, y: 0.0)
        } else {
            direction = Point2D(x: 0.0, y: 1.0)
        }
        self.center = center
        self.majorDirection = direction
        self.majorRadius = sqrt(majorSquared)
        self.minorRadius = sqrt(minorSquared)
    }

    init(
        center: Point2D,
        majorDirection: Point2D,
        majorRadius: Double,
        minorRadius: Double,
        tolerance: Double
    ) throws {
        let normalizedDirection = try Self.normalized(majorDirection, tolerance: tolerance)
        guard center.x.isFinite,
              center.y.isFinite,
              majorRadius.isFinite,
              minorRadius.isFinite,
              majorRadius >= minorRadius,
              minorRadius > tolerance else {
            throw GeometryError.invalidDistance(minorRadius)
        }
        self.center = center
        self.majorDirection = normalizedDirection
        self.majorRadius = majorRadius
        self.minorRadius = minorRadius
    }

    var majorVector: Point2D {
        Point2D(
            x: majorDirection.x * majorRadius,
            y: majorDirection.y * majorRadius
        )
    }

    var minorVector: Point2D {
        Point2D(
            x: -majorDirection.y * minorRadius,
            y: majorDirection.x * minorRadius
        )
    }

    func parameter(of point: Point2D) -> Double {
        let offsetX = point.x - center.x
        let offsetY = point.y - center.y
        let cosine = (offsetX * majorDirection.x + offsetY * majorDirection.y) / majorRadius
        let sine = (offsetX * -majorDirection.y + offsetY * majorDirection.x) / minorRadius
        var parameter = atan2(sine, cosine)
        if parameter < 0.0 {
            parameter += 2.0 * Double.pi
        }
        return parameter
    }

    func residual(of point: Point2D) -> Double {
        let parameter = parameter(of: point)
        let reconstructed = self.point(at: parameter)
        return hypot(reconstructed.x - point.x, reconstructed.y - point.y)
    }

    func point(at parameter: Double) -> Point2D {
        let major = majorVector
        let minor = minorVector
        return Point2D(
            x: center.x + major.x * cos(parameter) + minor.x * sin(parameter),
            y: center.y + major.y * cos(parameter) + minor.y * sin(parameter)
        )
    }

    func derivative(at parameter: Double) -> Point2D {
        let major = majorVector
        let minor = minorVector
        return Point2D(
            x: -major.x * sin(parameter) + minor.x * cos(parameter),
            y: -major.y * sin(parameter) + minor.y * cos(parameter)
        )
    }

    private static func normalized(_ value: Point2D, tolerance: Double) throws -> Point2D {
        let length = hypot(value.x, value.y)
        guard length.isFinite, length > tolerance else {
            throw GeometryError.invalidDistance(length)
        }
        return Point2D(x: value.x / length, y: value.y / length)
    }
}
