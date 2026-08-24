enum BoundedBSplineSurfaceExactIntersectionCertificate {
    case disjoint
    case coincidence
    case quadraticTangency(QuadraticHeightFieldTangencyCertificate)
    case quarticTangency(QuarticHeightFieldTangencyCertificate)
    case isoparametricPlanar(ExactIsoparametricPlanarIntersectionGraph)
    case affinePoint(SurfaceIntersectionParameterPair)
    case affineBilinear(ExactAffineBilinearIntersectionGraph)
}
