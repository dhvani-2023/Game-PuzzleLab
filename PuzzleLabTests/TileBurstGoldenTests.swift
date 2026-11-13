import XCTest
#if canImport(PuzzleLab)
@testable import PuzzleLab
#else
@testable import TileCore
#endif

/// Same seeds → same trays, moves and scores as Android. `Golden/tileburst_golden.json` was dumped from the
/// JVM (`Golden/source/TileBurstGoldenDump.kt`, which this file mirrors line for line).
final class TileBurstGoldenTests: XCTestCase {
    // MARK: Fixtures

    private static func fixture(_ name: String, _ ext: String, filePath: String = #filePath) -> URL? {
        let here = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle(for: TileBurstGoldenTests.self).url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Levels"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "levels"),
            here.appendingPathComponent("Golden/\(name).\(ext)"),
            here.appendingPathComponent("../PuzzleLab/Resources/Levels/\(name).\(ext)"),
            ProcessInfo.processInfo.environment["TILEBURST_FIXTURES"].map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).\(ext)") },
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let golden: [String: Any] = {
        guard let url = fixture("tileburst_golden", "json"), let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return o
    }()

    static let levels: [TileLevel] = {
        guard let url = fixture("tileburst_levels", "json"), let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["levels"] as? [[String: Any]] else { return [] }
        return array.map { TileLevel.parse($0) }.sorted { $0.id < $1.id }
    }()

    // MARK: Hashing (FNV-1a over 64-bit words, as the Kotlin dump)

    private struct H {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        mutating func add(_ v: Int64) { h = (h ^ UInt64(bitPattern: v)) &* 1_099_511_628_211 }
        mutating func add(_ v: Int) { add(Int64(v)) }
        mutating func add(_ v: UInt64) { add(Int64(bitPattern: v)) }
        mutating func add(_ b: Bool) { add(Int64(b ? 1 : 0)) }
        mutating func add(_ d: Double) { add(Int64(bitPattern: d.bitPattern)) }
        mutating func add(_ s: String) { for u in s.utf16 { add(Int(u)) } }
    }

    private static func hex(_ v: UInt64) -> String { String(v, radix: 16) }
    private static func hex(_ d: Double) -> String { String(d.bitPattern, radix: 16) }

    private struct Run {
        let hash: UInt64
        let score: Int
        let moves: Int
        let rounds: Int
        let outcome: Int
        let trace: [String]
    }

    private static func hashTray(_ h: inout H, _ tray: [TilePiece?]) {
        h.add(1000)
        for p in tray {
            guard let p else { h.add(-1); continue }
            h.add(p.id); h.add(p.shape.id); h.add(p.gemCell ?? -1); h.add(p.gem?.ordinal ?? -1)
        }
    }

    private static func hashCleared(_ h: inout H, _ list: [TileCleared]) {
        h.add(list.count)
        for c in list {
            h.add(c.cell); h.add(c.block.id); h.add(c.block.tone); h.add(c.block.gem?.ordinal ?? -1); h.add(c.block.prefilled); h.add(c.distance)
        }
    }

    private static func hashBoard(_ h: inout H, _ b: TileBoard) {
        h.add(b.score); h.add(b.occupancy); h.add(b.combo); h.add(b.misses); h.add(b.bestCombo); h.add(b.placements); h.add(b.linesCleared)
        for g in b.collected.indices { h.add(b.collected[g]); h.add(b.goalTotals[g]); h.add(b.remaining(g)) }
        h.add(b.goalsDone); h.add(b.fever); h.add(b.prefilledLeft)
        for gem in b.neededGems { h.add(gem.ordinal) }
    }

