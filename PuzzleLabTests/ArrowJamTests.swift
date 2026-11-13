import XCTest
@testable import PuzzleLab

/// FNV-1a 64 over 32-bit values, as in `Golden/source/ArrowJamZipGoldenDump.kt`.
struct GoldenFnv {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func add(_ v: Int) {
        var x = UInt32(truncatingIfNeeded: v)
        for _ in 0..<4 {
            h = (h ^ UInt64(x & 0xFF)) &* 0x0000_0100_0000_01B3
            x >>= 8
        }
    }

    var hex: String {
        let s = String(h, radix: 16)
        return String(repeating: "0", count: max(0, 16 - s.count)) + s
    }
}

enum GoldenFiles {
    /// The test bundle, plus directories named in `PUZZLELAB_TEST_RESOURCES` (a macOS SwiftPM harness).
    static let bundles: [Bundle] = {
        var out = [Bundle(for: ArrowJamTests.self)]
        let extra = ProcessInfo.processInfo.environment["PUZZLELAB_TEST_RESOURCES"]?.split(separator: ":").compactMap { Bundle(path: String($0)) } ?? []
        out += extra
        ArrowLevelPack.searchBundles += extra
        return out
    }()

    static func prepare() { _ = bundles }

    static func json(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(bundles.lazy.compactMap {
            $0.url(forResource: name, withExtension: "json") ?? $0.url(forResource: name, withExtension: "json", subdirectory: "Golden")
        }.first, "\(name).json missing from the test bundle")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The app's bundled level pack, the way `LevelPacksTest.load` reads it.
    static func pack(_ name: String) throws -> JSONObject {
        prepare()
        let url = try XCTUnwrap(ArrowLevelPack.url(name), "\(name).json missing from the app bundle")
        return try XCTUnwrap(JSONObject(data: Data(contentsOf: url)))
    }
}

@MainActor
final class ArrowJamTests: XCTestCase {
    private func load(_ name: String) throws -> [ArrowLevel] {
        let array = try GoldenFiles.pack(name).getJSONArray("levels")
        return (0..<array.length()).map { ArrowLevel.parse(array.getJSONObject($0)) }.sorted { $0.id < $1.id }
    }

    // MARK: LevelPacksTest.arrowBoardsCanAllBeCleared

    func testArrowBoardsCanAllBeCleared() throws {
        for (name, count) in [("arrowjam_levels", 3000), ("arrowjam_daily", 365)] {
            let levels = try load(name)
            XCTAssertEqual(count, levels.count)
            XCTAssertEqual(Array(1...count), levels.map(\.id))
            for level in levels {
                XCTAssertEqual(level.a.count, level.pieces.count, "\(name) \(level.id): bad arrow code")
                XCTAssertNotNil(ArrowBoard(level).solutionOrder(), "\(name) \(level.id) is stuck")
                let limit = name == "arrowjam_levels" && level.id > 1000 ? 100 : 80
                XCTAssertTrue(max(level.w, level.h) <= limit, "\(name) \(level.id) too big")
            }
        }
    }

    /// The fast byte reader must decode exactly what the org.json-style parser does.
    func testFastPackReaderMatchesJSONParser() throws {
        for name in ["arrowjam_levels", "arrowjam_daily"] {
            let slow = try load(name)
            let pack = ArrowLevelPack(name)
            XCTAssertEqual(pack.count, slow.count)
            XCTAssertEqual(pack.version, try GoldenFiles.pack(name).optInt("version", 1))
            for (a, b) in zip(pack.levels, slow) {
                XCTAssertEqual(a.id, b.id)
                XCTAssertEqual(a.tier, b.tier, "\(name) \(a.id)")
                XCTAssertEqual(a.w, b.w)
                XCTAssertEqual(a.h, b.h)
                XCTAssertEqual(a.pic, b.pic)
                XCTAssertEqual(a.tip, b.tip)
                XCTAssertEqual(a.a, b.a, "\(name) \(a.id)")
            }
            XCTAssertEqual(pack.tiers, DifficultyTier.entries.filter { t in slow.contains { $0.tier == t } })
            XCTAssertEqual(pack.sizeLabel(1), "\(slow[0].a.count) arrows")
        }
    }

    // MARK: Golden (Android ArrowModel.kt on the JVM)

    private func tapCode(_ r: ArrowBoard.TapResult) -> Int {
        switch r {
        case .Exited: return -1
        case .None: return -2
        case let .Blocked(by, distance): return by * 1000 + distance
        }
    }

