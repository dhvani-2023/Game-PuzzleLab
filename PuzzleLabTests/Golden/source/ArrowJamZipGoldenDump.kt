// Golden dump for the iOS port: runs the Android ArrowModel.kt / ZipModel.kt (unmodified) over every
// bundled level and prints fingerprints of solver output and scripted play traces.
// Build: kotlinc src/*.kt -include-runtime -d golden.jar && java -jar golden.jar <levelsDir> <outDir>
package golden

import com.ngstudio.puzzlelab.braingames.games.arrowjam.ArrowBoard
import com.ngstudio.puzzlelab.braingames.games.arrowjam.ArrowLevel
import com.ngstudio.puzzlelab.braingames.games.zip.ZipGame
import com.ngstudio.puzzlelab.braingames.games.zip.ZipLevel
import org.json.JSONObject
import java.io.File

/** FNV-1a 64 over 32-bit values (the Swift test computes the same). */
class Fnv {
    var h: ULong = 0xcbf29ce484222325uL
    fun add(v: Int) {
        var x = v.toUInt()
        for (k in 0 until 4) {
            h = (h xor (x and 0xFFu).toULong()) * 0x100000001b3uL
            x = x shr 8
        }
    }
    fun hex(): String = h.toString(16).padStart(16, '0')
}

fun <L> load(file: File, parse: (JSONObject) -> L, id: (L) -> Int): List<L> {
    val array = JSONObject(file.readText()).getJSONArray("levels")
    return List(array.length()) { parse(array.getJSONObject(it)) }.sortedBy(id)
}

fun tapCode(r: ArrowBoard.TapResult): Int = when (r) {
    ArrowBoard.TapResult.Exited -> -1
    ArrowBoard.TapResult.None -> -2
    is ArrowBoard.TapResult.Blocked -> r.by * 1000 + r.distance
}

fun arrowPack(levels: List<ArrowLevel>, traceIDs: (ArrowLevel) -> Boolean): String {
    val out = StringBuilder()
    out.append("[")
    levels.forEachIndexed { index, level ->
        val pieces = level.pieces
        val geo = Fnv()
        for (p in pieces) {
            geo.add(p.id); geo.add(p.cells.size); geo.add(p.heading.ordinal); geo.add(p.tailHeading.ordinal)
            for (c in p.cells) { geo.add(c.r); geo.add(c.c) }
        }
        val board = ArrowBoard(level)
        val lanes = Fnv()
        for (i in pieces.indices) {
            lanes.add(board.laneLength(i))
            val b = board.blocker(i)
            lanes.add(b?.first ?: -1); lanes.add(b?.second ?: -1)
        }
        val order = board.solutionOrder()
        val sol = Fnv()
        order?.forEach { sol.add(it) }
        val hint = board.bestHint() ?: -1
        val free = Fnv()
        board.freeArrows.forEach { free.add(it) }
        // Tap every arrow in index order, twice, recording what happens.
        val sweep = ArrowBoard(level)
        val taps = Fnv()
        repeat(2) { for (i in pieces.indices) taps.add(tapCode(sweep.tap(i))) }
        taps.add(sweep.remaining)
        // Hint play: follow the hint until the board is clear (selected boards only; it is slow).
        var trace = ""
        var traceLen = -1
        if (traceIDs(level)) {
            val t = ArrowBoard(level)
            val f = Fnv()
            traceLen = 0
            while (!t.isCleared) {
                val h = t.bestHint() ?: break
                f.add(h)
                t.remove(h)
                traceLen++
            }
            trace = f.hex()
        }
        if (index > 0) out.append(",\n")
        out.append("{\"id\":${level.id},\"n\":${pieces.size},\"a\":${level.a.size},\"w\":${level.w},\"h\":${level.h},")
        out.append("\"geo\":\"${geo.hex()}\",\"lanes\":\"${lanes.hex()}\",")
        out.append("\"sol\":\"${if (order == null) "stuck" else sol.hex()}\",\"solLen\":${order?.size ?: -1},")
        out.append("\"hint\":$hint,\"free\":\"${free.hex()}\",\"taps\":\"${taps.hex()}\"")
        if (traceLen >= 0) out.append(",\"trace\":\"$trace\",\"traceLen\":$traceLen")
        out.append("}")
    }
    out.append("]")
    return out.toString()
}