    /// TileBurstSession's turn loop with the bot playing and every revive accepted.
    private static func simulate(_ level: TileLevel?, seed: Int64, pressure: Double, gemRate: Double, endless: Bool, maxMoves: Int, keepTrace: Bool) -> Run {
        var h = H()
        var trace: [String] = []
        let board = TileBoard(level)
        let dealer = TileDealer(seed, pressure, gemRate)
        var tray: [TilePiece?] = [nil, nil, nil]
        for (k, p) in dealer.deal(board).enumerated() { tray[k] = p }
        hashTray(&h, tray)
        hashBoard(&h, board)
        if keepTrace { trace.append(hex(h.h)) }
        var rounds = 1
        var revived = false
        var moves = 0
        var outcome = 2
        while moves < maxMoves {
            guard let move = TileBot.bestMove(board, tray) else { outcome = 3; break }
            h.add(2000); h.add(move.slot); h.add(move.origin); h.add(move.value)
            let piece = tray[move.slot]!
            let p = board.place(piece, move.origin)!
            tray[move.slot] = nil
            moves += 1
            h.add(3000)
            h.add(p.cells.count); for c in p.cells { h.add(c) }
            for b in p.blocks { h.add(b.id); h.add(b.tone); h.add(b.gem?.ordinal ?? -1) }
            h.add(p.rows.count); for r in p.rows { h.add(r) }
            h.add(p.cols.count); for c in p.cols { h.add(c) }
            hashCleared(&h, p.cleared)
            h.add(p.gems.count); for g in p.gems { h.add(g.cell); h.add(g.gem.ordinal); h.add(g.goal ?? -1) }
            h.add(p.cellPoints); h.add(p.linePoints); h.add(p.bonusPoints); h.add(p.combo); h.add(p.graceLeft); h.add(p.comboBroke)
            h.add(p.praise ?? -1); h.add(p.perfect); h.add(p.feverStarted); h.add(p.feverEnded); h.add(p.lines); h.add(p.total)
            hashBoard(&h, board)
            if keepTrace { trace.append(hex(h.h)) }
            if board.goalsDone { outcome = 0; break }
            if tray.allSatisfy({ $0 == nil }) {
                if endless { dealer.pressure = TileDealer.classicPressure(board.score) }
                for (k, np) in dealer.deal(board).enumerated() { tray[k] = np }
                rounds += 1
                hashTray(&h, tray)
            }
            if !board.anyFits(tray) {
                if revived { outcome = 1; break }
                revived = true
                h.add(4000)
                hashCleared(&h, board.revive())
                for (k, np) in dealer.deal(board, rescue: true).enumerated() { tray[k] = np }
                rounds += 1
                hashTray(&h, tray)
                hashBoard(&h, board)
            }
        }
        return Run(hash: h.h, score: board.score, moves: moves, rounds: rounds, outcome: outcome, trace: trace)
    }

    private static func tierOrdinal(_ t: DifficultyTier) -> Int { DifficultyTier.allCases.firstIndex(of: t) ?? -1 }

    private static func levelHash(_ l: TileLevel) -> UInt64 {
        var h = H()
        h.add(l.id); h.add(tierOrdinal(l.tier)); h.add(l.par); h.add(l.pressure); h.add(l.gemRate); h.add(l.seed)
        h.add(l.pattern.count); for row in l.pattern { h.add(row.utf16.count); h.add(row) }
        h.add(l.gems?.count ?? -1); for row in l.gems ?? [] { h.add(row.utf16.count); h.add(row) }
        h.add(l.goals.count); for g in l.goals { h.add(g.kind.rawValue); h.add(g.gem?.ordinal ?? -1); h.add(g.n ?? -1) }
        h.add(l.tip.map { $0.utf16.count } ?? -1); if let tip = l.tip { h.add(tip) }
        h.add(l.sizeLabel.utf16.count); h.add(l.sizeLabel)
        h.add(l.world)
        return h.h
    }

