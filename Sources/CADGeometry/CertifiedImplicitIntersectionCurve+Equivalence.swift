import CADCore

package extension CertifiedImplicitIntersectionCurve {
    func certifiesSameComponent(
        as other: CertifiedImplicitIntersectionCurve,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try validate(tolerance: tolerance)
        try other.validate(tolerance: tolerance)
        let surfacesAreSwapped: Bool
        if firstSurface == other.firstSurface,
           secondSurface == other.secondSurface {
            surfacesAreSwapped = false
        } else if firstSurface == other.secondSurface,
                  secondSurface == other.firstSurface {
            surfacesAreSwapped = true
        } else {
            return false
        }
        guard isClosed == other.isClosed else {
            return false
        }
        if surfacesAreSwapped == false, cells == other.cells {
            return true
        }
        if let coordinate = cells.first?.freeParameter,
           cells.allSatisfy({ $0.freeParameter == coordinate }),
           let otherCoordinate = correspondingCoordinate(
               to: coordinate,
               surfacesAreSwapped: surfacesAreSwapped
           ),
           other.cells.allSatisfy({
               $0.freeParameter == otherCoordinate
           }),
           sameFreeCoordinateAtlasesMatch(
               other,
               coordinate: coordinate,
               otherCoordinate: otherCoordinate,
               surfacesAreSwapped: surfacesAreSwapped,
               tolerance: tolerance
           ) {
            return true
        }
        return differentlyParameterizedAtlasesMatch(
            other,
            surfacesAreSwapped: surfacesAreSwapped,
            tolerance: tolerance
        )
    }

    private func sameFreeCoordinateAtlasesMatch(
        _ other: CertifiedImplicitIntersectionCurve,
        coordinate: SurfaceIntersectionParameterCoordinate,
        otherCoordinate: SurfaceIntersectionParameterCoordinate,
        surfacesAreSwapped: Bool,
        tolerance: ModelingTolerance
    ) -> Bool {
        let firstIntervals = cells.map {
            $0.parameterBox.interval(for: coordinate)
        }
        let secondIntervals = other.cells.map {
            $0.parameterBox.interval(for: otherCoordinate)
        }
        let bounds = Array(Set(
            (firstIntervals + secondIntervals).flatMap { [$0.lower, $0.upper] }
        )).sorted()
        guard bounds.count >= 2,
              approximatelyEqual(
                  firstIntervals.map(\.lower).min() ?? .infinity,
                  secondIntervals.map(\.lower).min() ?? -.infinity,
                  tolerance: tolerance.relative
              ),
              approximatelyEqual(
                  firstIntervals.map(\.upper).max() ?? -.infinity,
                  secondIntervals.map(\.upper).max() ?? .infinity,
                  tolerance: tolerance.relative
              ) else {
            return false
        }
        for index in 0..<(bounds.count - 1) {
            let lower = bounds[index]
            let upper = bounds[index + 1]
            guard upper - lower > tolerance.relative else {
                continue
            }
            let midpoint = lower + (upper - lower) * 0.5
            guard let firstCell = cells.first(where: {
                $0.parameterBox.interval(for: coordinate).contains(midpoint)
            }), let secondCell = other.cells.first(where: {
                $0.parameterBox.interval(for: otherCoordinate).contains(midpoint)
            }), boxesAreNested(
                firstCell.parameterBox,
                secondCell.parameterBox,
                surfacesAreSwapped: surfacesAreSwapped,
                tolerance: tolerance.relative
            ) else {
                return false
            }
        }
        return true
    }

    private func differentlyParameterizedAtlasesMatch(
        _ other: CertifiedImplicitIntersectionCurve,
        surfacesAreSwapped: Bool,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard endpointsMatch(
            other,
            surfacesAreSwapped: surfacesAreSwapped,
            tolerance: tolerance.relative
        ) else {
            return false
        }
        if cells.allSatisfy({ firstCell in
            other.cells.contains { secondCell in
                boxesAreNested(
                    firstCell.parameterBox,
                    secondCell.parameterBox,
                    surfacesAreSwapped: surfacesAreSwapped,
                    tolerance: tolerance.relative
                )
            }
        }), other.cells.allSatisfy({ secondCell in
            cells.contains { firstCell in
                boxesAreNested(
                    firstCell.parameterBox,
                    secondCell.parameterBox,
                    surfacesAreSwapped: surfacesAreSwapped,
                    tolerance: tolerance.relative
                )
            }
        }) {
            return true
        }
        return sharesCertifiedComponentWitness(
            with: other,
            surfacesAreSwapped: surfacesAreSwapped,
            tolerance: tolerance.relative
        )
    }

    private func sharesCertifiedComponentWitness(
        with other: CertifiedImplicitIntersectionCurve,
        surfacesAreSwapped: Bool,
        tolerance: Double
    ) -> Bool {
        for firstCell in cells {
            let firstAnchors = [
                firstCell.lowerAnchor,
                firstCell.midpointAnchor,
                firstCell.upperAnchor,
            ]
            for secondCell in other.cells {
                let secondIntervals = reorderedIntervals(
                    secondCell.parameterBox,
                    surfacesAreSwapped: surfacesAreSwapped
                )
                guard boxesOverlap(
                    firstCell.parameterBox.intervals,
                    secondIntervals,
                    tolerance: tolerance
                ) else {
                    continue
                }
                for firstAnchor in firstAnchors {
                    for secondAnchor in [
                        secondCell.lowerAnchor,
                        secondCell.midpointAnchor,
                        secondCell.upperAnchor,
                    ] {
                        let secondValues = reorderedValues(
                            secondAnchor,
                            surfacesAreSwapped: surfacesAreSwapped
                        )
                        guard parameterValues(
                            firstAnchor.values,
                            approximatelyEqualTo: secondValues,
                            tolerance: tolerance
                        ), box(
                            firstCell.parameterBox.intervals,
                            containsValues: secondValues,
                            tolerance: tolerance
                        ), box(
                            secondIntervals,
                            containsValues: firstAnchor.values,
                            tolerance: tolerance
                        ) else {
                            continue
                        }
                        return true
                    }
                }
            }
        }
        return false
    }

    private func endpointsMatch(
        _ other: CertifiedImplicitIntersectionCurve,
        surfacesAreSwapped: Bool,
        tolerance: Double
    ) -> Bool {
        guard let firstStart = cells.first?.startAnchor,
              let firstEnd = cells.last?.endAnchor,
              let secondStart = other.cells.first?.startAnchor,
              let secondEnd = other.cells.last?.endAnchor else {
            return false
        }
        let reorderedStart = reorderedValues(
            secondStart,
            surfacesAreSwapped: surfacesAreSwapped
        )
        let reorderedEnd = reorderedValues(
            secondEnd,
            surfacesAreSwapped: surfacesAreSwapped
        )
        return (parameterValues(
            firstStart.values,
            approximatelyEqualTo: reorderedStart,
            tolerance: tolerance
        ) && parameterValues(
            firstEnd.values,
            approximatelyEqualTo: reorderedEnd,
            tolerance: tolerance
        )) || (parameterValues(
            firstStart.values,
            approximatelyEqualTo: reorderedEnd,
            tolerance: tolerance
        ) && parameterValues(
            firstEnd.values,
            approximatelyEqualTo: reorderedStart,
            tolerance: tolerance
        ))
    }

    private func reorderedValues(
        _ parameters: SurfaceIntersectionParameterPair,
        surfacesAreSwapped: Bool
    ) -> [Double] {
        guard surfacesAreSwapped else {
            return parameters.values
        }
        return [
            parameters.second.u,
            parameters.second.v,
            parameters.first.u,
            parameters.first.v,
        ]
    }

    private func parameterValues(
        _ first: [Double],
        approximatelyEqualTo second: [Double],
        tolerance: Double
    ) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy {
            approximatelyEqual($0, $1, tolerance: tolerance)
        }
    }

    private func boxesAreNested(
        _ first: SurfaceIntersectionParameterBox,
        _ second: SurfaceIntersectionParameterBox,
        surfacesAreSwapped: Bool,
        tolerance: Double
    ) -> Bool {
        let firstIntervals = first.intervals
        let secondIntervals = surfacesAreSwapped
            ? [second.secondU, second.secondV, second.firstU, second.firstV]
            : second.intervals
        return box(
            firstIntervals,
            contains: secondIntervals,
            tolerance: tolerance
        ) || box(
            secondIntervals,
            contains: firstIntervals,
            tolerance: tolerance
        )
    }

    private func reorderedIntervals(
        _ box: SurfaceIntersectionParameterBox,
        surfacesAreSwapped: Bool
    ) -> [ScalarInterval] {
        surfacesAreSwapped
            ? [box.secondU, box.secondV, box.firstU, box.firstV]
            : box.intervals
    }

    private func boxesOverlap(
        _ first: [ScalarInterval],
        _ second: [ScalarInterval],
        tolerance: Double
    ) -> Bool {
        zip(first, second).allSatisfy { first, second in
            max(first.lower, second.lower) <= min(first.upper, second.upper) + tolerance
        }
    }

    private func box(
        _ outer: [ScalarInterval],
        contains inner: [ScalarInterval],
        tolerance: Double
    ) -> Bool {
        zip(outer, inner).allSatisfy { outer, inner in
            inner.lower >= outer.lower - tolerance
                && inner.upper <= outer.upper + tolerance
        }
    }

    private func box(
        _ outer: [ScalarInterval],
        containsValues values: [Double],
        tolerance: Double
    ) -> Bool {
        zip(outer, values).allSatisfy { interval, value in
            value >= interval.lower - tolerance
                && value <= interval.upper + tolerance
        }
    }

    private func correspondingCoordinate(
        to coordinate: SurfaceIntersectionParameterCoordinate,
        surfacesAreSwapped: Bool
    ) -> SurfaceIntersectionParameterCoordinate? {
        guard surfacesAreSwapped else {
            return coordinate
        }
        switch coordinate {
        case .firstU:
            return .secondU
        case .firstV:
            return .secondV
        case .secondU:
            return .firstU
        case .secondV:
            return .firstV
        }
    }

    private func approximatelyEqual(
        _ first: Double,
        _ second: Double,
        tolerance: Double
    ) -> Bool {
        let scale = max(abs(first), abs(second), 1.0)
        return abs(first - second) <= max(
            tolerance * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }
}
