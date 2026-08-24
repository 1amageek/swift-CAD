import CADCore

enum SurfaceParameterThirdOrderChainRule {
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
