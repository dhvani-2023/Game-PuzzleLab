import XCTest
import GameKit
@testable import PuzzleLab

@MainActor
final class ZipTests: XCTestCase {
    /** Zip ships 1001-1500 for now (blocks 3-8 of `tools/generate_zip_levels.py` not generated yet). */
    private let zipLevelCount = 1500

    private func load() throws -> [ZipLevel] {
        let array = try GoldenFiles.pack("zip_levels").getJSONArray("levels")
        return (0..<array.length()).map { ZipLevel.parse(array.getJSONObject($0)) }.sorted { $0.id < $1.id }
    }

    // MARK: LevelPacksTest.zipSolutionsVisitEveryCellAndTheDotsInOrder

    func testZipSolutionsVisitEveryCellAndTheDotsInOrder() throws {
        let levels = try load()
        XCTAssertEqual(zipLevelCount, levels.count)
        XCTAssertEqual(Array(1...zipLevelCount), levels.map(\.id))
        for level in levels {
            let where_ = "zip \(level.id)"
            let path = level.solution
            XCTAssertEqual(Set(0..<level.cellCount), Set(path), "\(where_): not every cell")
            XCTAssertEqual(level.cellCount, path.count, "\(where_): repeats a cell")
            let walls = Set(level.walls.map { [min($0.first, $0.second), max($0.first, $0.second)] })
            for k in 1..<path.count {
                let a = path[k - 1], b = path[k]
                let adjacent = (level.row(a) == level.row(b) && abs(a - b) == 1) || abs(a - b) == level.cols
                XCTAssertTrue(adjacent, "\(where_): step \(k) is not a neighbour")
                XCTAssertFalse(walls.contains([min(a, b), max(a, b)]), "\(where_): step \(k) crosses a wall")
            }
            XCTAssertEqual(level.dots.first, path.first, "\(where_): start")
            XCTAssertEqual(level.dots.last, path.last, "\(where_): end")
            let order = level.dots.map { d in path.firstIndex(of: d) ?? -1 }
            XCTAssertEqual(order.sorted(), order, "\(where_): dots out of order")
        }
    }

    // MARK: Golden (Android ZipModel.kt on the JVM)

    private func feedbackOrdinal(_ f: ZipGame.Feedback?) -> Int {
        switch f {
        case nil: return -1
        case .StartAtOne: return 0
        case .WrongOrder: return 1
        case .EndTooSoon: return 2
        }
    }

    func testGoldenMatchesAndroidModel() throws {
        let levels = try load()
        let golden = try XCTUnwrap(GoldenFiles.json("ZipGolden")["levels"] as? [[String: Any]])
        XCTAssertEqual(levels.count, golden.count)
        for (level, g) in zip(levels, golden) {
            let where_ = "zip \(level.id)"
            XCTAssertEqual(level.id, g["id"] as? Int, where_)
            XCTAssertEqual(level.cellCount, g["cells"] as? Int, where_)

            let game = ZipGame(level, nil)
            var hints = GoldenFnv()
            var steps = 0
            while !game.isSolved && steps < level.cellCount + 2 {
                game.hint()
                hints.add(game.path.count); hints.add(game.hintRange?.lowerBound ?? -1); hints.add(game.hintRange?.upperBound ?? -1)
                steps += 1
            }
            hints.add(game.isSolved ? 1 : 0)
            XCTAssertEqual(steps, g["hintSteps"] as? Int, "\(where_) hint steps")
            XCTAssertEqual(hints.hex, g["hints"] as? String, "\(where_) hint play")

            let s = ZipGame(level, nil)
            let rnd = JavaRandom(Int64(level.id))
            var sim = GoldenFnv()
            let n = level.cellCount
            s.beginStroke(level.dots[0])
            for _ in 0..<120 {
                let r = rnd.nextInt(100)
                if r < 6 {
                    s.endStroke(); s.beginStroke(rnd.nextInt(n))
                } else if r < 40 {
                    s.drag(rnd.nextInt(n))
                } else if r < 78 {
                    let next = s.path.count < n ? level.solution[s.path.count] : rnd.nextInt(n)
                    s.drag(next)
                } else if r < 84 {
                    s.endStroke(); s.undo(); s.beginStroke(s.end ?? level.dots[0])
                } else if r < 87 {
                    s.endStroke(); s.clear(); s.beginStroke(level.dots[0])
                } else if r < 90 {
                    s.endStroke(); s.hint(); s.beginStroke(s.end ?? level.dots[0])
                } else {
                    s.endStroke(); s.beginStroke(rnd.nextInt(n)); s.drag(rnd.nextInt(n))
                }
                sim.add(s.path.count)
                s.path.forEach { sim.add($0) }
                sim.add(s.errorCount); sim.add(feedbackOrdinal(s.feedback)); sim.add(s.isSolved ? 1 : 0)
                sim.add(s.revision); sim.add(s.dotCount); sim.add(s.nextDot ?? -1); sim.add(s.canUndo ? 1 : 0)
                s.clearFeedback()
            }
            s.endStroke()
            s.elapsed = 7
            XCTAssertEqual(sim.hex, g["sim"] as? String, "\(where_) scripted strokes")
            let state = s.encodeState()
            XCTAssertEqual(state, g["state"] as? String, "\(where_) saved state")
            if let state {
                let restored = ZipGame(level, state)
                XCTAssertEqual(restored.path, s.path, "\(where_) restore")
                XCTAssertEqual(restored.elapsed, 7)
                XCTAssertEqual(restored.hintsUsed, s.hintsUsed)
                XCTAssertEqual(restored.dotCount, s.visitedDots)
            }
        }
    }

    func testRulesAndFeedback() throws {
        let level = try XCTUnwrap(try load().first)
        let game = ZipGame(level, nil)
        let notOne = (0..<level.cellCount).first { $0 != level.dots[0] && !isNeighbour(level, level.dots[0], $0) }!
        game.beginStroke(notOne)
        XCTAssertEqual(game.feedbackMessage, "Start your path on 1")
        XCTAssertEqual(game.errorCount, 1)
        game.endStroke()
        game.beginStroke(level.dots[0])
        for cell in level.solution.dropFirst() { game.drag(cell) }
        game.endStroke()
        XCTAssertTrue(game.isSolved)
        XCTAssertEqual(game.statusText, "Solved!")
        XCTAssertEqual(game.progressText, "\(level.cellCount)/\(level.cellCount)")
        XCTAssertNil(game.encodeState())
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(ZipGame(level, "{\"p\":[\(level.dots[0]),99999]}").path, [], "invalid saves are ignored")
    }

    private func isNeighbour(_ level: ZipLevel, _ a: Int, _ b: Int) -> Bool {
        abs(level.row(a) - level.row(b)) + abs(level.col(a) - level.col(b)) == 1
    }
}