    private func checkRun(_ name: String, _ r: Run, _ o: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = Self.hex(r.hash) == o["h"] as? String && r.score == o["s"] as? Int && r.moves == o["m"] as? Int
            && r.rounds == o["r"] as? Int && r.outcome == o["o"] as? Int
        if !ok {
            var detail = ""
            if let t = o["trace"] as? [String] {
                let k = zip(t, r.trace).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                detail = " first divergent step \(k.map(String.init) ?? "none (\(t.count) vs \(r.trace.count))")"
            }
            XCTFail("\(name): got hash \(Self.hex(r.hash)) score \(r.score) moves \(r.moves) rounds \(r.rounds) outcome \(r.outcome), "
                    + "want \(o["h"] ?? "?") \(o["s"] ?? "?") \(o["m"] ?? "?") \(o["r"] ?? "?") \(o["o"] ?? "?")\(detail)", file: file, line: line)
        }
        return ok
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: Tests

    func testGoldenFileLoads() {
        XCTAssertFalse(Self.golden.isEmpty, "tileburst_golden.json missing from the test bundle")
        XCTAssertEqual(Self.levels.count, 3000, "tileburst_levels.json missing from the app bundle")
    }

    func testRngStreams() throws {
        let streams = try XCTUnwrap(Self.golden["rng"] as? [[String: Any]])
        XCTAssertEqual(streams.count, 8)
        for s in streams {
            let seed = try XCTUnwrap(Int64(s["seed"] as? String ?? ""))
            var r = TileRNG(seed)
            XCTAssertEqual((0..<6).map { _ in Self.hex(r.next()) }, s["next"] as? [String], "next \(seed)")
            XCTAssertEqual((0..<12).map { _ in r.int(7) }, s["int7"] as? [Int], "int7 \(seed)")
            XCTAssertEqual((0..<12).map { _ in r.int(37) }, s["int37"] as? [Int], "int37 \(seed)")
            XCTAssertEqual((0..<3).map { _ in r.int(1) }, s["int1"] as? [Int], "int1 \(seed)")
            XCTAssertEqual((0..<6).map { _ in Self.hex(r.unit()) }, s["unit"] as? [String], "unit \(seed)")
            var list = Array(0..<10)
            r.shuffle(&list)
            XCTAssertEqual(list, s["shuffle"] as? [Int], "shuffle \(seed)")
        }
    }

    func testShapes() throws {
        let shapes = try XCTUnwrap(Self.golden["shapes"] as? [[String: Any]])
        XCTAssertEqual(TileShape.all.count, 37)
        XCTAssertEqual(shapes.count, TileShape.all.count)
        for (s, o) in zip(TileShape.all, shapes) {
            var h = H()
            for p in s.placements { h.add(p.origin); h.add(p.mask) }
            XCTAssertEqual(s.id, o["id"] as? Int)
            XCTAssertEqual(s.family.rawValue, o["family"] as? Int, "family \(s.id)")
            XCTAssertEqual(s.tone, o["tone"] as? Int, "tone \(s.id)")
            XCTAssertEqual(s.size, o["size"] as? Int, "size \(s.id)")
            XCTAssertEqual(s.rows, o["rows"] as? Int, "rows \(s.id)")
            XCTAssertEqual(s.cols, o["cols"] as? Int, "cols \(s.id)")
            XCTAssertEqual(s.placements.count, o["placements"] as? Int, "placements \(s.id)")
            XCTAssertEqual(Self.hex(h.h), o["ph"] as? String, "placement masks \(s.id)")
            XCTAssertEqual([0.0, 0.25, 0.5, 0.85, 1.0, 1.4].map { Self.hex(s.weight($0)) }, o["w"] as? [String], "weights \(s.id)")
        }
    }

    func testHypotMatchesJava() throws {
        let want = try XCTUnwrap(Self.golden["hypot"] as? [String])
        var got: [String] = []
        for a in -16...16 { for b in -16...16 { got.append(Self.hex(tileHypot(Double(a) / 2.0, Double(b) / 2.0))) } }
        XCTAssertEqual(got, want)
    }

    func testRuleTables() throws {
        var praise: [Int] = []
        for lines in 0...6 { for combo in 0...20 { praise.append(TileBoard.praise(lines, combo) ?? -1) } }
        XCTAssertEqual(praise, Self.golden["praise"] as? [Int])
        XCTAssertEqual([0, 1, 150, 2999, 4500, 8100, 8999, 9000, 12000].map { Self.hex(TileDealer.classicPressure($0)) },
                       Self.golden["classicPressure"] as? [String])
        var masks = H()
        for seed in Int64(1)...200 {
            var r = TileRNG(seed &* 7919)
            let a = r.next()
            let occ = a & r.next()
            masks.add(TileGrid.lineMask(occ)); masks.add(TileGrid.holes(occ)); masks.add(TileGrid.roughness(occ))
            let l = TileGrid.lines(occ)
            for x in l.rows { masks.add(x) }
            for x in l.cols { masks.add(x) }
            masks.add(l.mask)
            for s in TileShape.all { masks.add(s.fits(occ)) }
            var budget = 4000
            masks.add(TileDealer.solvable(occ, [TileShape.all[Int(seed % 37)], TileShape.all[Int((seed * 3) % 37)], TileShape.all[10]], &budget))
        }
        XCTAssertEqual(Self.hex(masks.h), Self.golden["gridHash"] as? String)

        var rescue = H()
        for seed in Int64(1)...60 {
            var r = TileRNG(seed)
            let a = r.next()
            let occ = a | r.next()
            let dealer = TileDealer(seed, 0.5, 0.0)
            for p in dealer.deal(occ, [], rescue: true) { rescue.add(p.id); rescue.add(p.shape.id) }
            for p in dealer.deal(occ, [], rescue: false) { rescue.add(p.id); rescue.add(p.shape.id) }
        }
        XCTAssertEqual(Self.hex(rescue.h), Self.golden["rescueHash"] as? String)
    }

    func testEveryAdventureLevelPlaysLikeAndroid() throws {
        let want = try XCTUnwrap(Self.golden["adventure"] as? [[String: Any]])
        XCTAssertEqual(Self.levels.count, want.count)
        var failures = 0
        for (l, o) in zip(Self.levels, want) {
            XCTAssertEqual(l.id, o["id"] as? Int)
            if Self.hex(Self.levelHash(l)) != o["lh"] as? String {
                failures += 1
                XCTFail("level \(l.id): parsed fields differ (pressure \(Self.hex(l.pressure)) vs \(o["p"] ?? "?"), gemRate \(Self.hex(l.gemRate)) vs \(o["g"] ?? "?"))")
            }
            let board = TileBoard(l)
            XCTAssertEqual(Self.hex(board.occupancy), o["occ"] as? String, "level \(l.id) start board")
            XCTAssertEqual(board.goalTotals, o["totals"] as? [Int], "level \(l.id) goal totals")
            let keep = o["trace"] != nil
            let run = Self.simulate(l, seed: l.seed, pressure: l.pressure, gemRate: l.gemRate, endless: false, maxMoves: 240, keepTrace: keep)
            if !checkRun("level \(l.id)", run, o) { failures += 1 }
            if failures > 20 { XCTFail("stopping after 20 failures"); return }
        }
    }

    func testClassicRunsPlayLikeAndroid() throws {
        let want = try XCTUnwrap(Self.golden["classic"] as? [[String: Any]])
        XCTAssertEqual(want.count, 33)
        for o in want {
            let seed = try XCTUnwrap(Int64(o["seed"] as? String ?? ""))
            let run = Self.simulate(nil, seed: seed, pressure: 0, gemRate: 0, endless: true, maxMoves: 300, keepTrace: o["trace"] != nil)
            _ = checkRun("classic seed \(seed)", run, o)
        }
    }

    func testDailyRunsPlayLikeAndroid() throws {
        let want = try XCTUnwrap(Self.golden["daily"] as? [[String: Any]])
        XCTAssertEqual(want.count, 61)
        for o in want {
            let day = try XCTUnwrap(o["day"] as? Int)
            #if canImport(PuzzleLab)
            XCTAssertEqual(TileRecords.dailyTarget(day), o["target"] as? Int, "target \(day)")
            #endif
            let run = Self.simulate(nil, seed: Int64(day), pressure: 0, gemRate: 0, endless: true, maxMoves: 300, keepTrace: o["trace"] != nil)
            _ = checkRun("daily \(day)", run, o)
        }
    }
}
