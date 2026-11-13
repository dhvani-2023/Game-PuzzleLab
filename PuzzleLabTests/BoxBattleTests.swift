import XCTest
@testable import PuzzleLab
import GameKit

/// Box Battle: the level pack (port of `LevelPacksTest.boxBattleBoardsAreInRange`), the rules and stars,
/// and the JVM golden traces (`Golden/BoxBattleGolden.json`, dumped by `Golden/source/BoxBattleGoldenDump.kt`
/// from the Android `BoxModel.kt` / `BoxBot` / `springStep` / `scribblePath` code).
final class BoxBattleTests: XCTestCase {
    // MARK: Fixtures

    private static func fixture(_ name: String, _ ext: String, filePath: String = #filePath) -> URL? {
        let here = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle(for: BoxBattleTests.self).url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Levels"),
            here.appendingPathComponent("Golden/\(name).\(ext)"),
            here.appendingPathComponent("../PuzzleLab/Resources/Levels/\(name).\(ext)"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func json(_ name: String) -> [String: Any] {
        guard let url = fixture(name, "json"), let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return o
    }

    private static let golden = json("BoxBattleGolden")

    private static func levels() -> [BoxLevel] {
        guard let url = fixture("boxbattle_levels", "json"), let data = try? Data(contentsOf: url), let root = JSONObject(data: data) else { return [] }
        let array = root.getJSONArray("levels")
        return (0..<array.length()).map { BoxLevel.parse(array.getJSONObject($0)) }.sorted { $0.id < $1.id }
    }

    // MARK: LevelPacksTest

    func testBoxBattleBoardsAreInRange() {
        let levels = Self.levels()
        XCTAssertEqual(levels.count, 3000)
        XCTAssertEqual(levels.map(\.id), Array(1...3000))
        for level in levels {
            XCTAssertTrue((2...8).contains(level.rows) && (2...8).contains(level.cols), "boxbattle \(level.id): size")
            XCTAssertTrue((-3...3).contains(level.bot), "boxbattle \(level.id): bot")
        }
    }

    func testPackLoadsThroughTheModule() {
        let pack = BoxBattleModule.shared.pack
        XCTAssertEqual(pack.count, 3000)
        XCTAssertEqual(pack.level(1)?.sizeLabel, "3×3")
        XCTAssertEqual(pack.level(1)?.bot, -1)
        XCTAssertNil(pack.level(3001))
        XCTAssertEqual(BoxBattleModule.shared.mapTheme.worlds.count, 6)
        XCTAssertEqual(BoxBattleModule.shared.mapTheme.worlds[1].range, 501...1000)
    }

    // MARK: Golden (JVM)

    /// Kotlin `playGame` in the dump: bot vs bot with one `kotlin.random.Random(seed)`.
    private func playGame(_ rows: Int, _ cols: Int, _ botYou: Int, _ botRival: Int, _ seed: Int) -> String {
        let m = BoxModel(rows, cols)
        let rng = KotlinRandom(intSeed: seed)
        var turn = Player.You
        var parts: [String] = []
        while !m.isComplete {
            let d = turn == .You ? botYou : botRival
            let e = BoxBot.move(m, d, rng)
            parts.append("\(e.horizontal ? "h" : "v")\(e.r).\(e.c)")
            if m.draw(e, turn) == 0 { turn = turn == .You ? .Rival : .You }
        }
        return parts.joined(separator: " ") + "|\(m.scoreYou)-\(m.scoreRival)"
    }

    func testBotGamesMatchTheJVM() throws {
        let games = try XCTUnwrap(Self.golden["games"] as? [[String: Any]])
        XCTAssertEqual(games.count, 7 * 12 * 5)
        var mismatches = 0
        for g in games {
            let rows = g["rows"] as! Int, cols = g["cols"] as! Int
            let you = g["you"] as! Int, rival = g["rival"] as! Int, seed = g["seed"] as! Int
            let trace = playGame(rows, cols, you, rival, seed)
            if trace != g["trace"] as! String {
                mismatches += 1
                if mismatches < 5 { XCTFail("game \(rows)x\(cols) you \(you) rival \(rival) seed \(seed):\n\(trace)\n\(g["trace"] as! String)") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testEdgeProbesMatchTheJVM() throws {
        let probes = try XCTUnwrap(Self.golden["probes"] as? [[String: Any]])
        XCTAssertFalse(probes.isEmpty)
        for p in probes {
            let rows = p["rows"] as! Int, cols = p["cols"] as! Int, seed = p["seed"] as! Int, plies = p["plies"] as! Int
            let m = BoxModel(rows, cols)
            let rng = KotlinRandom(intSeed: seed)
            var turn = Player.You
            var n = 0
            while !m.isComplete && n < plies {
                let e = BoxBot.move(m, 1, rng)
                if m.draw(e, turn) == 0 { turn = turn == .You ? .Rival : .You }
                n += 1
            }
            let edges = m.legalEdges().map { e in
                "\(e.horizontal ? "h" : "v")\(e.r).\(e.c)=\(m.boxesClosedBy(e)),\(m.createsThreeSided(e) ? 1 : 0),\(m.safeCountAfter(e)),\(m.chainSizeOpenedBy(e))"
            }.joined(separator: " ")
            XCTAssertEqual(edges, p["edges"] as! String, "probe \(rows)x\(cols) seed \(seed) plies \(plies)")
        }
    }

    func testScribblePointsAreBitExact() throws {
        let scribbles = try XCTUnwrap(Self.golden["scribbles"] as? [[String: Any]])
        XCTAssertEqual(scribbles.count, 3 * 64)
        for s in scribbles {
            let seed = s["seed"] as! Int
            let rect = (s["rect"] as! [Int]).map { Float(bitPattern: UInt32(truncatingIfNeeded: $0)) }
            let expected = (s["pts"] as! [Int]).map { UInt32(truncatingIfNeeded: $0) }
            let pts = scribblePoints(rect[0], rect[1], rect[2], rect[3], seed)
            let got = pts.flatMap { [$0.x.bitPattern, $0.y.bitPattern] }
            XCTAssertEqual(got, expected, "scribble seed \(seed) rect \(rect)")
        }
    }

    func testSpringStepMatchesTheJVM() throws {
        let springs = try XCTUnwrap(Self.golden["springs"] as? [[String: Any]])
        XCTAssertFalse(springs.isEmpty)
        for s in springs {
            let t = Float(bitPattern: UInt32(truncatingIfNeeded: s["t"] as! Int))
            let response = Float(bitPattern: UInt32(truncatingIfNeeded: s["response"] as! Int))
            let damping = Float(bitPattern: UInt32(truncatingIfNeeded: s["damping"] as! Int))
            let v = Float(bitPattern: UInt32(truncatingIfNeeded: s["v"] as! Int))
            // libm and the JVM may differ in the last Double ulp; after rounding to Float that is ≤ 1 Float ulp.
            XCTAssertEqual(springStep(t, response, damping), v, accuracy: max(abs(v).ulp * 2, 1e-7), "t \(t) r \(response) d \(damping)")
        }
    }

    // MARK: Rules

    private func level(_ rows: Int, _ cols: Int, bot: Int, id: Int = 1) -> BoxLevel { BoxLevel(id, .Easy, rows, cols, bot) }

    func testClosingABoxEarnsAnotherTurn() {
        let m = BoxModel(1, 2)
        XCTAssertEqual(m.legalEdges().count, 7)
        XCTAssertEqual(m.draw(BoxEdge(true, 0, 0), .You), 0)
        XCTAssertEqual(m.draw(BoxEdge(true, 1, 0), .Rival), 0)
        XCTAssertEqual(m.draw(BoxEdge(false, 0, 0), .You), 0)
        XCTAssertEqual(m.boxesClosedBy(BoxEdge(false, 0, 1)), 1)
        XCTAssertTrue(m.createsThreeSided(BoxEdge(true, 0, 1)) == false)
        XCTAssertEqual(m.draw(BoxEdge(false, 0, 1), .You), 1)
        XCTAssertEqual(m.owner[0][0], .You)
        XCTAssertEqual(m.score(.You), 1)
        XCTAssertEqual(m.draw(BoxEdge(false, 0, 1), .Rival), 0, "drawing a drawn edge does nothing")

        let s = BoxBattleSession(level(1, 2, bot: 1))
        XCTAssertTrue(s.canPlayerMove)
        XCTAssertNotNil(s.playerDraw(BoxEdge(true, 0, 0)))
        XCTAssertEqual(s.turn, .Rival)
        XCTAssertTrue(s.botThinking)
        XCTAssertNil(s.playerDraw(BoxEdge(true, 1, 0)), "not the player's turn")
        XCTAssertEqual(s.commitBot(BoxEdge(true, 1, 0)), [])
        XCTAssertEqual(s.turn, .You)
        _ = s.playerDraw(BoxEdge(false, 0, 0))
        XCTAssertEqual(s.turn, .Rival)
        let claimed = s.commitBot(BoxEdge(false, 0, 1))
        XCTAssertEqual(claimed, [BoxCell(0, 0)])
        XCTAssertEqual(s.turn, .Rival, "a capture keeps the turn")
        XCTAssertEqual(s.scoreRival, 1)
        XCTAssertEqual(s.lastClaimed, 1)
        XCTAssertEqual(s.claimTick, 1)
        XCTAssertEqual(s.phase, .Playing)
    }

    func testTwoBoxCaptureWinsWithThreeStars() {
        // 1×2: You close both boxes with the shared middle line.
        let s = BoxBattleSession(level(1, 2, bot: 2, id: 80))
        _ = s.playerDraw(BoxEdge(true, 0, 0)); _ = s.commitBot(BoxEdge(true, 0, 1))
        _ = s.playerDraw(BoxEdge(true, 1, 0)); _ = s.commitBot(BoxEdge(true, 1, 1))
        _ = s.playerDraw(BoxEdge(false, 0, 0)); _ = s.commitBot(BoxEdge(false, 0, 2))
        let claimed = s.playerDraw(BoxEdge(false, 0, 1))
        XCTAssertEqual(claimed?.count, 2)
        XCTAssertEqual(s.phase, .Won)
        XCTAssertEqual(s.stars, 3)
        XCTAssertEqual(s.coinsEarned, 12 + 3 * 6 + 80 / 40)
        XCTAssertFalse(s.canPlayerMove)
        XCTAssertNil(s.chooseBotEdge())
    }

    /// Plays `rivalBoxes` boxes for the rival and the rest but the last edge for the player straight on the
    /// model, then the last edge through the session (so the session finishes the game).
    private func finish(_ rows: Int, _ cols: Int, bot: Int, rivalBoxes: Set<BoxCell>) -> BoxBattleSession {
        let s = BoxBattleSession(level(rows, cols, bot: bot, id: 40))
        let m = s.model
        var last: BoxEdge?
        for r in 0..<rows {
            for c in 0..<cols {
                let who: Player = rivalBoxes.contains(BoxCell(r, c)) ? .Rival : .You
                for e in [BoxEdge(true, r, c), BoxEdge(true, r + 1, c), BoxEdge(false, r, c), BoxEdge(false, r, c + 1)] where !m.isDrawn(e) {
                    if m.legalEdges().count == 1 { last = e; break }
                    m.draw(e, who)
                }
            }
        }
        if let last { _ = s.playerDraw(last) }
        XCTAssertTrue(m.isComplete)
        return s
    }

    func testStarsByMargin() {
        let twoStars = finish(2, 2, bot: 1, rivalBoxes: [BoxCell(0, 0)])
        XCTAssertEqual(twoStars.scoreYou, 3)
        XCTAssertEqual(twoStars.scoreRival, 1)
        XCTAssertEqual(twoStars.phase, .Won)
        XCTAssertEqual(twoStars.stars, 2)
        XCTAssertEqual(twoStars.coinsEarned, 12 + 2 * 6 + 1)

        let oneStar = finish(1, 3, bot: 1, rivalBoxes: [BoxCell(0, 0)])
        XCTAssertEqual(oneStar.scoreYou, 2)
        XCTAssertEqual(oneStar.scoreRival, 1)
        XCTAssertEqual(oneStar.stars, 1)

        let lost = finish(1, 3, bot: 1, rivalBoxes: [BoxCell(0, 0), BoxCell(0, 1)])
        XCTAssertEqual(lost.phase, .Lost)
        XCTAssertEqual(lost.stars, 0)
        XCTAssertEqual(lost.coinsEarned, 0)
    }

    func testDrawCountsAsAWinOnlyForTheRookieBot() {
        let rookie = finish(2, 2, bot: -1, rivalBoxes: [BoxCell(0, 0), BoxCell(1, 0)])
        XCTAssertEqual(rookie.scoreYou, 2)
        XCTAssertEqual(rookie.scoreRival, 2)
        XCTAssertEqual(rookie.phase, .Won)
        XCTAssertEqual(rookie.stars, 1)

        for bot in [-3, -2, 0, 3] {
            let draw = finish(2, 2, bot: bot, rivalBoxes: [BoxCell(0, 0), BoxCell(1, 0)])
            XCTAssertEqual(draw.phase, .Lost, "bot \(bot)")
        }
    }

    func testBotAlwaysTakesTheBiggestCapture() {
        // 1×3: the middle box and the right box are both one line short.
        let m = BoxModel(1, 3)
        for e in [BoxEdge(true, 0, 1), BoxEdge(true, 1, 1), BoxEdge(false, 0, 1), BoxEdge(true, 0, 2), BoxEdge(true, 1, 2), BoxEdge(false, 0, 3)] {
            m.draw(e, .You)
        }
        XCTAssertEqual(m.boxesClosedBy(BoxEdge(false, 0, 2)), 2)
        for d in 0...3 { XCTAssertEqual(BoxBot.move(m, d, KotlinRandom(intSeed: 1)), BoxEdge(false, 0, 2), "difficulty \(d)") }
    }

    func testBotAvoidsGiftsWhenItCan() {
        let rng = KotlinRandom(intSeed: 42)
        for _ in 0..<50 {
            let m = BoxModel(3, 3)
            m.draw(BoxEdge(true, 0, 0), .You)
            m.draw(BoxEdge(false, 0, 0), .You)
            for d in 1...3 {
                let e = BoxBot.move(m, d, rng)
                XCTAssertFalse(m.createsThreeSided(e), "difficulty \(d) gifted \(e)")
                XCTAssertEqual(m.boxesClosedBy(e), 0)
            }
        }
    }

    // MARK: Drawing helpers

    func testBoardGeometry() {
        let g = BoardGeom.of(300, 300, 2, 2)
        XCTAssertEqual(g.side, 300)
        XCTAssertEqual(g.cell, (300 - 2 * 300 * 0.105) / 2, accuracy: 1e-9)
        XCTAssertEqual(g.index(1, 2), 5)
        XCTAssertEqual(g.dot(5), g.dot(1, 2))
        XCTAssertEqual(g.ends(BoxEdge(false, 0, 1)).0, 1)
        XCTAssertEqual(g.ends(BoxEdge(false, 0, 1)).1, 4)
        let m = BoxMetrics(100, 300)
        XCTAssertEqual(m.dotR, 10, accuracy: 1e-9)
        XCTAssertEqual(m.endW, 19, accuracy: 1e-9)
        XCTAssertEqual(m.pencilLen, 72, accuracy: 1e-9)
    }
}
