import L3Fixtures
@main struct L3Proof {
 static func main() throws {
  try CellFixtures.nullification()
  try CellFixtures.singularities()
  try CellFixtures.domains()
  try QueryFixtures.selectionAndLocation()
  try QueryFixtures.nullifiedQuery()
  try QueryFixtures.algebraicQueries()
  try QueryFixtures.applicationRelations()
  try QueryFixtures.retainedAndOutside()
  try FailureFixtures.resources()
  try FailureFixtures.sourceTraversal()
  try FailureFixtures.escapedOwnership()
  try OriginalCoefficientFixtures.run()
  try ProtocolFixtures.run()
  print("PASS: 13 complete real-cell, selection, exact location and failure routines")
 }
}
