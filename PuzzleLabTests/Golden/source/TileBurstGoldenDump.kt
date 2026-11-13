package com.ngstudio.puzzlelab.braingames

import com.ngstudio.puzzlelab.braingames.games.tileburst.TileBoard
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileBot
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileCleared
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileDealer
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileGrid
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileLevel
import com.ngstudio.puzzlelab.braingames.games.tileburst.TilePiece
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileRNG
import com.ngstudio.puzzlelab.braingames.games.tileburst.TileShape
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate

/**
 * Golden dump for the iOS port (PuzzleLabTests/TileBurstGoldenTests.swift mirrors this file).
 * Every Adventure level is played by TileBot with the level's own seed, plus Classic and Daily runs,
 * and every deal, move, placement and revive is folded into a 64-bit FNV hash.
 */
class TileBurstGoldenDump {
    private class H {
        var h = -3750763034362895579L
        fun add(v: Long) { h = (h xor v) * 1099511628211L }
        fun add(v: Int) = add(v.toLong())
        fun add(b: Boolean) = add(if (b) 1L else 0L)
        fun add(d: Double) = add(java.lang.Double.doubleToRawLongBits(d))
    }

    private fun hex(v: Long) = java.lang.Long.toHexString(v)

    private class Run(val hash: Long, val score: Int, val moves: Int, val rounds: Int, val outcome: Int, val trace: List<Long>?)

    private fun hashTray(h: H, tray: Array<TilePiece?>) {
        h.add(1000)
        for (p in tray) {
            if (p == null) { h.add(-1); continue }
            h.add(p.id); h.add(p.shape.id); h.add(p.gemCell ?: -1); h.add(p.gem?.ordinal ?: -1)
        }
    }

    private fun hashCleared(h: H, list: List<TileCleared>) {
        h.add(list.size)
        for (c in list) {
            h.add(c.cell); h.add(c.block.id); h.add(c.block.tone); h.add(c.block.gem?.ordinal ?: -1); h.add(c.block.prefilled); h.add(c.distance)
        }
    }

    private fun hashBoard(h: H, b: TileBoard) {
        h.add(b.score); h.add(b.occupancy); h.add(b.combo); h.add(b.misses); h.add(b.bestCombo); h.add(b.placements); h.add(b.linesCleared)
        for (g in b.collected.indices) { h.add(b.collected[g]); h.add(b.goalTotals[g]); h.add(b.remaining(g)) }
        h.add(b.goalsDone); h.add(b.fever); h.add(b.prefilledLeft)
        b.neededGems.forEach { h.add(it.ordinal) }
    }

    private fun simulate(level: TileLevel?, seed: Long, pressure: Double, gemRate: Double, endless: Boolean, maxMoves: Int, keepTrace: Boolean): Run {
        val h = H()
        val trace = if (keepTrace) ArrayList<Long>() else null
        val board = TileBoard(level)
        val dealer = TileDealer(seed, pressure, gemRate)
        val tray = arrayOfNulls<TilePiece>(3)
        dealer.deal(board).forEachIndexed { k, p -> tray[k] = p }
        hashTray(h, tray)
        hashBoard(h, board)
        trace?.add(h.h)
        var rounds = 1
        var revived = false
        var moves = 0
        var outcome = 2
        while (moves < maxMoves) {
            val move = TileBot.bestMove(board, tray.toList())
            if (move == null) { outcome = 3; break }
            h.add(2000); h.add(move.slot); h.add(move.origin); h.add(move.value)
            val piece = tray[move.slot]!!
            val p = board.place(piece, move.origin)!!
            tray[move.slot] = null
            moves++
            h.add(3000)
            h.add(p.cells.size); p.cells.forEach { h.add(it) }
            p.blocks.forEach { h.add(it.id); h.add(it.tone); h.add(it.gem?.ordinal ?: -1) }
            h.add(p.rows.size); p.rows.forEach { h.add(it) }
            h.add(p.cols.size); p.cols.forEach { h.add(it) }
            hashCleared(h, p.cleared)
            h.add(p.gems.size); p.gems.forEach { (cell, gem, goal) -> h.add(cell); h.add(gem.ordinal); h.add(goal ?: -1) }
            h.add(p.cellPoints); h.add(p.linePoints); h.add(p.bonusPoints); h.add(p.combo); h.add(p.graceLeft); h.add(p.comboBroke)
            h.add(p.praise ?: -1); h.add(p.perfect); h.add(p.feverStarted); h.add(p.feverEnded); h.add(p.lines); h.add(p.total)
            hashBoard(h, board)
            trace?.add(h.h)
            if (board.goalsDone) { outcome = 0; break }
            if (tray.all { it == null }) {
                if (endless) dealer.pressure = TileDealer.classicPressure(board.score)
                dealer.deal(board).forEachIndexed { k, np -> tray[k] = np }
                rounds++
                hashTray(h, tray)
            }
            if (!board.anyFits(tray.toList())) {
                if (revived) { outcome = 1; break }
                revived = true
                h.add(4000)
                hashCleared(h, board.revive())
                dealer.deal(board, rescue = true).forEachIndexed { k, np -> tray[k] = np }
                rounds++
                hashTray(h, tray)
                hashBoard(h, board)
            }
        }
        return Run(h.h, board.score, moves, rounds, outcome, trace)
    }

