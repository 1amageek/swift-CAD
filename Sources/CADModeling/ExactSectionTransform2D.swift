import Foundation
import CADCore

package struct ExactSectionTransform2D: Sendable, Hashable {
    package let m11: Double
    package let m12: Double
    package let m21: Double
    package let m22: Double

    package static let identity = ExactSectionTransform2D(
        m11: 1.0,
        m12: 0.0,
        m21: 0.0,
        m22: 1.0
    )

    package static func uniformScale(
        _ scale: Double
    ) -> ExactSectionTransform2D {
        ExactSectionTransform2D(
            m11: scale,
            m12: 0.0,
            m21: 0.0,
            m22: scale
        )
    }

    package static func similarity(
        mapping source: Point2D,
        to target: Point2D,
        tolerance: ModelingTolerance
    ) throws -> ExactSectionTransform2D {
        let sourceLengthSquared = source.x * source.x + source.y * source.y
        guard sourceLengthSquared > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideContactUnavailable,
                residual: sourceLengthSquared,
                tolerance: tolerance,
                message: "Exact point-guide Sweep requires a guide contact distinct from the path axis."
            )
        }
        let real = (
            source.x * target.x + source.y * target.y
        ) / sourceLengthSquared
        let imaginary = (
            source.x * target.y - source.y * target.x
        ) / sourceLengthSquared
        return ExactSectionTransform2D(
            m11: real,
            m12: -imaginary,
            m21: imaginary,
            m22: real
        )
    }

    /// The linear map taking `source.0` to `target.0` and `source.1` to `target.1`: `T·S⁻¹` for the
    /// matrices with those columns. The sources must span the plane.
    package static func linear(
        mapping source: (Point2D, Point2D),
        to target: (Point2D, Point2D),
        tolerance: ModelingTolerance
    ) throws -> ExactSectionTransform2D {
        let determinant = source.0.x * source.1.y - source.1.x * source.0.y
        let scale = hypot(source.0.x, source.0.y) * hypot(source.1.x, source.1.y)
        guard scale > 0, abs(determinant) > sin(tolerance.angle) * scale else {
            throw KernelError(
                phase: .geometry,
                code: .sweepGuideContactUnavailable,
                residual: determinant,
                tolerance: tolerance,
                message: "Two Point guides start in line with the path; their contacts must span the section's plane."
            )
        }
        // S⁻¹ = (1/det)·[[s1.y, −s1.x], [−s0.y, s0.x]].
        let (i11, i12, i21, i22) = (source.1.y / determinant, -source.1.x / determinant,
                                    -source.0.y / determinant, source.0.x / determinant)
        return ExactSectionTransform2D(
            m11: target.0.x * i11 + target.1.x * i21,
            m12: target.0.x * i12 + target.1.x * i22,
            m21: target.0.y * i11 + target.1.y * i21,
            m22: target.0.y * i12 + target.1.y * i22
        )
    }

    package init(
        m11: Double,
        m12: Double,
        m21: Double,
        m22: Double
    ) {
        self.m11 = m11
        self.m12 = m12
        self.m21 = m21
        self.m22 = m22
    }

    package var determinant: Double {
        m11 * m22 - m12 * m21
    }

    package var isFinite: Bool {
        m11.isFinite && m12.isFinite && m21.isFinite && m22.isFinite
    }

    package func applied(to point: Point2D) -> Point2D {
        Point2D(
            x: m11 * point.x + m12 * point.y,
            y: m21 * point.x + m22 * point.y
        )
    }

    package func interpolated(ratio: Double) -> ExactSectionTransform2D {
        ExactSectionTransform2D(
            m11: 1.0 + (m11 - 1.0) * ratio,
            m12: m12 * ratio,
            m21: m21 * ratio,
            m22: 1.0 + (m22 - 1.0) * ratio
        )
    }
}