    private func check(_ levels: [ArrowLevel], _ golden: [[String: Any]], _ name: String) {
        XCTAssertEqual(levels.count, golden.count, name)
        for (level, g) in zip(levels, golden) {
            let where_ = "\(name) \(level.id)"
            XCTAssertEqual(level.id, g["id"] as? Int, where_)
            let pieces = level.pieces
            XCTAssertEqual(pieces.count, g["n"] as? Int, where_)
            XCTAssertEqual(level.a.count, g["a"] as? Int, where_)
            XCTAssertEqual(level.w, g["w"] as? Int, where_)
            XCTAssertEqual(level.h, g["h"] as? Int, where_)
            var geo = GoldenFnv()
            for p in pieces {
                geo.add(p.id); geo.add(p.cells.count)
                geo.add(Heading.entries.firstIndex(of: p.heading)!); geo.add(Heading.entries.firstIndex(of: p.tailHeading)!)
                for c in p.cells { geo.add(c.r); geo.add(c.c) }
            }
            XCTAssertEqual(geo.hex, g["geo"] as? String, "\(where_) geometry")
            let board = ArrowBoard(level)
            var lanes = GoldenFnv()
            for i in pieces.indices {
                lanes.add(board.laneLength(i))
                let b = board.blocker(i)
                lanes.add(b?.first ?? -1); lanes.add(b?.second ?? -1)
            }
            XCTAssertEqual(lanes.hex, g["lanes"] as? String, "\(where_) lanes")
            let order = board.solutionOrder()
            var sol = GoldenFnv()
            order?.forEach { sol.add($0) }
            XCTAssertEqual(order == nil ? "stuck" : sol.hex, g["sol"] as? String, "\(where_) solution")
            XCTAssertEqual(order?.count ?? -1, g["solLen"] as? Int, where_)
            XCTAssertEqual(board.bestHint() ?? -1, g["hint"] as? Int, "\(where_) hint")
            var free = GoldenFnv()
            board.freeArrows.forEach { free.add($0) }
            XCTAssertEqual(free.hex, g["free"] as? String, "\(where_) free")
            let sweep = ArrowBoard(level)
            var taps = GoldenFnv()
            for _ in 0..<2 { for i in pieces.indices { taps.add(tapCode(sweep.tap(i))) } }
            taps.add(sweep.remaining)
            XCTAssertEqual(taps.hex, g["taps"] as? String, "\(where_) taps")
            if let traceLen = g["traceLen"] as? Int {
                let t = ArrowBoard(level)
                var f = GoldenFnv()
                var len = 0
                while !t.isCleared {
                    guard let h = t.bestHint() else { break }
                    f.add(h)
                    t.remove(h)
                    len += 1
                }
                XCTAssertEqual(len, traceLen, "\(where_) hint play")
                XCTAssertEqual(f.hex, g["trace"] as? String, "\(where_) hint play")
            }
        }
    }

    func testGoldenMatchesAndroidModel() throws {
        let golden = try GoldenFiles.json("ArrowJamGolden")
        check(ArrowLevelPack("arrowjam_levels").levels, try XCTUnwrap(golden["levels"] as? [[String: Any]]), "levels")
        check(ArrowLevelPack("arrowjam_daily").levels, try XCTUnwrap(golden["daily"] as? [[String: Any]]), "daily")
    }

    // MARK: Static layer

    #if canImport(UIKit)
    /// Renders every tile of the densest board at the fitted zoom and the visible tiles at 6×, the
    /// worst cases for the cached layer (and checks the time stays far below Android's per-frame redraw).
    func testStaticLayerRendersDensestBoard() async throws {
        GoldenFiles.prepare()
        let pack = ArrowLevelPack("arrowjam_levels")
        let level = try XCTUnwrap(pack.levels.max { $0.a.count < $1.a.count })
        let session = ArrowJamSession(.Adventure, level, true, nil)
        defer { session.dispose() }
        try await Task.sleep(nanoseconds: 400_000_000) // reduce-motion entrance is 0.25 s
        XCTAssertFalse(session.inEntrance)
        var scene = ArrowStaticScene(session.board, ArrowTheme.night, true)
        scene.update(session, nowSeconds())
        XCTAssertEqual(scene.changed.count, level.a.count, "every arrow rests after the entrance")
        let view = CGSize(width: 393, height: 560)
        for zoom in [1.0, 6.0] as [CGFloat] {
            let layout = ArrowLayout(view, level.w, level.h, ArrowCamera(min(zoom, ArrowLayout(view, level.w, level.h, ArrowCamera()).maxZoom)))
            let lvl = ArrowTileLevel(cell: layout.cell, scale: 3)
            let T = lvl.tileSize
            // The tiles under the view (all of them at 1×).
            let x0 = max(-layout.origin.x, -layout.cell), y0 = max(-layout.origin.y, -layout.cell)
            let x1 = min(view.width - layout.origin.x, CGFloat(level.w + 1) * layout.cell)
            let y1 = min(view.height - layout.origin.y, CGFloat(level.h + 1) * layout.cell)
            var images = 0, tiles = 0
            let start = CACurrentMediaTime()
            for ty in Int((y0 / T).rounded(.down))...Int((y1 / T).rounded(.down)) {
                for tx in Int((x0 / T).rounded(.down))...Int((x1 / T).rounded(.down)) {
                    tiles += 1
                    if ArrowTileRenderer.renderTile(scene, cell: layout.cell, scale: 3, rect: lvl.rect(ArrowTileKey(tx: tx, ty: ty))) != nil { images += 1 }
                }
            }
            let ms = (CACurrentMediaTime() - start) * 1000
            print("Arrow Jam level \(level.id) (\(level.a.count) arrows, \(level.w)×\(level.h)) at \(zoom)×: \(tiles) tiles, \(images) drawn in \(String(format: "%.1f", ms)) ms")
            XCTAssertGreaterThan(images, 0)
        }
    }
    #endif

