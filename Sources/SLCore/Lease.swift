import Foundation

/// Holds a gpu-run slot only while the model is loaded. gpu-run has no acquire/release mode, so a tiny holder job runs under it:
///   gpu-run -n <label> --ram N sh -c '<holder>'   (gpu-run queues FIFO, applies the RAM gate, then starts the holder)
/// The holder writes a ready file and sleeps until the keep file disappears (release) or the owning sl process dies (no leaks).
/// gpu-run itself is not modified.
public final class GPULease {
  let label: String, ram: Int
  var proc: Process?
  var dir: URL?
  let gpuRun: String?
  public init(label: String, ram: Int = 10, gpuRun: String? = nil) { self.label = label; self.ram = ram; self.gpuRun = gpuRun }
  public var held: Bool { proc?.isRunning == true }

  static func gpuRunPath() -> String? {
    for p in [NSHomeDirectory() + "/.local/bin/gpu-run", "/opt/homebrew/bin/gpu-run", "/usr/local/bin/gpu-run"] where FileManager.default.isExecutableFile(atPath: p) { return p }
    return nil
  }

  /// Blocks until the slot is granted; `onWait` receives progress lines ("warte auf GPU …").
  public func acquire(onWait: @escaping (String) -> Void) throws {
    if held { return }
    guard let g = gpuRun ?? Self.gpuRunPath() else { throw SLError("gpu-run nicht gefunden") }
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("sl-lease-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    let keep = d.appendingPathComponent("keep").path, ready = d.appendingPathComponent("ready").path
    FileManager.default.createFile(atPath: keep, contents: Data())
    let p = Process()
    p.executableURL = URL(fileURLWithPath: g)
    let holder = #"echo $$ > "$1"; while [ -e "$2" ] && kill -0 "$3" 2>/dev/null; do sleep 1; done"#
    p.arguments = ["-n", label, "--ram", String(ram), "sh", "-c", holder, "sl-holder", ready, keep, String(getpid())]
    let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
    err.fileHandleForReading.readabilityHandler = { h in
      let s = String(decoding: h.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      if !s.isEmpty { onWait(s.hasPrefix("gpu-run:") ? "warte auf GPU … (\(s.dropFirst(8).trimmingCharacters(in: .whitespaces)))" : s) }
    }
    onWait("warte auf GPU …")
    try p.run()
    proc = p; dir = d
    while !FileManager.default.fileExists(atPath: ready) {
      if !p.isRunning { err.fileHandleForReading.readabilityHandler = nil; cleanup(); throw SLError("gpu-run beendet ohne Slot") }
      Thread.sleep(forTimeInterval: 0.3)
    }
    err.fileHandleForReading.readabilityHandler = nil
    onWait("GPU-Slot erhalten")
  }

  /// Gives the slot back (idle unload / quit).
  public func release() {
    guard let p = proc else { return }
    if let d = dir { try? FileManager.default.removeItem(at: d.appendingPathComponent("keep")) }   // holder notices within 1 s and exits -> gpu-run cleans the lock
    let t0 = Date()
    while p.isRunning && Date().timeIntervalSince(t0) < 6 { Thread.sleep(forTimeInterval: 0.2) }
    if p.isRunning { p.terminate() }   // our own gpu-run wrapper (its trap forwards TERM to the holder)
    p.waitUntilExit()
    cleanup()
  }
  func cleanup() { if let d = dir { try? FileManager.default.removeItem(at: d) }; proc = nil; dir = nil }
  deinit { release() }
}
