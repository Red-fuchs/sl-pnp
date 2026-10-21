import Foundation
import Schicksal

/// Deterministic action gate (round 4): risky and lethal actions are resolved by the harness BEFORE the narrator runs, with an
/// on-topic oracle question built from a template. The narrator then only gets the result as a hard fact (like /frage).
public enum ActionClass: Equatable { case kill, selfHarm, risky(Art) }

private func has(_ t: String, _ l: [String]) -> Bool { l.contains { t.contains($0) } }
private func words(_ t: String) -> [String] { t.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) }

/// Verb classes with object cues (no bare nouns: "meine Kehle ist trocken", "greife nach dem Becher", "werfe einen Blick" stay trivial).
public func classifyAction(_ text: String) -> ActionClass? {
  let w = words(text), t = " " + text.lowercased() + " "
  func verb(_ stems: [String]) -> Bool { w.contains { x in stems.contains { x.hasPrefix($0) } } }
  func exact(_ vs: [String]) -> Bool { w.contains { vs.contains($0) } }
  func next(_ v: [String], in ws: [String]) -> String? { for (i, x) in ws.enumerated() where v.contains(x) { return i + 1 < ws.count ? ws[i + 1] : "" }; return nil }
  let selfRef = exact(["mich", "mir", "selbst"])
  let personCue = exact(["ihn", "ihm", "sie", "ihr", "den", "dem", "die", "einen", "seinen", "ihren"]) || text.split(separator: " ").dropFirst().contains { $0.first?.isUppercase == true }
  // --- lethal: strong verb, or weak verb + lethal complement
  let strong = verb(["erstech", "ersteche", "erdolch", "erschieß", "erschiess", "erschlag", "töte", "töten", "ermord", "erwürg", "erdrossel", "enthaupt", "meuchel", "erhäng", "umbring", "durchbohr"]) || (exact(["bringe"]) && exact(["um"]))
  let weak = exact(["steche", "ramme", "stoße", "schlitze", "schieße", "schiesse", "köpfe", "schneide", "hacke", "stich", "stoss"]) && has(t, ["kehle", "ins herz", "in die brust", "in den hals", "in den rücken", "in den bauch", "nieder", "tödlich", "den schädel"])
  if strong || weak { return selfRef ? .selfHarm : (personCue ? .kill : nil) }
  // --- combat: attack verb + target
  let nonCombat = ["buch", "karte", "kapitel", "seite", "zelt", "lager", "feuer", "funken"]
  if verb(["kämpf", "angreif", "attackier", "prügel", "verprügel", "würge"]) || (exact(["greife"]) && exact(["an"])) { return .risky(.kampf) }
  if let n = next(["schlage", "schlag"], in: w), !w.contains(where: { nonCombat.contains($0) }), !w.contains("auf"), ["ihn", "ihm", "den", "die", "dem", "sie", "ihr", "nach"].contains(n) || text.split(separator: " ").dropFirst().contains(where: { $0.first?.isUppercase == true }) { return .risky(.kampf) }
  if let n = next(["trete"], in: w), ["nach", "ihn", "den", "dem", "ihm"].contains(n), !w.contains("näher") { return .risky(.kampf) }
  if exact(["stürme"]) && exact(["auf", "los", "ihn"]) || (exact(["ziele"]) && exact(["auf"])) { return .risky(.kampf) }
  // --- social
  if verb(["überred", "überzeug", "belüg", "bluff", "verhandel", "bestech", "einschüchter", "bedroh", "betrüg", "täusch", "feilsch", "schmeichel", "erpress", "verkleid", "fälsch"]) || exact(["lüge", "drohe"]) || (exact(["gebe"]) && exact(["mich"]) && exact(["als"])) { return .risky(.sozial) }
  // --- theft
  if verb(["stehle", "klaue", "stibitz", "entwend", "taschendieb"]) || exact(["unbemerkt"]) || (exact(["nehme", "stecke", "schnappe"]) && exact(["heimlich"])) { return .risky(.sonst) }
  // --- force
  if verb(["aufbrech", "aufstemm", "durchbrech", "sprenge"]) || (exact(["breche"]) && exact(["auf"]) && !exact(["brot", "lager", "zelt"])) || (exact(["trete"]) && exact(["ein"]) && exact(["tür", "tor", "pforte"])) || verb(["knack"]) { return .risky(.sonst) }
  // --- movement
  if verb(["schleich", "springe", "sprang", "klettere", "kletter", "schwimme", "tauche", "balanc", "fliehe", "überquere", "abseil", "anschleich", "krieche"]) || exact(["renne", "rutsche"]) || (exact(["verstecke"]) && exact(["mich"])) || (exact(["weiche"]) && exact(["aus"])) { return .risky(.sonst) }
  // --- knowledge
  if verb(["entziffer", "entschlüssel", "analysier", "identifizier", "recherchier"]) { return .risky(.wissen) }
  return nil
}
/// compatibility wrapper
public func riskArt(_ text: String) -> Art? { switch classifyAction(text) { case .risky(let a)?: return a; case .kill?: return .kampf; default: return nil } }

