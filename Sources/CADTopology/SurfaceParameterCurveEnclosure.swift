import CADGeometry

package struct SurfaceParameterCurveEnclosure: Hashable, Sendable {
    package let lowerFraction: Double
    package let upperFraction: Double
    package let u: ScalarInterval
    package let v: ScalarInterval

    package init(
        lowerFraction: Double,
        upperFraction: Double,
        u: ScalarInterval,
        v: ScalarInterval
    ) {
        self.lowerFraction = lowerFraction
        self.upperFraction = upperFraction
        self.u = u
        self.v = v
    }

    package var maximumWidth: Double {
        max(u.width, v.width)
    }
}
