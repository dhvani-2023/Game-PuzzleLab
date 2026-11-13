import XCTest
@testable import PuzzleLab

/// Patches: the level pack (port of `LevelPacksTest.patchesSolutionsTileTheGridAndMatchTheClues`) and the
/// `PatchesGame` rules (place, tap, undo history of 200, clear, hint, stars, save/restore).
final class PatchesTests: XCTestCase {
    private static func fixture(_ name: String, _ ext: String, filePath: String = #filePath) -> URL? {
        let here = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Levels"),
            Bundle(for: PatchesTests.self).url(forResource: name, withExtension: ext),
            here.appendingPathComponent("../PuzzleLab/Resources/Levels/\(name).\(ext)"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let levels: [PatchesLevel] = {
        guard let url = fixture("patches_levels", "json"), let data = try? Data(contentsOf: url), let root = JSONObject(data: data) else { return [] }
        let array = root.getJSONArray("levels")
        return (0..<array.length()).map { PatchesLevel.parse(array.getJSONObject($0)) }.sorted { $0.id < $1.id }
    }()

    // MARK: LevelPacksTest

    func testPatchesSolutionsTileTheGridAndMatchTheClues() {
        let levels = Self.levels
        XCTAssertEqual(levels.count, 3000)
        XCTAssertEqual(levels.map(\.id), Array(1...3000))
        for level in levels {
            let at = "patches \(level.id)"
            XCTAssertEqual(level.clues.count, level.solution.count, at)
            var covered = Set<Cell>()
            for (i, rect) in level.solution.enumerated() {
                let clue = level.clues[i]
                XCTAssertTrue(rect.contains(clue.cell), "\(at): clue \(i) outside its patch")
                XCTAssertTrue(clue.accepts(rect), "\(at): clue \(i) rejects its patch")
                for r in rect.row..<(rect.row + rect.height) {
                    for c in rect.col..<(rect.col + rect.width) {
                        XCTAssertTrue(r >= 0 && r < level.rows && c >= 0 && c < level.cols, "\(at): patch leaves the grid")
                        XCTAssertTrue(covered.insert(Cell(r, c)).inserted, "\(at): patches overlap")
                    }
                }
            }
            XCTAssertEqual(level.rows * level.cols, covered.count, "\(at): gaps")
        }
    }

    func testParseKeepsShapeAndAnySizeClues() {
        let level = PatchesLevel.parse(JSONObject(string: """
        {"id":7,"tier":"medium","rows":2,"cols":3,"clues":[{"r":0,"c":0,"n":4,"s":"wide","k":3},{"r":1,"c":2,"s":"tall","k":9}],
         "solution":[[0,0,2,2],[0,2,2,1]]}
        """)!)
        XCTAssertEqual(level.id, 7)
        XCTAssertEqual(level.tier, .Medium)
        XCTAssertEqual(level.sizeLabel, "2×3")
        XCTAssertEqual(level.clues[0], PatchesClue(0, 0, 4, .Wide, 3))
        XCTAssertNil(level.clues[1].n)
        XCTAssertEqual(level.clues[1].s, .Tall)
        XCTAssertEqual(level.solution[1], GridRect(0, 2, 2, 1))
        XCTAssertFalse(level.clues[0].accepts(GridRect(0, 0, 2, 2)), "a 2×2 is square, the clue wants wide")
        XCTAssertTrue(level.clues[0].accepts(GridRect(0, 0, 1, 4)))
        XCTAssertTrue(level.clues[1].accepts(GridRect(0, 2, 2, 1)))
        XCTAssertEqual(PatchShape.of(2, 2), .Square)
        XCTAssertEqual(PatchShape.of(1, 3), .Wide)
        XCTAssertEqual(PatchShape.of(3, 1), .Tall)
        XCTAssertEqual(GridRect.spanning(Cell(3, 1), Cell(1, 4)), GridRect(1, 1, 3, 4))
    }

    // MARK: Rules

    private func level(_ id: Int) -> PatchesLevel { Self.levels[id - 1] }

    func testSolvingWithTheSolution() {
        let game = PatchesGame(level(1), nil)
        XCTAssertEqual(game.statusText, "Fill every cell — no gaps, no overlaps")
        for rect in game.level.solution { XCTAssertTrue(game.place(rect)) }
        XCTAssertTrue(game.isSolved)
        XCTAssertEqual(game.statusText, "Solved!")
        XCTAssertEqual(game.progress, 1)
        XCTAssertEqual(game.progressText, "\(game.rows * game.cols)/\(game.rows * game.cols)")
        XCTAssertEqual(game.hintsUsed, 0)
        XCTAssertEqual(Scoring.stars(game.hintsUsed), 3)
        XCTAssertFalse(game.canUndo)
        XCTAssertFalse(game.canClear)
        XCTAssertNil(game.encodeState())
        XCTAssertFalse(game.place(game.level.solution[0]), "nothing moves once solved")
    }

    func testRejectsPatchesWithoutExactlyOneClue() {
        let game = PatchesGame(level(1), nil)
        let all = GridRect(0, 0, game.rows, game.cols)
        XCTAssertFalse(game.place(all))
        XCTAssertEqual(game.feedbackMessage, "A patch can only hold one clue")
        XCTAssertEqual(game.errorCount, 1)
        // Find an empty cell (no clue) for a 1×1 patch.
        let empty = (0..<game.rows).flatMap { r in (0..<game.cols).map { Cell(r, $0) } }.first { game.clue($0) == nil }!
        XCTAssertFalse(game.place(GridRect(empty.row, empty.col, 1, 1)))
        XCTAssertEqual(game.feedbackMessage, "Every patch needs exactly one clue")
        XCTAssertEqual(game.errorCount, 2)
        XCTAssertTrue(game.place(game.level.solution[0]))
        XCTAssertNil(game.feedbackMessage, "a good patch clears the message")
        game.clearFeedback()
        XCTAssertEqual(game.actionCount, 1)
    }

    func testPlacingReplacesOverlapsAndTheClueOwnPatch() throws {
        let game = PatchesGame(level(1), nil)
        let sol = game.level.solution
        game.place(sol[0])
        game.place(sol[1])
        XCTAssertEqual(game.patches.count, 2)
        // Re-placing the same rect is a no-op.
        let count = game.placeCount
        XCTAssertTrue(game.place(sol[0]))
        XCTAssertEqual(game.placeCount, count)
        // A patch that overlaps another clue's patch replaces it; a clue's new patch replaces its old one.
        var found: (Int, GridRect, Int)?
        for level in Self.levels.prefix(20) where found == nil {
            let g = PatchesGame(level, nil)
            for i in level.clues.indices where found == nil {
                for rect in candidates(g, owner: i) where rect != level.solution[i] {
                    if let j = level.solution.indices.first(where: { $0 != i && level.solution[$0].intersects(rect) }) {
                        found = (i, rect, j)
                        break
                    }
                }
            }
            if let f = found {
                let (i, rect, j) = f
                g.place(rect)
                XCTAssertEqual(g.patches[i], rect)
                g.place(level.solution[j])
                XCTAssertNil(g.patches[i], "level \(level.id): the overlapped patch is dropped")
                XCTAssertEqual(g.patches[j], level.solution[j])
                g.place(level.solution[i])
                XCTAssertEqual(g.patches[i], level.solution[i])
                XCTAssertEqual(g.patchOwner(level.clues[i].cell), i)
            }
        }
        XCTAssertNotNil(found)
    }

    /// Every rect containing only clue `owner` (small boards only).
    private func candidates(_ game: PatchesGame, owner: Int) -> [GridRect] {
        var out: [GridRect] = []
        for r in 0..<game.rows {
            for c in 0..<game.cols {
                for h in 1...(game.rows - r) {
                    for w in 1...(game.cols - c) {
                        let rect = GridRect(r, c, h, w)
                        if game.cluesIn(rect) == [owner] { out.append(rect) }
                    }
                }
            }
        }
        return out
    }

    func testTapRemovesAPatchOrDropsASingle() {
        let game = PatchesGame(level(1), nil)
        let sol = game.level.solution
        game.place(sol[0])
        XCTAssertTrue(game.tap(Cell(sol[0].row, sol[0].col)))
        XCTAssertNil(game.patches[0])
        XCTAssertTrue(game.canUndo)
        game.undo()
        XCTAssertEqual(game.patches[0], sol[0])
        // A size-1 clue gets a 1×1 patch from a tap (not a removal).
        if let level = Self.levels.first(where: { $0.clues.contains { $0.n == 1 } }) {
            let g = PatchesGame(level, nil)
            let i = level.clues.firstIndex { $0.n == 1 }!
            XCTAssertFalse(g.tap(level.clues[i].cell))
            XCTAssertEqual(g.patches[i], GridRect(level.clues[i].r, level.clues[i].c, 1, 1))
        }
    }

    func testUndoKeepsTheLast200Boards() {
        let game = PatchesGame(level(1), nil)
        let a = game.level.solution[0]
        let alternatives = candidates(game, owner: 0).filter { $0 != a }
        let b = alternatives[0]
        for i in 0..<250 { game.place(i % 2 == 0 ? a : b) }
        var undos = 0
        while game.canUndo { game.undo(); undos += 1 }
        XCTAssertEqual(undos, 200)
        XCTAssertNotNil(game.patches[0], "the oldest boards beyond 200 are gone")
    }

    func testClearThenUndo() {
        let game = PatchesGame(level(2), nil)
        game.place(game.level.solution[0])
        game.place(game.level.solution[1])
        XCTAssertTrue(game.canClear)
        game.clear()
        XCTAssertTrue(game.patches.isEmpty)
        XCTAssertFalse(game.canClear)
        game.undo()
        XCTAssertEqual(game.patches.count, 2)
    }

    func testHintFixesWrongPatchesFirstThenFillsMissing() {
        let game = PatchesGame(level(1), nil)
        let sol = game.level.solution
        let wrong = candidates(game, owner: 1).first { $0 != sol[1] }!
        game.place(wrong)
        game.hint()
        XCTAssertEqual(game.hintsUsed, 1)
        XCTAssertEqual(game.lastHintClue, 1)
        XCTAssertEqual(game.patches[1], sol[1])
        game.hint()
        XCTAssertEqual(game.lastHintClue, 0)
        XCTAssertEqual(Scoring.stars(game.hintsUsed), 1)
        while !game.isSolved { game.hint() }
        XCTAssertEqual(game.hintsUsed, game.level.clues.count)
        let before = game.hintsUsed
        game.hint()
        XCTAssertEqual(game.hintsUsed, before)
        XCTAssertEqual(Scoring.stars(1), 2)
        XCTAssertEqual(Scoring.stars(2), 1)
        XCTAssertEqual(Scoring.stars(9), 1)
    }

    func testSaveAndRestore() throws {
        let game = PatchesGame(level(3), nil)
        XCTAssertNil(game.encodeState(), "nothing worth saving yet")
        game.elapsed = 12
        XCTAssertNotNil(game.encodeState())
        game.place(game.level.solution[0])
        game.place(game.level.solution[2])
        game.hint()
        let state = try XCTUnwrap(game.encodeState())
        let restored = PatchesGame(level(3), state)
        XCTAssertEqual(restored.patches, game.patches)
        XCTAssertEqual(restored.elapsed, 12)
        XCTAssertEqual(restored.hintsUsed, 1)
        XCTAssertFalse(restored.canUndo, "history is not saved")
        // A saved board that no longer fits (overlap, off-grid, wrong clue) is dropped.
        let a = game.level.solution[0]
        let bad = "{\"p\":{\"0\":[\(a.row),\(a.col),\(a.height),\(a.width)],\"1\":[\(a.row),\(a.col),\(a.height),\(a.width)]},\"e\":5,\"h\":2}"
        let dropped = PatchesGame(level(3), bad)
        XCTAssertTrue(dropped.patches.isEmpty)
        XCTAssertEqual(dropped.elapsed, 0)
        XCTAssertTrue(PatchesGame(level(3), "{\"p\":{\"0\":[0,0,99,1]}}").patches.isEmpty)
        XCTAssertTrue(PatchesGame(level(3), "not json").patches.isEmpty)
    }
}