extension World {
  /// Who an action is aimed at. Names/roles are matched over ALL npcs (absent/dead ones included); the single-present fallback only fires
  /// for a bare pronoun ("ihn", "sie") and prefers the NPC of the previous action.
  public enum Target: Equatable { case npc(Int), absent(Int), dead(Int), selfRef, none }
  public func resolveTarget(_ text: String, last: String? = nil) -> Target {
    let p = text.lowercased()
    var best: (pos: String.Index, i: Int)?
    for i in npcs.indices {
      let ts = tokens(npcs[i].name) + roleTokens(i) + (tokens(npcs[i].kurz).first.map { $0.count >= 4 ? [$0] : [] } ?? [])
      for t in ts { if let r = p.range(of: t), best == nil || r.lowerBound < best!.pos { best = (r.lowerBound, i) } }
    }
    if let (_, i) = best { return npcs[i].tot ? .dead(i) : (npcs[i].anwesend ? .npc(i) : .absent(i)) }
    let ws = Set(p.split(whereSeparator: { !$0.isLetter }).map(String.init))
    if !ws.isDisjoint(with: ["mich", "mir", "selbst"]) { return .selfRef }
    if !ws.isDisjoint(with: ["ihn", "ihm", "sie", "ihr"]) {
      let present = npcs.indices.filter { npcs[$0].anwesend && !npcs[$0].tot }
      if let l = last, let i = present.first(where: { npcs[$0].id == l }) { return .npc(i) }
      if present.count == 1 { return .npc(present[0]) }
    }
    return .none
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
  /// Resolves a risky/lethal action with the oracle before the narrator. Returns the extra user text (hard facts / oracle result); `res` is nil when
  /// no oracle was needed (absent, dead or self targets).
  func resolveAction(_ player: String, _ cls: ActionClass) -> (text: String, res: J?)? {
    if cls == .selfHarm { return ("[Fakt] Die Spielfigur zögert im letzten Moment: zeige das Zögern, keine Selbstverletzung, keine Methoden.", nil) }
    let tg = world.resolveTarget(player, last: lastTargetId)
    var target: Int?, named = false
    switch tg {
    case .absent(let i): if cls == .kill || cls == .risky(.kampf) { return ("[Fakt] \(world.npcs[i].name) ist nicht hier. Die Handlung läuft ins Leere; erzähle das.", nil) }
    case .dead(let i): if cls == .kill || cls == .risky(.kampf) { return ("[Fakt] \(world.npcs[i].name) ist bereits tot. Erzähle, dass die Leiche daliegt.", nil) }
    case .npc(let i): target = i; named = !(player.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).contains { ["ihn", "ihm", "sie", "ihr"].contains($0) } && !world.npcs[i].name.isEmpty && !player.lowercased().contains(world.npcs[i].name.lowercased()))
    default: break
    }
    if let t = target, world.npcs[t].minor { return nil }                  // belt and braces: the content rule deflects before this point
    if let t = target { lastTargetId = world.npcs[t].id }
    if isSchicksal, cls != .selfHarm { return resolveSchicksal(player, cls, target: target, speaker: speaker) }
    let name = target.map { world.npcs[$0].name }
    var art = Art.kampf, q: String, odds = 0
    switch cls {
    case .kill: q = name.map { "Ist der Angriff auf \($0) tödlich?" } ?? "Ist der Angriff tödlich?"; odds = world.killOdds(player, target: target)
    case .risky(let a):
      art = a
      var act = player.trimmingCharacters(in: .whitespacesAndNewlines); while let l = act.last, ".!?".contains(l) { act.removeLast() }
      q = "Gelingt meine Handlung (\(clean(act, 80)))?"
    case .selfHarm: return nil
    }
    var rel = 0
    if let t = target, art == .sozial { rel = world.npcs[t].haltung }                // a beaten / hostile NPC is hard to talk round
    let rs = regel.oddsShift(art: art, pc: world.pc, input: player) + spOracleShift(speaker)
    var args: J = ["q": .str(q), "odds": .int(odds)]
    if var o = args.obj, let sh = combinedShift(haltung: rel == 0 ? nil : rel, regel: rs) { o["shift"] = .int(sh); args = .obj(o) }
    lastOracleQ = q
    if world.regeln == "saeulen" { lastArt = art }
    let res = eng.call("ask_oracle", args)
    guard res["error"].isNull, let ans = res["answer"].str else { return nil }
    out(.tool("ask_oracle", args, res))
    if let e = evInfo("ask_oracle", res) { out(.event(evShow(e))) }
    turnQA.append((q, ans))
    if ans.hasPrefix("NEIN") { sceneNein += 1 } else { sceneJa += 1 }
    if !res["event"].isNull { sceneEvents += 1 }
    var fb = fmtResult("ask_oracle", res)
    var facts: [String] = []
    let hit = ans.hasPrefix("JA")
    if let t = target, cls == .kill || (named && art == .kampf) {            // an attack makes the (named) victim hostile whatever the result
      var l = world.setHaltung(t, hit || cls == .kill ? -2 : min(world.npcs[t].haltung, -1))
      if cls == .kill {
        if hit { l += world.kill(t); facts.append("[Fakt] \(world.npcs[t].name) ist tot. Erzähle den Tod ausdrücklich: er fällt, regt sich nicht mehr.") }
        else if ans == "NEIN" { if !world.npcs[t].zustand.contains("verletzt") { world.npcs[t].zustand.append("verletzt") }; facts.append("[Fakt] \(world.npcs[t].name) überlebt den Angriff, ist aber verletzt. Erzähle die Verletzung, nicht den Tod.") }
        else { facts.append("[Fakt] Der Angriff geht fehl und \(world.npcs[t].name) schlägt zurück: die Spielfigur ist verletzt, \(world.npcs[t].name) bleibt unverletzt. Erzähle das Scheitern, nicht den Tod.") }
      }
      if !l.isEmpty { out(.world(l.joined(separator: " · "))) }
    } else if cls == .kill {
      facts.append(hit ? "[Fakt] Der Angriff ist tödlich, aber niemand Bestimmtes steht da: erzähle ihn als Szene ohne benannte Figur." : "[Fakt] Der Angriff trifft nicht tödlich. Erzähle das ausdrücklich.")
    }
    if !facts.isEmpty { fb += "\n" + facts.joined(separator: "\n") }
    return (fb, res)
  }
}

