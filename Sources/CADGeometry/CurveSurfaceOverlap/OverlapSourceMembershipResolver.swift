import CADCore

/// Restricts hosting provenance to exact retained surface values.
struct OverlapSourceMembershipResolver {
    func isExactSource(_ surface: Surface3D, of curve: Curve3D, tolerance: ModelingTolerance) throws -> Bool {
        try supports(of: curve, tolerance: tolerance).contains(surface)
    }

    private func supports(of curve: Curve3D, tolerance: ModelingTolerance) throws -> [Surface3D] {
        switch curve {
        case .surfaceLift(let lift):
            if let other = try lift.parameterCurve.otherIntersectionSupportSurface(on: lift.surface, tolerance: tolerance) {
                return [lift.surface, other]
            }
            return [lift.surface]
        case .implicit(let implicit):
            return [implicit.firstSurface, implicit.secondSurface]
        case .analytic(.planeTorus(let intersection)):
            return [intersection.planeSurface, intersection.torusSurface]
        case .certifiedIntersection(let intersection):
            switch intersection {
            case .sphereCone(let source): return [source.sphereSurface, source.coneSurface]
            case .coneCone(let source): return [source.referenceSurface, source.parameterizedSurface]
            case .coneCylinder(let source): return [source.coneSurface, source.cylinderSurface]
            case .coneTorus(let source): return [source.coneSurface, source.torusSurface]
            case .parallelTorusTorus(let source): return [source.primarySurface, source.secondarySurface]
            }
        case .rigidImage(let image):
            return try supports(of: image.source, tolerance: tolerance).map {
                try image.transform.applying(to: $0, tolerance: tolerance)
            }
        case .parameterImage(let image):
            return try supports(of: image.source, tolerance: tolerance)
        case .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain, .originalPolyline, .originalGuideEndpointConnector, .originalDrafted, .originalAngularTransport, .originalAffineWord, .line, .circle, .bSpline, .affineImage, .analytic:
            return []
        }
    }
}