    private fun runJson(r: Run, extra: JSONObject = JSONObject()): JSONObject {
        extra.put("h", hex(r.hash)); extra.put("s", r.score); extra.put("m", r.moves); extra.put("r", r.rounds); extra.put("o", r.outcome)
        r.trace?.let { t -> extra.put("trace", JSONArray(t.map { hex(it) })) }
        return extra
    }

    private fun levelHash(l: TileLevel): Long {
        val h = H()
        h.add(l.id); h.add(l.tier.ordinal); h.add(l.par); h.add(l.pressure); h.add(l.gemRate); h.add(l.seed)
        h.add(l.pattern.size); l.pattern.forEach { row -> h.add(row.length); row.forEach { h.add(it.code) } }
        h.add(l.gems?.size ?: -1); l.gems?.forEach { row -> h.add(row.length); row.forEach { h.add(it.code) } }
        h.add(l.goals.size); l.goals.forEach { g -> h.add(g.kind.ordinal); h.add(g.gem?.ordinal ?: -1); h.add(g.n ?: -1) }
        h.add(l.tip?.length ?: -1); l.tip?.forEach { h.add(it.code) }
        h.add(l.sizeLabel.length); l.sizeLabel.forEach { h.add(it.code) }
        h.add(l.world)
        return h.h
    }

