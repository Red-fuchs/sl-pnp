import Foundation
import Schicksal

/// Thread-safe party store: the Foundry bridge rolls and spends SP while a turn may be running.
public final class PartyStore: @unchecked Sendable {
  public let lock = NSRecursiveLock()
  var pcs: [Pc] = []
  public init() {}
  public func with<T>(_ f: (inout [Pc]) -> T) -> T { lock.lock(); defer { lock.unlock() }; return f(&pcs) }
  public var all: [Pc] { with { $0 } }
  /// Wunden edited from outside (Foundry): `set` wins over `delta`; clamped to -5...wundenMax. nil = unknown speaker.
  public func wunden(speaker: String, delta: Int?, set: Int?) -> [String: Any]? {
    with { p in
      guard let i = p.firstIndex(where: { norm($0.speaker) == norm(speaker) || norm($0.name) == norm(speaker) }) else { return nil }
      let v = set ?? (p[i].wunden + (delta ?? 0)); p[i].wunden = max(-5, min(p[i].wundenMax, v))
      return ["name": p[i].name, "wunden": p[i].wunden, "wundenMax": p[i].wundenMax]
    }
  }
}

public extension Game {
  var isSchicksal: Bool { world.regeln == "schicksal" }

  /// index of the speaker's sheet (created on first use); nil speaker = the single player
  @discardableResult
  func pcIndex(_ speaker: String?, create: Bool = true) -> Int? {
    let key = (speaker?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? (world.name ?? "Spieler")
    return partyStore.with { p -> Int? in
      if let i = p.firstIndex(where: { norm($0.speaker) == norm(key) || norm($0.name) == norm(key) }) { return i }
      guard create else { return nil }
      p.append(Pc(speaker: key, name: key)); return p.count - 1
    }.map { i in if create { announceSheet() }; return i }
  }
  func announceSheet() { out(.sheet) }
  var partyJSON: [[String: Any]] { partyStore.all.map(\.json) }

  /// d100 (1...100) from the schicksal engine's RNG
  func d100() -> Int { rnd(100) + 1 }

  /// harness check (POST /roll, or an action under `schicksal`)
  @discardableResult
  func doCheck(speaker: String?, pillar: String, traits: [String] = [], difficulty: Int = 0, sp: Int = 0, reason: String = "", context: String = "") -> Check {
    let i = pcIndex(speaker)!
    let c: Check = partyStore.with { p in
      var pc = p[i]
      let fit = SR.fitting(reason + " " + context + " " + traits.joined(separator: " "), pc.traits)
      let r = SR.check(&pc, pillar: pillar, traits: fit, difficulty: difficulty, spUse: sp, reason: reason, d100: d100())
      p[i] = pc; return r
    }
    out(.roll(c)); announceSheet()
    return c
  }
  /// a roll made in Foundry: degrees computed here, queued as a fact for the next narration
  func foundryRoll(speaker: String?, label: String, target: Int, roll: Int) -> Check {
    var c = Check(); c.speaker = speaker ?? ""; c.reason = label; c.target = target; c.roll = roll; c.source = "foundry"
    (c.success, c.dos, c.dof, c.crit) = SR.degrees(target: target, roll: roll)
    if let i = pcIndex(speaker, create: false) { c.speaker = partyStore.with { $0[i].name }; c.spLeft = partyStore.with { $0[i].sp } }
    pendingFacts.append(c.fact); out(.roll(c))
    return c
  }

  /// SP on a sheet. mode: adjust (default) | pre | reroll | orakel | survive; target = another member / NPC name
  func applySP(speaker: String?, delta: Int, target: String? = nil, mode: String? = nil) -> [String: Any]? {
    guard let i = pcIndex(speaker, create: false) else { return nil }
    let m = mode ?? "adjust"
    if m == "wunden" { let r = partyStore.wunden(speaker: speaker ?? "", delta: delta, set: nil); announceSheet(); return r }
    var err: String?
    let res: [String: Any] = partyStore.with { p in
      var pc = p[i]
      switch m {
      case "pre":
        let n = max(0, min(3 - pc.pendingSp, min(delta, pc.sp))); pc.pendingSp += n
      case "orakel":
        let n = max(0, min(delta, pc.sp)); pc.sp -= n; pc.pendingOracle += n
      case "survive":
        if pc.sp >= 1 && pc.wunden <= 0 { pc.sp -= 1; pc.wunden = 0 } else { err = "überleben braucht 1 SP und 0 Wunden" }
      case "reroll":
        if pc.sp >= 2, var last = pc.lastCheck { pc.sp -= 2; let r = d100(); last.roll = r; (last.success, last.dos, last.dof, last.crit) = SR.degrees(target: last.target, roll: r); last.spLeft = pc.sp; last.reason += " (Neuwurf)"; pc.lastCheck = last; pendingFacts.append(last.fact); self.out(.roll(last)) } else { err = "Neuwurf braucht 2 SP und eine vorherige Probe" }
      default:
        if let t = target, !t.isEmpty {       // spend SP on someone else's next check: 1 SP = +-10
          let n = min(abs(delta), pc.sp); pc.sp -= n
          if let j = p.firstIndex(where: { norm($0.name) == norm(t) || norm($0.speaker) == norm(t) }), j != i { p[j].mod += (delta >= 0 ? 10 : -10) * n }
          else { npcMods[norm(t), default: 0] += (delta >= 0 ? 10 : -10) * n }
        } else { pc.sp = max(0, min(pc.spMax, pc.sp + delta)) }
      }
      p[i] = pc
      return ["name": pc.name, "sp": pc.sp, "spMax": pc.spMax, "pending": pc.pendingSp]
    }
    announceSheet()
    if let e = err { out(.info(e)); return res.merging(["error": e]) { a, _ in a } }
    return res
  }
  /// how many odds steps SP changes for this speaker's next oracle question (pending SP spent, SP 0 = one worse); consumes the pending steps
  func spOracleShift(_ speaker: String?) -> Int {
    guard isSchicksal, let i = pcIndex(speaker, create: false) else { return 0 }
    return partyStore.with { p in let s = p[i].pendingOracle - (p[i].sp == 0 ? 1 : 0); p[i].pendingOracle = 0; return s }
  }
  /// party-wide recovery (rest, feast, thread solved)
  func partyGain(sp: Int, wunden: Int = 0) { partyStore.with { p in for i in p.indices { p[i].sp = min(p[i].spMax, p[i].sp + sp); p[i].wunden = min(p[i].wundenMax, p[i].wunden + wunden) } }; announceSheet() }
  var partyBlock: String {
    let p = partyStore.all; guard isSchicksal, !p.isEmpty else { return "" }
    return "Gruppe: " + p.map { "\($0.name) (SP \($0.sp)/\($0.spMax), Wunden \($0.wunden)/\($0.wundenMax)\($0.wunden <= 3 ? ", schwer verletzt" : ""))" }.joined(separator: " | ")
  }

  // MARK: action resolution under `schicksal`
  func resolveSchicksal(_ player: String, _ cls: ActionClass, target: Int?, speaker: String?) -> (text: String, res: J?)? {
    let kill = cls == .kill
    var pillar = "kampf", dif = 0
    if case .risky(let a) = cls { pillar = a == .sonst ? "kampf" : a.rawValue }
    if kill { dif = 10 * world.killOdds(player, target: target) }
    let c = doCheck(speaker: speaker, pillar: pillar, difficulty: dif, reason: SR.shortReason(player), context: player)
    var facts = [c.fact]
    if let t = target, kill || pillar == "kampf", cls != .risky(.sozial) {
      let name = world.npcs[t].name
      var l = world.setHaltung(t, -2)
      if c.success {
        let dmg = max(0, SR.weaponDamage(player) + c.dos - SR.armour(role: world.npcs[t].kurz))
        let hp = (world.npcs[t].wunden ?? 6) - dmg
        world.npcs[t].wunden = max(0, hp)
        if hp <= 0 { l += world.kill(t); facts.append("[Fakt] \(name) ist tot (Schaden \(dmg)). Erzähle den Tod ausdrücklich.") }
        else { if !world.npcs[t].zustand.contains("verletzt") { world.npcs[t].zustand.append("verletzt") }; facts.append("[Fakt] \(name) wird getroffen (Schaden \(dmg)) und lebt noch, verletzt. Erzähle die Verletzung, nicht den Tod.") }
      } else if c.dof >= 2 || c.crit == "failure" {
        let dmg = 2 + (c.crit == "failure" ? 1 : 0)
        if let i = pcIndex(speaker, create: false) {
          let now: Int = partyStore.with { p in p[i].wunden -= dmg; return p[i].wunden }
          facts.append("[Fakt] Gegenschlag von \(name): \(partyStore.all[i].name) verliert \(dmg) Wunden (jetzt \(max(0, now)))." + (now <= 0 ? " Die Figur geht zu Boden; nur ein Schicksalspunkt hält sie am Leben." : ""))
          announceSheet()
        }
      } else { facts.append("[Fakt] Der Angriff auf \(name) geht fehl, \(name) bleibt unverletzt.") }
      if !l.isEmpty { out(.world(l.joined(separator: " · "))) }
    }
    return (facts.joined(separator: "\n"), nil)
  }

  // MARK: character creation
  /// background story -> traits (grammar enum minor/major, pos/neg) -> budget 20 -> pillars 30/40/50 -> leftover as Taler
  @discardableResult
  func createCharacter(speaker: String?, name: String, story: String) -> [Trait] {
    let i = pcIndex(speaker)!
    var traits: [Trait] = []
    // two passes: a single pass made the model list only a few skills and skip flaws and debts
    func line(_ key: String) -> G { G.seq([.s("\(key): "), .re(Cls.rep(Cls.lineNoQ, 6)), .s("| "), GenGr.en(["minor", "major"])]) }
    func opt(_ key: String) -> G { G.or([.s(""), .seq([.s("\n"), line(key)])]) }
    let posG = Grammar(.seq([line("Merkmal"), .s("\n"), line("Merkmal"), opt("Merkmal"), opt("Merkmal"), opt("Merkmal"), opt("Merkmal"), opt("Merkmal")]))
    let negG = Grammar(.seq([.or([line("Schwäche"), .s("Schwäche: -")]), opt("Schwäche"), opt("Schwäche"), opt("Schwäche")]))
    let posSys = "Du extrahierst aus einer Hintergrundgeschichte alle positiven Merkmale der Figur als kurze Wendungen (2 bis 5 Wörter): Fertigkeiten, Begabungen, Berufe, Kontakte, Freunde, Titel. Jede Fertigkeit und jeden Kontakt einzeln nennen. Format je Zeile: Merkmal: <Text> | minor oder major. major = prägend, minor = beiläufig. Nur Dinge, die in der Geschichte stehen."
    let negSys = "Du extrahierst aus einer Hintergrundgeschichte alle Schwächen der Figur als kurze Wendungen (2 bis 5 Wörter): Fehler, Süchte, Schulden, Feinde, Ängste (auch „ich fürchte X“), Gebrechen, Verfolger, Verletzungen. Format je Zeile: Schwäche: <Text> | minor oder major. Gibt es keine, antworte genau: Schwäche: -"
    let st = clean(story, 700)
    let posEx = "Beispiel:\nGeschichte: Ich war Bogenschütze der Stadtwache, bis ich beim Würfeln meinen Sold verlor. Seitdem schulde ich dem Wirt Geld und trinke zu viel.\nAusgabe:\nMerkmal: geübter Bogenschütze | major\nMerkmal: Stadtwache gedient | minor"
    let negEx = "Beispiel:\nGeschichte: Ich war Bogenschütze der Stadtwache, bis ich beim Würfeln meinen Sold verlor. Seitdem schulde ich dem Wirt Geld und trinke zu viel.\nAusgabe:\nSchwäche: Spielsucht | major\nSchwäche: Schulden beim Wirt | minor\nSchwäche: trinkt zu viel | minor"
    do { let (txt, _) = try lm.aux(system: posSys, user: "\(posEx)\n\nGeschichte: \(st)\nAusgabe:", posG, temp: 0.3, maxTok: 450); traits += SR.parseTraits(txt, pos: true) } catch { out(.info("Merkmal-Extraktion (Stärken) fehlgeschlagen: \(error) \((error as? TruncatedError)?.partial.prefix(300) ?? "")")) }
    do { let (txt, _) = try lm.aux(system: negSys, user: "\(negEx)\n\nGeschichte: \(st)\nAusgabe:", negG, temp: 0.3, maxTok: 300); traits += SR.parseTraits(txt, pos: false) } catch { out(.info("Merkmal-Extraktion (Schwächen) fehlgeschlagen: \(error)")) }
    return setTraits(i, name: name, story: story, traits: SR.dedupe(traits))
  }
  /// pure part (testable): budget fit, pillars, Taler
  @discardableResult
  func setTraits(_ i: Int, name: String, story: String, traits: [Trait]) -> [Trait] {
    let d = partyStore.with { p in SR.build(&p[i], name: name, story: story, traits: traits) }
    announceSheet(); return d
  }
  func applyBudget(_ i: Int, args: String) -> String {
    let m = partyStore.with { p in SR.budget(&p[i], args: args) }
    announceSheet(); return m
  }
}
