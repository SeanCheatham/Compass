import Foundation

func makeCompassTestDirectory(named prefix: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "\(prefix)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(
    at: url,
    withIntermediateDirectories: true,
    attributes: nil
  )
  return url
}
