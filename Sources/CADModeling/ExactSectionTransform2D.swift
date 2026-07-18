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
