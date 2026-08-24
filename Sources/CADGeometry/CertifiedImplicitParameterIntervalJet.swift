package struct CertifiedImplicitParameterIntervalJet: Sendable, Hashable {
    package struct Coordinate: Sendable, Hashable {
        package let value: ScalarInterval
        package let firstDerivative: ScalarInterval
        package let secondDerivative: ScalarInterval
        package let thirdDerivative: ScalarInterval

        package init(
            value: ScalarInterval,
            firstDerivative: ScalarInterval,
            secondDerivative: ScalarInterval,
            thirdDerivative: ScalarInterval
        ) {
            self.value = value
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
            self.thirdDerivative = thirdDerivative
        }
    }

    package let coordinates: [Coordinate]

    package init(coordinates: [Coordinate]) {
        self.coordinates = coordinates
    }

    package subscript(
        _ coordinate: SurfaceIntersectionParameterCoordinate
    ) -> Coordinate {
        coordinates[coordinate.rawValue]
    }
}