// MARK: M2 claimed items
let itemList = ["schwert", "dolch", "messer", "bogen", "armbrust", "pistole", "gewehr", "revolver", "granate", "axt", "speer", "schild", "rüstung", "schlüssel", "dietrich", "seil", "fackel", "laterne", "trank", "elixier", "amulett", "ring", "karte", "buch", "zauberstab", "stab", "hammer", "brecheisen", "pfeife", "flöte", "laute", "beutel", "münzen", "gold", "brief", "siegel", "fernglas", "kompass", "werkzeug", "rucksack", "mantel", "umhang", "helm", "handschuhe", "stiefel", "kette", "glocke", "horn", "schaufel", "spaten", "kreuz", "handy", "laser", "bombe", "streitkolben", "keule", "säbel", "degen", "morgenstern", "pfeil", "pfeile", "bolzen", "bolzen"]
let anachronisms = ["pistole", "gewehr", "revolver", "granate", "handy", "laser", "bombe"]
let basicGear = ["messer", "beutel", "mantel", "umhang", "stiefel", "rucksack", "handschuhe", "seil", "fackel"]
let armedRoles = ["söldner", "krieger", "ritter", "jäger", "wache", "kämpfer", "soldat", "hauptmann", "waffenmeister", "leibwächter"]

/// "mein Schwert", "mit dem Dolch", "ziehe den Dolch": items the player claims to hold (allowlist only; never Hand/Augen/Stimme)
public func claimedItems(_ text: String) -> [String] {
  let pats = [#"\bmein(?:e|en|em|er|es)?\s+(\p{L}+)"#, #"\bmit\s+(?:dem|der|einem|einer|meinem|meiner|meinen)\s+(\p{L}+)"#, #"\b(?:ziehe|zücke|greife\s+zu|greife\s+nach|werfe|schwinge|hebe)\s+(?:den|die|das|mein\w*|einen|eine|ein)\s+(\p{L}+)"#]
  var out: [String] = []
  for p in pats {
    guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
    for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      if let r = Range(m.range(at: 1), in: text) { let w = text[r].lowercased(); if let it = itemList.first(where: { w == $0 || (w.count > $0.count && w.hasPrefix($0)) || (w.hasSuffix($0) && $0.count >= 5) }), !out.contains(it) { out.append(it) } }
    }
  }
  return out
}
extension World {
  /// claimed items the character demonstrably does not have (inventory / figure description / armed role / basic gear)
  public func missingItems(_ text: String) -> [String] {
    let have = (inventar + [kurz ?? "", name ?? ""]).joined(separator: " ").lowercased()
    let armed = armedRoles.contains { have.contains($0) }
    return claimedItems(text).filter { it in
      if have.contains(it) || have.contains(String(it.prefix(max(4, it.count - 2)))) { return false }
      if basicGear.contains(it) { return false }
      if armed, ["schwert", "dolch", "bogen", "armbrust", "axt", "speer", "schild", "rüstung", "helm", "säbel", "degen", "keule", "streitkolben", "pfeil", "pfeile", "bolzen"].contains(it) { return false }
      return true }
  }
}
extension Game {
  /// Oracle "Habe ich X dabei?" for a claimed item that is not in the inventory. JA adds it; NEIN is an in-fiction fact and cancels the action.
  func resolveClaim(_ player: String) -> (fact: String, res: J?, cancel: Bool)? {
    let own = (isSchicksal ? pcIndex(speaker, create: false).map { partyStore.all[$0].inventar } : nil)?.joined(separator: " ").lowercased() ?? ""
    guard let item = world.missingItems(player).first(where: { !own.contains($0) && !own.contains(String($0.prefix(max(4, $0.count - 2)))) }) else { return nil }
    let disp = item.prefix(1).uppercased() + item.dropFirst()
    let q = "Habe ich \(disp) dabei?", odds = anachronisms.contains(item) ? -3 : -2
    let args: J = ["q": .str(q), "odds": .int(odds)]
    let res = eng.call("ask_oracle", args)
    guard res["error"].isNull, let ans = res["answer"].str else { return nil }
    out(.tool("ask_oracle", args, res)); if let e = evInfo("ask_oracle", res) { out(.event(evShow(e))) }
    turnQA.append((q, ans)); lastOracleQ = q
    if ans.hasPrefix("JA") {
      if world.inventar.count < 8 { world.inventar.append(disp) }
      return ("[Orakel] Antwort: \(ans)\n[Fakt] Die Spielfigur hat \(disp) dabei.", res, false)
    }
    return ("[Orakel] Antwort: \(ans)\n[Fakt] Die Spielfigur hat kein \(disp) dabei: die Hand greift ins Leere. Erzähle das ausdrücklich; die Handlung gelingt nicht mit diesem Gegenstand.", res, true)
  }
}

