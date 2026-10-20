import Foundation
import Schicksal

/// Deterministic action gate (round 4): risky and lethal actions are resolved by the harness BEFORE the narrator runs, with an
/// on-topic oracle question built from a template. The narrator then only gets the result as a hard fact (like /frage).
public enum ActionClass: Equatable { case kill, risky(Art) }

private func has(_ t: String, _ l: [String]) -> Bool { l.contains { t.contains($0) } }

public func classifyAction(_ text: String) -> ActionClass? {
  let t = " " + text.lowercased() + " "
  let nonCombat = ["buch ", "karte ", "kapitel", "zelt", "lager auf", "seite ", "tür zu", "fenster"]
  let kill = ["erstech", "ersteche", "erdolch", "erschieß", "erschiess", "schieße", "schiesse", "erschlag", "erschlage", "töte ", "töten", "ermord", "erwürg", "erdrossel", "enthaupt", "köpfe", "kehle", "ins herz", "umbring", "bringe ihn um", "bringe sie um", "meuchel", "ersteh", "erhäng", "dolch in", "messer in", "steche ", "in die brust", "in den rücken", "in den bauch", "schlitze", "ramme", "durchbohr"]
  if has(t, kill) && !has(t, ["töte die zeit", "töte zeit"]) { return .kill }
  let combat = ["kämpf", "angreif", "greife", " an,", "schlage ", "schlag ", "trete ", "ringe ", "prügel", "verprügel", "stürme", "attackier", "würge", "hieb", "stoße ", "werfe ", "ziele auf", "zücke"]
  if has(t, combat) && !has(t, nonCombat) && !has(t, [" an ", " an."]) || has(t, ["greife", "greife ", "angreife"]) { return .risky(.kampf) }
  if has(t, ["überred", "überzeug", "belüg", "lüge ", "bluffe", "verhandle", "bestech", "einschüchter", "drohe ", "bedrohe", "betrüge", "täusche", "feilsche", "schmeichle", "erpresse", "verkleide", "gebe mich als", "fälsche", "verführe"]) { return .risky(.sozial) }
  if has(t, ["stehle", "klaue", "stibitze", "entwende", "taschendieb", "unbemerkt", "heimlich nehme", "schnappe mir heimlich", "stecke heimlich"]) { return .risky(.sonst) }
  if has(t, ["aufbrech", "breche", "eintret", "trete die tür", "trete das tor", "schloss knack", "knacke", "aufstemm", "durchbrech", "sprenge", "schlosses", "gitter"]) && !has(t, ["breche das brot", "breche auf"]) { return .risky(.sonst) }
  if has(t, ["schleich", "springe", "sprang", "klettere", "kletter", "schwimme", "tauche", "balanc", "renne ", "fliehe", "überquere", "abseil", "hinüber", "verstecke mich", "weiche aus", "anschleich", "krieche", "rutsche", "seil", "klettern"]) { return .risky(.sonst) }
  if has(t, ["entziffer", "entschlüssel", "analysier", "identifizier", "recherchier"]) { return .risky(.wissen) }
  return nil
}
/// compatibility wrapper
public func riskArt(_ text: String) -> Art? { if case .risky(let a)? = classifyAction(text) { return a }; if classifyAction(text) == .kill { return .kampf }; return nil }

extension World {
  /// the NPC an action is aimed at: named or role-named in the input, else the single present NPC
  public func actionTarget(_ text: String) -> Int? {
    let p = text.lowercased()
    let present = npcs.indices.filter { npcs[$0].anwesend && !npcs[$0].tot }
    for i in present.sorted(by: { npcs[$0].name.count > npcs[$1].name.count }) {
      let ts = tokens(npcs[i].name) + roleTokens(i) + tokens(npcs[i].kurz).filter { $0.count >= 5 }
      if ts.contains(where: { p.contains($0) }) { return i }
    }
    return present.count == 1 ? present[0] : nil
  }
  /// odds of a lethal attack from the situation: surprise / vital spot / unarmed victim up, armed victim down
  public func killOdds(_ text: String, target i: Int?) -> Int {
    let p = text.lowercased(); var o = 0
    if has(p, ["von hinten", "schlafend", "im schlaf", "überraschend", "unbemerkt", "heimlich", "ahnungslos"]) { o += 1 }
    if has(p, ["ins herz", "kehle", "genick", "hals"]) { o += 1 }
    if let i { let k = npcs[i].kurz.lowercased()
      if has(k, ["wache", "söldner", "hauptmann", "waffenmeister", "krieger", "ritter", "jäger", "kämpfer", "leibwächter", "soldat"]) { o -= 1 }
      else if has(k, ["wirt", "händler", "priester", "bauer", "schreiber", "magd", "knecht", "bettler", "heiler", "mönch", "nonne", "archivar", "bäcker", "müller", "fischer", "kräuter", "gelehrt"]) { o += 1 } }
    return max(-2, min(2, o))
  }
}

