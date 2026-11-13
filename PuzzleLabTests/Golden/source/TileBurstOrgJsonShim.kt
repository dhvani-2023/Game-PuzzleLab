package org.json

/** Minimal org.json stand-in (the Maven artifact isn't cached offline). Numbers follow Android's
 *  JSONTokener: a literal with '.', 'e' or 'E' is Double.valueOf, otherwise Long (Int when it fits). */
class JSONObject() {
    val map = LinkedHashMap<String, Any?>()

    constructor(text: String) : this() {
        val p = Parser(text)
        val v = p.value()
        @Suppress("UNCHECKED_CAST")
        map.putAll((v as JSONObject).map)
    }

    fun has(key: String) = map.containsKey(key)
    fun put(key: String, value: Any?): JSONObject { map[key] = value; return this }
    fun getJSONArray(key: String): JSONArray = map[key] as JSONArray
    fun optJSONArray(key: String): JSONArray? = map[key] as? JSONArray
    fun getJSONObject(key: String): JSONObject = map[key] as JSONObject
    fun getString(key: String): String = map[key] as String
    fun getInt(key: String): Int = (map[key] as Number).toInt()
    fun optDouble(key: String, def: Double): Double = (map[key] as? Number)?.toDouble() ?: def
    fun optLong(key: String): Long = (map[key] as? Number)?.toLong() ?: 0L
    fun optString(key: String, def: String): String = (map[key] as? String) ?: def

    override fun toString(): String {
        val sb = StringBuilder("{")
        var first = true
        for ((k, v) in map) {
            if (!first) sb.append(',')
            first = false
            sb.append(quote(k)).append(':').append(encode(v))
        }
        return sb.append('}').toString()
    }
}

class JSONArray() {
    val list = ArrayList<Any?>()

    constructor(c: Collection<*>) : this() { list.addAll(c) }

    fun length() = list.size
    fun put(v: Any?): JSONArray { list.add(v); return this }
    fun getString(i: Int): String = list[i] as String
    fun getJSONObject(i: Int): JSONObject = list[i] as JSONObject
    fun getInt(i: Int): Int = (list[i] as Number).toInt()

    override fun toString(): String = list.joinToString(",", "[", "]") { encode(it) }
}

internal fun quote(s: String): String {
    val sb = StringBuilder("\"")
    for (ch in s) {
        when (ch) {
            '"' -> sb.append("\\\"")
            '\\' -> sb.append("\\\\")
            '\n' -> sb.append("\\n")
            else -> if (ch < ' ') sb.append(String.format("\\u%04x", ch.code)) else sb.append(ch)
        }
    }
    return sb.append('"').toString()
}

internal fun encode(v: Any?): String = when (v) {
    null -> "null"
    is String -> quote(v)
    is JSONObject, is JSONArray -> v.toString()
    is Double -> v.toString()
    is Float -> v.toString()
    else -> v.toString()
}

private class Parser(val s: String) {
    var i = 0
    fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
    fun value(): Any? {
        ws()
        return when (val c = s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> str()
            't' -> { i += 4; true }
            'f' -> { i += 5; false }
            'n' -> { i += 4; null }
            else -> if (c == '-' || c.isDigit()) num() else error("bad json at $i")
        }
    }
    fun obj(): JSONObject {
        val o = JSONObject()
        i++
        ws()
        if (s[i] == '}') { i++; return o }
        while (true) {
            ws(); val k = str(); ws(); i++ // ':'
            o.map[k] = value()
            ws()
            if (s[i] == ',') { i++; continue }
            i++ // '}'
            return o
        }
    }
    fun arr(): JSONArray {
        val a = JSONArray()
        i++
        ws()
        if (s[i] == ']') { i++; return a }
        while (true) {
            a.list.add(value())
            ws()
            if (s[i] == ',') { i++; continue }
            i++
            return a
        }
    }
    fun str(): String {
        val sb = StringBuilder()
        i++
        while (s[i] != '"') {
            if (s[i] == '\\') {
                i++
                when (s[i]) {
                    'n' -> sb.append('\n'); 't' -> sb.append('\t'); 'r' -> sb.append('\r'); 'b' -> sb.append('\b'); 'f' -> sb.append('\u000c')
                    'u' -> { sb.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                    else -> sb.append(s[i])
                }
                i++
            } else sb.append(s[i++])
        }
        i++
        return sb.toString()
    }
    fun num(): Number {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
        val lit = s.substring(start, i)
        if (lit.contains('.') || lit.contains('e') || lit.contains('E')) return java.lang.Double.valueOf(lit)
        val l = lit.toLong()
        return if (l in Int.MIN_VALUE..Int.MAX_VALUE) l.toInt() else l
    }
}
