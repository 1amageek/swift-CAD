import CADCore

enum SurfaceParameterThirdOrderChainRule {
    /// Pulls a surface jet back to one normalized curve parameter, stored in U.
    static func intervalJet(
        surface: SurfaceIntervalVectorJet,
        u: SurfaceIntervalJet,
        v: SurfaceIntervalJet
    ) -> SurfaceIntervalVectorJet {
        let a = u.derivativeU, b = v.derivativeU
        let c = u.secondDerivativeUU, d = v.secondDerivativeUU
        let three = OutwardScalarInterval(3)
        let zero = OutwardScalarInterval(0)
        func coordinate(_ s: SurfaceIntervalJet) -> SurfaceIntervalJet {
            let first = s.derivativeU * a + s.derivativeV * b
            let second = s.secondDerivativeUU * a * a
                + OutwardScalarInterval(2) * s.secondDerivativeUV * a * b
                + s.secondDerivativeVV * b * b + s.derivativeU * c + s.derivativeV * d
            let third = s.thirdDerivativeUUU * a * a * a
                + three * s.thirdDerivativeUUV * a * a * b
                + three * s.thirdDerivativeUVV * a * b * b
                + s.thirdDerivativeVVV * b * b * b
                + three * s.secondDerivativeUU * a * c
                + three * s.secondDerivativeUV * (c * b + a * d)
                + three * s.secondDerivativeVV * b * d
                + s.derivativeU * u.thirdDerivativeUUU + s.derivativeV * v.thirdDerivativeUUU
            return SurfaceIntervalJet(value: s.value,
                derivativeU: first, derivativeV: zero,
                secondDerivativeUU: second, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: third, thirdDerivativeUUV: zero,
                thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        return SurfaceIntervalVectorJet(x: coordinate(surface.x),
            y: coordinate(surface.y), z: coordinate(surface.z))
    }

    static func firstDerivative(
        surface: SurfaceParameterThirdOrderDerivatives,
        parameter: Point2D
    ) -> Vector3D {
        surface.tangentU * parameter.x
            + surface.tangentV * parameter.y
    }

    static func secondDerivative(
        surface: SurfaceParameterThirdOrderDerivatives,
        firstParameterDerivative first: Point2D,
        secondParameterDerivative second: Point2D
    ) -> Vector3D {
        surface.secondDerivativeUU * (first.x * first.x)
            + surface.secondDerivativeUV * (2.0 * first.x * first.y)
            + surface.secondDerivativeVV * (first.y * first.y)
            + surface.tangentU * second.x
            + surface.tangentV * second.y
    }

    static func thirdDerivative(
        surface: SurfaceParameterThirdOrderDerivatives,
        firstParameterDerivative first: Point2D,
        secondParameterDerivative second: Point2D,
        thirdParameterDerivative third: Point2D
    ) -> Vector3D {
        surface.thirdDerivativeUUU * (first.x * first.x * first.x)
            + surface.thirdDerivativeUUV * (3.0 * first.x * first.x * first.y)
            + surface.thirdDerivativeUVV * (3.0 * first.x * first.y * first.y)
            + surface.thirdDerivativeVVV * (first.y * first.y * first.y)
            + surface.secondDerivativeUU * (3.0 * first.x * second.x)
            + surface.secondDerivativeUV
                * (3.0 * (second.x * first.y + first.x * second.y))
            + surface.secondDerivativeVV * (3.0 * first.y * second.y)
            + surface.tangentU * third.x
            + surface.tangentV * third.y
    }
}
