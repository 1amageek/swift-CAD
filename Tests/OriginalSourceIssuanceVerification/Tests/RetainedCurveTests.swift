import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalRetainedCurveSupply() throws { try SourceFixtures.retainedCurveLaws() }
