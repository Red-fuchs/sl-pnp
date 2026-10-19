import Foundation

/// Header value (case-insensitive name) from a raw request head. Note: "\r\n" is ONE Character in Swift -> split on it, never test for "\r".
public func httpHeader(_ head: String, _ name: String) -> String? {
  for l in head.components(separatedBy: "\r\n").dropFirst() {
    guard let i = l.firstIndex(of: ":") else { continue }
    if l[..<i].lowercased() == name.lowercased() { return l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) }
  }
  return nil
}