// MARK: N7 dialogue and names
let speechRe = try! NSRegularExpression(pattern: #"\b(frage|frag|sage|sag|spreche|sprich|rufe|rede|flüstere|bitte|antworte|erkundige|erzähle|begrüße|grüße)\w*"#, options: .caseInsensitive)
let nameAskRe = try! NSRegularExpression(pattern: #"\b(wie heißt|wie heisst|wie nennt|wie lautet (?:dein|ihr|sein)\w* name|(?:dein|sein|ihr|eur)\w*\s+name\w*|stell\w* (?:dich|sich) vor|wer bist du)\b"#, options: .caseInsensitive)
/// a dialogue turn: the player speaks to / asks someone and a (living) NPC is present
public func isDialogueTurn(_ player: String, _ w: World) -> Bool {
  speechRe.firstMatch(in: player, range: NSRange(player.startIndex..., in: player)) != nil && w.npcs.contains { $0.anwesend && !$0.tot }
}
public func isNameAsk(_ player: String) -> Bool { nameAskRe.firstMatch(in: player, range: NSRange(player.startIndex..., in: player)) != nil }
extension World {
  /// a role label instead of a name ("Wache", "Händler", "Frau")
  public func isGenericName(_ i: Int) -> Bool {
    let n = npcs[i].name.lowercased()
    return GenGr.roles.contains { $0.lowercased() == n } || ["wache", "fremde", "fremder", "frau", "mann", "kind", "dorfbewohner", "unbekannter", "unbekannte", "alte", "alter"].contains(n) || (tokens(npcs[i].kurz).contains(n) && !n.isEmpty)
  }
}
extension Game {
  /// the player asks a present, still unnamed NPC for its name: the oracle decides ("Nennt X seinen Namen?"); JA assigns a generated name and registers it
  func resolveNameAsk(_ player: String) -> (fact: String, res: J)? {
    guard isNameAsk(player) else { return nil }
    let tg = world.resolveTarget(player, last: lastTargetId)
    guard case .npc(let i) = tg, world.isGenericName(i) else { return nil }
    let old = world.npcs[i].name
    let args: J = ["q": .str("Nennt \(old) den eigenen Namen?"), "odds": .int(0), "shift": .int(max(-2, min(2, world.npcs[i].haltung)))]
    let res = eng.call("ask_oracle", args)
    guard res["error"].isNull, let ans = res["answer"].str else { return nil }
    out(.tool("ask_oracle", args, res)); turnQA.append(("Nennt \(old) den eigenen Namen?", ans)); lastTargetId = world.npcs[i].id
    var fact = fmtResult("ask_oracle", res)
    if ans.hasPrefix("JA") {
      var ng = NameGen(used: Set(world.gen.used), rand: rnd)
      let nn = ng.next(culture: NameGen.culture(for: world.gen.slots.line), avoid: Set(world.npcs.map { norm($0.name) })); world.gen.used = ng.used.sorted()
      if let h = hidden.npcs.removeValue(forKey: old) { hidden.npcs[nn] = h }
      world.npcs[i].name = nn; if world.npcs[i].kurz.isEmpty { world.npcs[i].kurz = old }
      out(.world("\(old) heißt \(nn)"))
      fact += "\n[Fakt] \(old) nennt den Namen: \(nn). Die Figur sagt ihn wörtlich in „…“."
    } else { fact += "\n[Fakt] \(old) verweigert den Namen. Erzähle die Weigerung." }
    return (fact, res)
  }
}