    fun dump() {
        val started = System.currentTimeMillis()
        val file = File("/Volumes/Work/Raj/Android/Game-PuzzelLab-master/app/src/main/assets/levels/tileburst_levels.json")
        val array = JSONObject(file.readText()).getJSONArray("levels")
        val levels = List(array.length()) { TileLevel.parse(array.getJSONObject(it)) }.sortedBy { it.id }
        val out = JSONObject()

        // RNG streams.
        val rng = JSONArray()
        for (seed in listOf(0L, 1L, -1L, 42L, Long.MAX_VALUE, Long.MIN_VALUE, 20261108L, 45711348L)) {
            val r = TileRNG(seed)
            val o = JSONObject()
            o.put("seed", seed.toString())
            o.put("next", JSONArray((0 until 6).map { hex(r.next()) }))
            o.put("int7", JSONArray((0 until 12).map { r.int(7) }))
            o.put("int37", JSONArray((0 until 12).map { r.int(37) }))
            o.put("int1", JSONArray((0 until 3).map { r.int(1) }))
            o.put("unit", JSONArray((0 until 6).map { hex(java.lang.Double.doubleToRawLongBits(r.unit())) }))
            val list = (0 until 10).toMutableList()
            r.shuffle(list)
            o.put("shuffle", JSONArray(list))
            rng.put(o)
        }
        out.put("rng", rng)

        // Shapes.
        val shapes = JSONArray()
        for (s in TileShape.all) {
            val h = H()
            s.placements.forEach { (o, m) -> h.add(o); h.add(m) }
            shapes.put(JSONObject().put("id", s.id).put("family", s.family.ordinal).put("tone", s.tone).put("size", s.size).put("rows", s.rows).put("cols", s.cols)
                .put("placements", s.placements.size).put("ph", hex(h.h))
                .put("w", JSONArray(listOf(0.0, 0.25, 0.5, 0.85, 1.0, 1.4).map { hex(java.lang.Double.doubleToRawLongBits(s.weight(it))) })))
        }
        out.put("shapes", shapes)

        // hypot over every half-step pair the board can produce.
        val hyp = JSONArray()
        for (a in -16..16) for (b in -16..16) hyp.put(hex(java.lang.Double.doubleToRawLongBits(kotlin.math.hypot(a / 2.0, b / 2.0))))
        out.put("hypot", hyp)

        // Rules tables.
        val praise = JSONArray()
        for (lines in 0..6) for (combo in 0..20) praise.put(TileBoard.praise(lines, combo) ?: -1)
        out.put("praise", praise)
        out.put("classicPressure", JSONArray(listOf(0, 1, 150, 2999, 4500, 8100, 8999, 9000, 12000).map { hex(java.lang.Double.doubleToRawLongBits(TileDealer.classicPressure(it))) }))
        val masks = H()
        for (seed in 1L..200L) {
            val r = TileRNG(seed * 7919)
            val occ = r.next() and r.next()
            masks.add(TileGrid.lineMask(occ)); masks.add(TileGrid.holes(occ)); masks.add(TileGrid.roughness(occ))
            val l = TileGrid.lines(occ); l.rows.forEach { masks.add(it) }; l.cols.forEach { masks.add(it) }; masks.add(l.mask)
            TileShape.all.forEach { masks.add(it.fits(occ)) }
            masks.add(TileDealer.solvable(occ, listOf(TileShape.all[(seed % 37).toInt()], TileShape.all[((seed * 3) % 37).toInt()], TileShape.all[10]), intArrayOf(4000)))
        }
        out.put("gridHash", hex(masks.h))

        // Every Adventure level.
        val adv = JSONArray()
        var advMoves = 0
        for (l in levels) {
            val board = TileBoard(l)
            val o = JSONObject()
            o.put("id", l.id)
            o.put("lh", hex(levelHash(l)))
            o.put("p", hex(java.lang.Double.doubleToRawLongBits(l.pressure)))
            o.put("g", hex(java.lang.Double.doubleToRawLongBits(l.gemRate)))
            o.put("occ", hex(board.occupancy))
            o.put("totals", JSONArray(board.goalTotals.toList()))
            val run = simulate(l, l.seed, l.pressure, l.gemRate, endless = false, maxMoves = 240, keepTrace = l.id <= 3 || l.id == 1500 || l.id == 3000)
            advMoves += run.moves
            adv.put(runJson(run, o))
        }
        out.put("adventure", adv)

        // Classic: random seeds in the app, fixed ones here.
        val classic = JSONArray()
        for (seed in listOf(1L, 2L, 3L, 7L, 99L, 12345L, 987654321L, 4611686018427387904L, Long.MAX_VALUE - 1) + (100L until 124L)) {
            val run = simulate(null, seed, 0.0, 0.0, endless = true, maxMoves = 300, keepTrace = seed == 1L)
            classic.put(runJson(run, JSONObject().put("seed", seed.toString())))
        }
        out.put("classic", classic)

        // Daily: yyyyMMdd seeds.
        val daily = JSONArray()
        var d = LocalDate.of(2026, 11, 1)
        repeat(61) {
            val day = d.year * 10_000 + d.monthValue * 100 + d.dayOfMonth
            val run = simulate(null, day.toLong(), 0.0, 0.0, endless = true, maxMoves = 300, keepTrace = day == 20261108)
            daily.put(runJson(run, JSONObject().put("day", day).put("target", 1500 + (day % 9) * 250)))
            d = d.plusDays(1)
        }
        out.put("daily", daily)

        // Rescue deals on a crowded board.
        val rescue = H()
        for (seed in 1L..60L) {
            val r = TileRNG(seed)
            val occ = r.next() or r.next()
            val dealer = TileDealer(seed, 0.5, 0.0)
            dealer.deal(occ, emptyList(), rescue = true).forEach { rescue.add(it.id); rescue.add(it.shape.id) }
            dealer.deal(occ, emptyList(), rescue = false).forEach { rescue.add(it.id); rescue.add(it.shape.id) }
        }
        out.put("rescueHash", hex(rescue.h))

        val dir = File("/private/tmp/claude-501/-Users-ngd-vi--claude-spares-spare-i6ZDWN/994b964a-4e20-4a95-81be-8ff2ef2b19ea/scratchpad/tb/out")
        dir.mkdirs()
        File(dir, "tileburst_golden.json").writeText(out.toString())
        println("TileBurst golden: ${levels.size} levels, $advMoves adventure moves, ${System.currentTimeMillis() - started} ms")
    }
}

fun main() { TileBurstGoldenDump().dump() }