extension Game {
  /// Resolves a risky/lethal action with the oracle before the narrator. Returns the extra user text (oracle result + hard facts) and the result.
  func resolveAction(_ player: String, _ cls: ActionClass) -> (text: String, res: J)? {
    let target = world.actionTarget(player)
    let name = target.map { world.npcs[$0].name }
    var art = Art.kampf, q: String, odds = 0
    switch cls {
    case .kill: q = name.map { "Ist der Angriff auf \($0) tödlich?" } ?? "Ist der Angriff tödlich?"; odds = world.killOdds(player, target: target)
    case .risky(let a):
      art = a
      var act = player.trimmingCharacters(in: .whitespacesAndNewlines); while let l = act.last, ".!?".contains(l) { act.removeLast() }
      q = "Gelingt meine Handlung (\(clean(act, 80)))?"
    }
    var rel = 0
    if let t = target, art == .sozial { rel = world.npcs[t].haltung }                // a beaten / hostile NPC is hard to talk round
    let rs = regel.oddsShift(art: art, pc: world.pc, input: player)
    var args: J = ["q": .str(q), "odds": .int(odds)]
    if var o = args.obj, let sh = combinedShift(haltung: rel == 0 ? nil : rel, regel: rs) { o["shift"] = .int(sh); args = .obj(o) }
    lastArt = art; lastOracleQ = q
    let res = eng.call("ask_oracle", args)
    guard res["error"].isNull, let ans = res["answer"].str else { return nil }
    out(.tool("ask_oracle", args, res))
    if let e = evInfo("ask_oracle", res) { out(.event(evShow(e))) }
    turnQA.append((q, ans))
    if ans.hasPrefix("NEIN") { sceneNein += 1 } else { sceneJa += 1 }
    if !res["event"].isNull { sceneEvents += 1 }
    var fb = fmtResult("ask_oracle", res)
    var facts: [String] = []
    if let t = target, cls == .kill || art == .kampf {            // an attack makes the victim hostile whatever the result
      let hit = ans.hasPrefix("JA")
      var l = world.setHaltung(t, hit || cls == .kill ? -2 : min(world.npcs[t].haltung, -1))
      if cls == .kill {
        if hit { l += world.kill(t); facts.append("[Fakt] \(world.npcs[t].name) ist tot. Erzähle den Tod ausdrücklich: er fällt, regt sich nicht mehr.") }
        else if ans == "NEIN" { if !world.npcs[t].zustand.contains("verletzt") { world.npcs[t].zustand.append("verletzt") }; facts.append("[Fakt] \(world.npcs[t].name) überlebt den Angriff, ist aber verletzt. Erzähle die Verletzung, nicht den Tod.") }
        else { facts.append("[Fakt] Der Angriff geht fehl, \(world.npcs[t].name) bleibt unverletzt. Erzähle das Scheitern, nicht den Tod.") }
      }
      if !l.isEmpty { out(.world(l.joined(separator: " · "))) }
    } else if cls == .kill {
      facts.append(ans.hasPrefix("JA") ? "[Fakt] Der Angriff ist tödlich. Erzähle den Tod ausdrücklich." : "[Fakt] Der Angriff trifft nicht tödlich. Erzähle das ausdrücklich.")
    }
    if !facts.isEmpty { fb += "\n" + facts.joined(separator: "\n") }
    return (fb, res)
  }
}
