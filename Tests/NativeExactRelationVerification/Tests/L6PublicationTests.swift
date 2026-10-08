import Testing
import NativeExactFixtures

@Test(.timeLimit(.minutes(2)))
func l5SquareReductionContracts() throws { try L5SquareReductionFixtures.verify() }

@Test(.timeLimit(.minutes(2)))
func l6CurveSurfacePublicPublication() throws { try L6CurveSurfaceFixtures.verify() }

@Test(.timeLimit(.minutes(2)))
func l6CurveSurfaceCompleteCandidateLimits() throws { try L6PublicCurveSurfaceFixtures.verifyCandidateLimits() }

@Test(.timeLimit(.minutes(2)))
func l6SurfaceSurfacePublicPoints() throws { try L6SurfaceSurfaceFixtures.verifyPoints() }

@Test(.timeLimit(.minutes(2)))
func l6SurfaceSurfacePublicImagesAndFibers() throws { try L6SurfaceSurfaceFixtures.verifyImagesAndFibers() }

@Test(.timeLimit(.minutes(2)))
func l6SurfaceSurfacePublicSelectedDomains() throws { try L6SurfaceSurfaceFixtures.verifySelectedDomains() }

@Test(.timeLimit(.minutes(2)))
func l6SurfaceSurfacePublicFailures() throws { try L6SurfaceSurfaceFixtures.verifyFailures() }