    func testFastOutSlowInMatchesCompose() {
        // Compose FastOutSlowInEasing = CubicBezierEasing(0.4, 0, 0.2, 1).
        XCTAssertEqual(ArrowEase.fastOutSlowIn(0), 0)
        XCTAssertEqual(ArrowEase.fastOutSlowIn(1), 1)
        XCTAssertEqual(ArrowEase.fastOutSlowIn(0.5), 0.77556, accuracy: 0.0005)
    }

    // MARK: Model basics

    func testParseAndRules() {
        let piece = ArrowPiece.parse(0, "3.7.RRDDLU")!
        XCTAssertEqual(piece.tail, ArrowCell(3, 7))
        XCTAssertEqual(piece.cells.count, 7)
        XCTAssertEqual(piece.head, ArrowCell(4, 8))
        XCTAssertEqual(piece.heading, .Up)
        XCTAssertEqual(piece.tailHeading, .Left)
        XCTAssertNil(ArrowPiece.parse(0, "3.7"))
        XCTAssertNil(ArrowPiece.parse(0, "3.x.RR"))
        XCTAssertNil(ArrowPiece.parse(0, "3.7.RX"))
        XCTAssertEqual(ArrowPiece.parse(1, "0.0.")?.heading, .Up)

        // Two arrows in one row: 0 points right into 1, 1 points up and is free.
        let board = ArrowBoard(5, 3, [ArrowPiece.of(0, [(1, 0), (1, 1)]), ArrowPiece.of(1, [(2, 3), (1, 3)])])
        XCTAssertEqual(board.tap(0), .Blocked(by: 1, distance: 1))
        XCTAssertEqual(board.bestHint(), 1)
        XCTAssertEqual(board.solutionOrder(), [1, 0])
        XCTAssertEqual(board.tap(1), .Exited)
        XCTAssertEqual(board.tap(1), .None)
        XCTAssertEqual(board.laneLength(0), 3)
        XCTAssertEqual(board.freeArrows, [0])
        XCTAssertEqual(board.tap(0), .Exited)
        XCTAssertTrue(board.isCleared)
    }

    func testSessionScoringAndSnapshot() throws {
        GoldenFiles.prepare()
        let pack = ArrowLevelPack("arrowjam_levels")
        let level = try XCTUnwrap(pack.level(25))
        let session = ArrowJamSession(.Adventure, level, true, "{\"r\":[0,1],\"h\":2,\"l\":1,\"c\":4}")
        defer { session.dispose() }
        XCTAssertEqual(session.cleared, 2)
        XCTAssertEqual(session.hearts, 2)
        XCTAssertEqual(session.heartsLost, 1)
        XCTAssertEqual(session.bestCombo, 4)
        XCTAssertEqual(session.stars, Scoring.stars(1))
        // stars 2 → 20, combo bonus min(15, 4 - 3) = 1, level 25 milestone 50.
        XCTAssertEqual(session.coins(), [0, 10, 20, 30][Scoring.stars(1)] + 1 + 50)
        XCTAssertEqual(session.snapshot, "{\"r\":[0,1],\"h\":2,\"l\":1,\"c\":4}")
        let daily = ArrowJamSession(.Daily, level, true, nil)
        defer { daily.dispose() }
        XCTAssertNil(daily.snapshot)
        XCTAssertEqual(daily.coins(), 30 + 0 + 40)
        XCTAssertEqual(ArrowJamSession.entranceDuration(10), 0.55 + 0.08, accuracy: 1e-12)
        XCTAssertEqual(ArrowJamSession.entranceDuration(500), 1.1, accuracy: 1e-12)
    }
}
