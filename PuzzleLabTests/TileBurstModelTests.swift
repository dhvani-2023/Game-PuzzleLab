import XCTest
#if canImport(PuzzleLab)
@testable import PuzzleLab
#else
@testable import TileCore
#endif

/// Port of LevelPacksTest.tileBurstLevelsAreWellFormed plus rule checks for the bit-board engine.
final class TileBurstModelTests: XCTestCase {
    private var levels: [TileLevel] { TileBurstGoldenTests.levels }

    // MARK: LevelPacksTest (JUnit) port

    func testTileBurstLevelsAreWellFormed() {
        XCTAssertEqual(levels.count, 3000)
        XCTAssertEqual(levels.map(\.id), Array(1...3000))
        for level in levels {
            let whereText = "tileburst \(level.id)"
            XCTAssertEqual(level.pattern.count, 8, whereText)
            XCTAssertTrue(level.pattern.allSatisfy { $0.count == 8 }, whereText)
            XCTAssertFalse(level.goals.isEmpty, "\(whereText): no goals")
            XCTAssertTrue(level.par >= 1, "\(whereText): par")
            XCTAssertTrue((0.0...1.0).contains(level.pressure), "\(whereText): pressure")
        }
    }

    // MARK: Rules

    private func piece(_ shapeID: Int, id: Int = 1, gemCell: Int? = nil, gem: TileGem? = nil) -> TilePiece {
        TilePiece(id: id, shape: TileShape.all[shapeID], gemCell: gemCell, gem: gem)
    }

    func testScoreFormulaComboGraceAndFever() {
        let board = TileBoard(nil)
        // Fill row 0 with a 5-line and a 3-line: one line, combo 1 → 10·1·2·1 = 20 (+ cells).
        _ = board.place(piece(7), TileGrid.index(0, 0))
        let p = board.place(piece(3), TileGrid.index(0, 5))!
        XCTAssertEqual(p.lines, 1)
        XCTAssertEqual(p.linePoints, 20)
        XCTAssertEqual(p.cellPoints, 3)
        XCTAssertEqual(p.combo, 1)
        XCTAssertTrue(p.perfect, "row 0 was the only thing on the board")
        XCTAssertEqual(p.bonusPoints, TileBoard.PERFECT_BONUS)
        XCTAssertEqual(board.score, 5 + 3 + 20 + 300)

        // Two misses keep the combo, the third breaks it.
        _ = board.place(piece(0), TileGrid.index(7, 7))
        XCTAssertEqual(board.combo, 1)
        _ = board.place(piece(0), TileGrid.index(7, 6))
        XCTAssertEqual(board.combo, 1)
        let third = board.place(piece(0), TileGrid.index(7, 5))!
        XCTAssertTrue(third.comboBroke)
        XCTAssertEqual(board.combo, 0)
    }

    func testFeverDoublesLinePointsAtComboEight() {
        let board = TileBoard(nil)
        var last: TilePlacement?
        for k in 0..<9 {
            let r = k % 8
            _ = board.place(piece(7, id: 2 * k), TileGrid.index(r, 0))
            last = board.place(piece(3, id: 2 * k + 1), TileGrid.index(r, 5))
            if k == 7 { XCTAssertTrue(last!.feverStarted) }
        }
        // Combo 9: 20 · (1 + 8/4) · 2 = 120.
        XCTAssertEqual(last?.combo, 9)
        XCTAssertEqual(last?.linePoints, 120)
        XCTAssertTrue(board.fever)
    }

    func testReviveClearsTheMostCrowded3x3() {
        let board = TileBoard(nil)
        _ = board.place(piece(10), TileGrid.index(4, 4))  // 3×3 square at rows 4-6, cols 4-6
        _ = board.place(piece(0, id: 2), TileGrid.index(0, 0))
        let cleared = board.revive()
        XCTAssertEqual(cleared.count, 9)
        XCTAssertEqual(cleared.first?.cell, TileGrid.index(5, 5), "the centre goes first")
        XCTAssertEqual(board.occupancy, TileGrid.bit(0))
    }

    func testStartingPictureNeverHoldsAFullLine() {
        for level in levels.prefix(400) {
            let board = TileBoard(level)
            XCTAssertEqual(TileGrid.lineMask(board.occupancy), 0, "level \(level.id)")
        }
    }

    func testDealerAlwaysDealsSomethingThatFits() {
        let dealer = TileDealer(20261108, 0.9)
        var rng = TileRNG(5)
        for _ in 0..<200 {
            let a = rng.next()
            let occ = a | rng.next()
            let tray = dealer.deal(occ, [], rescue: false)
            XCTAssertEqual(tray.count, 3)
            if TileShape.all.contains(where: { $0.fits(occ) }) {
                XCTAssertTrue(tray.contains { $0.shape.fits(occ) })
            }
        }
    }
}
