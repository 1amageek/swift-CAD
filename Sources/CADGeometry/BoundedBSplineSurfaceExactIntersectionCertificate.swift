enum BoundedBSplineSurfaceExactIntersectionCertificate {
    case coincidence
    case quadraticTangency(QuadraticHeightFieldTangencyCertificate)
    case quarticTangency(QuarticHeightFieldTangencyCertificate)
    case isoparametricPlanar(ExactIsoparametricPlanarIntersectionGraph)
    case affineBilinear(ExactAffineBilinearIntersectionGraph)
}
