import Foundation

func makeTempDir(file: StaticString = #file, line: UInt = #line) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("CompassTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