fun zipPack(levels: List<ZipLevel>): String {
    val out = StringBuilder()
    out.append("[")
    levels.forEachIndexed { index, level ->
        // Hint play from an empty board.
        val g = ZipGame(level, null)
        val hints = Fnv()
        var steps = 0
        while (!g.isSolved && steps < level.cellCount + 2) {
            g.hint()
            hints.add(g.path.size); hints.add(g.hintRange?.first ?: -1); hints.add(g.hintRange?.last ?: -1)
            steps++
        }
        hints.add(if (g.isSolved) 1 else 0)
        // Scripted strokes from java.util.Random(id): begin, drag (often along the solution), undo, clear, hint.
        val s = ZipGame(level, null)
        val rnd = java.util.Random(level.id.toLong())
        val sim = Fnv()
        val n = level.cellCount
        s.beginStroke(level.dots.first())
        for (k in 0 until 120) {
            val r = rnd.nextInt(100)
            when {
                r < 6 -> { s.endStroke(); s.beginStroke(rnd.nextInt(n)) }
                r < 40 -> s.drag(rnd.nextInt(n))
                r < 78 -> { val next = if (s.path.size < n) level.solution[s.path.size] else rnd.nextInt(n); s.drag(next) }
                r < 84 -> { s.endStroke(); s.undo(); s.beginStroke(s.end ?: level.dots.first()) }
                r < 87 -> { s.endStroke(); s.clear(); s.beginStroke(level.dots.first()) }
                r < 90 -> { s.endStroke(); s.hint(); s.beginStroke(s.end ?: level.dots.first()) }
                else -> { s.endStroke(); s.beginStroke(rnd.nextInt(n)); s.drag(rnd.nextInt(n)) }
            }
            sim.add(s.path.size)
            s.path.forEach { sim.add(it) }
            sim.add(s.errorCount); sim.add(s.feedback?.ordinal ?: -1); sim.add(if (s.isSolved) 1 else 0)
            sim.add(s.revision); sim.add(s.dotCount); sim.add(s.nextDot ?: -1); sim.add(if (s.canUndo) 1 else 0)
            s.clearFeedback()
        }
        s.endStroke()
        s.elapsed = 7
        val state = s.encodeState()
        if (index > 0) out.append(",\n")
        out.append("{\"id\":${level.id},\"cells\":${level.cellCount},\"hints\":\"${hints.hex()}\",\"hintSteps\":$steps,")
        out.append("\"sim\":\"${sim.hex()}\",\"state\":${if (state == null) "null" else JSONObject().put("s", state).toString().removePrefix("{\"s\":").removeSuffix("}")}}")
    }
    out.append("]")
    return out.toString()
}

fun main(args: Array<String>) {
    val dir = File(args[0])
    val outDir = File(args[1])
    val main = load(File(dir, "arrowjam_levels.json"), ArrowLevel::parse) { it.id }
    val daily = load(File(dir, "arrowjam_daily.json"), ArrowLevel::parse) { it.id }
    val trace: (ArrowLevel) -> Boolean = { it.id <= 30 || (it.id % 100 == 0 && it.a.size <= 150) }
    File(outDir, "ArrowJamGolden.json").writeText(
        "{\"source\":\"ArrowJamZipGoldenDump.kt (Android ArrowModel.kt)\",\n\"levels\":" + arrowPack(main, trace) +
            ",\n\"daily\":" + arrowPack(daily) { it.id % 50 == 0 && it.a.size <= 150 } + "}\n",
    )
    val zip = load(File(dir, "zip_levels.json"), ZipLevel::parse) { it.id }
    File(outDir, "ZipGolden.json").writeText("{\"source\":\"ArrowJamZipGoldenDump.kt (Android ZipModel.kt)\",\n\"levels\":" + zipPack(zip) + "}\n")
    println("arrow ${main.size}+${daily.size}, zip ${zip.size}")
}
