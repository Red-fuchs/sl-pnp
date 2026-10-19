import Foundation
import Schicksal

public let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/Claude-Workspace/gm-bench/sl-sessions")

struct Chat: Codable { var setting: String; var msgs: [Msg]; var figur: String? = nil; var quiet: Int? = nil }

/// Persistent session dir: state.json (schicksal), chat.json (history), transcript.md.
public final class Session {
  public let dir: URL
  public let name: String
  var lockFD: Int32 = -1
  /// `mustExist`: resume of an unknown name must not create an empty dir. Holds an exclusive flock on state.json.lock (same convention as the schicksal CLI).
  public init(name: String, root: URL = sessionsRoot, mustExist: Bool = false) throws {
    self.name = name; dir = root.appendingPathComponent(name)
    if mustExist && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("chat.json").path) { throw SLError("Sitzung nicht gefunden: \(name)") }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    lockFD = open(dir.appendingPathComponent("state.json.lock").path, O_CREAT | O_RDWR, 0o644)
    if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 { close(lockFD); lockFD = -1; throw SLError("Sitzung \(name) ist von einem anderen Prozess gesperrt") }
  }
  deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
  var statePath: String { dir.appendingPathComponent("state.json").path }
  var chatURL: URL { dir.appendingPathComponent("chat.json") }
  var worldURL: URL { dir.appendingPathComponent("world.json") }
  var mdURL: URL { dir.appendingPathComponent("transcript.md") }
  public var exists: Bool { FileManager.default.fileExists(atPath: statePath) && FileManager.default.fileExists(atPath: chatURL.path) }

  public static func latest(root: URL = sessionsRoot) -> String? {
    let fm = FileManager.default
    let ds = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    return ds.filter { fm.fileExists(atPath: $0.appendingPathComponent("chat.json").path) }
      .max { (try? $0.appendingPathComponent("chat.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
           < (try? $1.appendingPathComponent("chat.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }?
      .lastPathComponent
  }

  public static func newEngine(rng: String) throws -> Engine {
    let e = Engine(rng: rng.hasPrefix("seed:") ? "seed" : rng, fallback: "jitter"); e.machine = true
    var a: J = ["op": "new", "rng": .str(rng), "ev_mode": "adaptiv"]
    if rng.hasPrefix("seed:"), let n = Int(rng.dropFirst(5)) { a = ["op": "new", "rng": "seed", "seed": .int(n), "ev_mode": "adaptiv"] }
    let r = e.call("session", a)
    if let err = r["error"].str { throw SLError(err) }
    return e
  }
  public func loadEngine() throws -> (Engine, setting: String, msgs: [Msg], figur: String?, quiet: Int, world: World) {
    let e = try Engine.load(path: statePath); e.machine = true
    let c = try JSONDecoder().decode(Chat.self, from: Data(contentsOf: chatURL))
    let w = (try? JSONDecoder().decode(World.self, from: Data(contentsOf: worldURL))) ?? World()
    return (e, c.setting, c.msgs, c.figur, c.quiet ?? 0, w)
  }
  public func save(_ g: Game) throws { try save(g.eng, g.setting, g.msgs, g.figur, g.quiet, g.world) }
  public func save(_ e: Engine, _ setting: String, _ msgs: [Msg], _ figur: String? = nil, _ quiet: Int = 0, _ world: World = World()) throws {
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
    try enc.encode(world).write(to: worldURL, options: .atomic)
    try e.save(path: statePath)
    try JSONEncoder().encode(Chat(setting: setting, msgs: msgs, figur: figur, quiet: quiet)).write(to: chatURL, options: .atomic)
  }
  public func log(_ s: String) {
    if !FileManager.default.fileExists(atPath: mdURL.path) { FileManager.default.createFile(atPath: mdURL.path, contents: nil) }
    if let h = try? FileHandle(forWritingTo: mdURL) { h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close() }
  }
}
