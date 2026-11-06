package com.portfolioassistant.app.widget

import org.json.JSONArray
import org.json.JSONObject

/**
 * Bloque `v2` del snapshot y reglas de qué dibuja cada tamaño
 * (docs/specs/home-widget-v2-tech.md §3.2 y §3.5). Puro: solo `org.json`,
 * sin `android.*`, para correr en JUnit. Mismas reglas que `FeedPicker`
 * (Swift, `ios/PortyWidget/PortyWidgetFeed.swift`) y `WidgetFeedPicker` (Dart).
 * Ausente = no hay: nunca lanza.
 *
 * Diferencia con `WidgetFeedPicker` (Dart): `hidden_count` de mediano y grande
 * cuenta los vigentes con prio <= 2, como iOS y el chico (Dart cuenta todos).
 */
object PortyFeedPicker {

    class Segment(
        val from: Long,
        val prio: Int,
        val short: String?,
        val title: String?,
        val meta: String?,
    )

    class Question(val ref: String, val t: String, val src: String, val text: String)

    class Item(
        /** Posición en `v2.feed` (los casos compartidos identifican filas así). */
        val index: Int,
        val id: String?,
        val kind: String,
        val icon: String?,
        val tag: String?,
        val paid: Boolean,
        val publishedAt: Long?,
        val expiresAt: Long,
        val segments: List<Segment>,
        val a11y: String?,
        val openTarget: String?,
        val openId: String?,
        val q: Question?,
    )

    class Chart(val kind: String, val points: List<Double>, val baseline: Double?) {
        /** Con menos de 2 puntos no hay línea que dibujar. */
        val isDrawable: Boolean get() = points.size >= 2
    }

    class Block(
        val positionsHidden: Boolean,
        val mood: String,
        val planUntil: Long?,
        val chart: Chart?,
        val feedRev: String?,
        val feed: List<Item>,
        val fallback: Question?,
        val large: List<Question>,
        val labels: JSONObject,
    ) {
        fun label(key: String): String? = str(labels, key)?.takeIf { it.isNotEmpty() }
    }

    /** Lo que escribe el nativo al tocar "siguiente" (`porty_widget_cursor`). */
    class Cursor(val rev: String, val index: Int, val at: Long) {
        fun toJson(): String =
            JSONObject().put("rev", rev).put("index", index).put("at", at).toString()
    }

    sealed class SmallLine {
        class ItemLine(val item: Item) : SmallLine()
        object ChartLine : SmallLine()
        class HiddenCount(val n: Int) : SmallLine()
        object NoNews : SmallLine()
    }

    class MediumPick(
        val item: Item?,
        /** Con posiciones ocultas: cuántas novedades (null = `no_news`). */
        val hiddenCount: Int?,
        val question: Question?,
        val showNext: Boolean,
        val index: Int,
    )

    class LargePick(
        val headerN: Int,
        val rows: List<Item>,
        val hiddenCount: Int?,
        val questions: List<Question>,
    )

    // --- Decodificación tolerante ---------------------------------------

    internal fun str(o: JSONObject?, key: String): String? = (o?.opt(key) as? String)

    private fun lng(o: JSONObject?, key: String): Long? = (o?.opt(key) as? Number)?.toLong()

    private fun int(o: JSONObject?, key: String): Int? = (o?.opt(key) as? Number)?.toInt()

    private fun bool(o: JSONObject?, key: String): Boolean? = o?.opt(key) as? Boolean

    private fun obj(o: JSONObject?, key: String): JSONObject? = o?.opt(key) as? JSONObject

    private fun arr(o: JSONObject?, key: String): JSONArray? = o?.opt(key) as? JSONArray

    private fun question(o: JSONObject?): Question? {
        o ?: return null
        val ref = str(o, "ref") ?: return null
        val t = str(o, "t") ?: return null
        val src = str(o, "src") ?: return null
        val text = str(o, "text") ?: return null
        return Question(ref, t, src, text)
    }

    private fun item(index: Int, o: JSONObject): Item? {
        val kind = str(o, "kind") ?: return null
        val expiresAt = lng(o, "expires_at") ?: return null
        val segsJson = arr(o, "segments") ?: return null
        val segments = ArrayList<Segment>()
        for (i in 0 until segsJson.length()) {
            val s = segsJson.opt(i) as? JSONObject ?: continue
            segments.add(
                Segment(
                    from = lng(s, "from") ?: 0L,
                    prio = int(s, "prio") ?: 3,
                    short = str(s, "short"),
                    title = str(s, "title"),
                    meta = str(s, "meta"),
                ),
            )
        }
        if (segments.isEmpty()) return null
        val open = obj(o, "open")
        return Item(
            index = index,
            id = str(o, "id"),
            kind = kind,
            icon = str(o, "icon"),
            tag = str(o, "tag")?.takeIf { it.isNotEmpty() },
            paid = bool(o, "paid") ?: false,
            publishedAt = lng(o, "published_at"),
            expiresAt = expiresAt,
            segments = segments,
            a11y = str(o, "a11y"),
            openTarget = str(open, "target"),
            openId = str(open, "id"),
            q = question(obj(o, "q")),
        )
    }

    private fun chart(o: JSONObject?): Chart? {
        o ?: return null
        val kind = str(o, "kind") ?: return null
        val raw = arr(o, "points") ?: return null
        val points = ArrayList<Double>()
        for (i in 0 until raw.length()) {
            val n = raw.opt(i) as? Number ?: return null
            points.add(n.toDouble())
        }
        return Chart(kind, points, (o.opt("baseline") as? Number)?.toDouble())
    }

    /**
     * Decodifica el bloque `v2` de un snapshot completo. `null` = no hay `v2`
     * (o no es un objeto) -> modo legado. Un ítem roto se descarta solo.
     */
    fun parse(snapshot: JSONObject?): Block? {
        val v2 = obj(snapshot, "v2") ?: return null
        return try {
            val feedJson = arr(v2, "feed")
            val feed = ArrayList<Item>()
            if (feedJson != null) {
                for (i in 0 until feedJson.length()) {
                    val o = feedJson.opt(i) as? JSONObject ?: continue
                    val parsed = try { item(i, o) } catch (e: Exception) { null }
                    if (parsed != null) feed.add(parsed)
                }
            }
            val qs = obj(v2, "questions")
            val largeJson = arr(qs, "large")
            val large = ArrayList<Question>()
            if (largeJson != null) {
                for (i in 0 until largeJson.length()) {
                    question(largeJson.opt(i) as? JSONObject)?.let { large.add(it) }
                }
            }
            Block(
                positionsHidden = bool(v2, "positions_hidden") ?: false,
                mood = str(v2, "mood") ?: "neutral",
                planUntil = lng(v2, "plan_until"),
                chart = chart(obj(v2, "chart")),
                feedRev = str(v2, "feed_rev"),
                feed = feed,
                fallback = question(obj(qs, "fallback")),
                large = large,
                labels = obj(v2, "labels") ?: JSONObject(),
            )
        } catch (e: Exception) {
            null
        }
    }

    fun parseCursor(raw: String?): Cursor? {
        raw ?: return null
        return try {
            val o = JSONObject(raw)
            Cursor(str(o, "rev") ?: return null, int(o, "index") ?: return null, lng(o, "at") ?: 0L)
        } catch (e: Exception) {
            null
        }
    }

    // --- Selector (§3.5) -------------------------------------------------

    /** Último segmento con `from <= now` (si ninguno, el primero). */
    fun seg(item: Item, now: Long): Segment {
        var current: Segment? = null
        for (s in item.segments) if (s.from <= now) current = s
        return current ?: item.segments[0]
    }

    fun prio(item: Item, now: Long): Int = seg(item, now).prio

    /** Ítems vigentes, ordenados de forma estable por prioridad del segmento. */
    fun live(block: Block, now: Long): List<Item> {
        val planOver = block.planUntil?.let { now >= it } ?: false
        val alive = block.feed.filter { it.segments.isNotEmpty() && now < it.expiresAt && !(planOver && it.paid) }
        // sortedBy es estable: dentro de cada prioridad queda el orden de Dart.
        return alive.sortedBy { prio(it, now) }
    }

    /** Cantidad de vigentes con prio <= 2 (encabezado del grande y `hidden_count`). */
    fun nearCount(live: List<Item>, now: Long): Int = live.count { prio(it, now) <= 2 }

    fun small(block: Block, now: Long): SmallLine {
        val near = live(block, now).filter { prio(it, now) <= 2 }
        val hasChart = block.chart?.isDrawable == true
        if (block.positionsHidden) {
            if (near.isNotEmpty()) return SmallLine.HiddenCount(near.size)
            return if (hasChart) SmallLine.ChartLine else SmallLine.NoNews
        }
        if (near.isNotEmpty()) return SmallLine.ItemLine(near.first())
        return if (hasChart) SmallLine.ChartLine else SmallLine.NoNews
    }

    /** Índice actual del mediano: el del cursor si es del mismo feed, si no 0. */
    fun currentIndex(block: Block, liveCount: Int, cursor: Cursor?): Int {
        val rev = block.feedRev
        if (liveCount <= 0 || cursor == null || rev == null || cursor.rev != rev) return 0
        return ((cursor.index % liveCount) + liveCount) % liveCount
    }

    fun medium(block: Block, now: Long, cursor: Cursor?): MediumPick {
        val live = live(block, now)
        if (block.positionsHidden) {
            val n = nearCount(live, now)
            return MediumPick(null, if (n > 0) n else null, block.fallback, false, 0)
        }
        if (live.isEmpty()) return MediumPick(null, null, block.fallback, false, 0)
        val index = currentIndex(block, live.size, cursor)
        val item = live[index]
        return MediumPick(item, null, item.q ?: block.fallback, live.size >= 2, index)
    }

    fun large(block: Block, now: Long): LargePick {
        val live = live(block, now)
        val n = nearCount(live, now)
        if (block.positionsHidden) {
            return LargePick(n, emptyList(), if (n > 0) n else null, block.large)
        }
        val rows = ArrayList<Item>()
        val skipped = ArrayList<Item>()
        val perKind = HashMap<String, Int>()
        for (item in live) {
            if (rows.size == 3) break
            if ((perKind[item.kind] ?: 0) >= 2) {
                skipped.add(item)
            } else {
                rows.add(item)
                perKind[item.kind] = (perKind[item.kind] ?: 0) + 1
            }
        }
        for (item in skipped) {
            if (rows.size >= 3) break
            rows.add(item)
        }
        return LargePick(n, rows, null, block.large)
    }

    /** Cursor que deja "siguiente"; `null` si no hay nada que avanzar. */
    fun advance(block: Block, now: Long, cursor: Cursor?): Cursor? {
        val live = live(block, now)
        if (live.isEmpty() || block.positionsHidden) return null
        val i = currentIndex(block, live.size, cursor)
        return Cursor(block.feedRev ?: "", (i + 1) % live.size, now)
    }

    /** Horas futuras en que cambia lo que se dibuja: vencimientos, segmentos y fin del plan. */
    fun boundaries(block: Block, after: Long): List<Long> {
        val out = ArrayList<Long>()
        block.planUntil?.let { out.add(it) }
        for (item in block.feed) {
            out.add(item.expiresAt)
            for (s in item.segments) out.add(s.from)
        }
        return out.filter { it > after }
    }

    // --- "hace X" ---------------------------------------------------------

    /**
     * `< 1 min` ahora; `< 60 min` minutos; `< 24 h` horas; día calendario
     * anterior "ayer"; si no, días. [yesterday] lo decide el llamador (usa el
     * calendario del dispositivo) para que esto siga puro.
     */
    fun ageText(
        sinceMs: Long,
        nowMs: Long,
        label: (String) -> String?,
        isYesterday: (Long, Long) -> Boolean,
    ): String? {
        val minutes = maxOf(0L, (nowMs - sinceMs) / 60000L)
        fun fill(key: String, n: Long) = label(key)?.replace("{n}", n.toString())
        return when {
            minutes < 1 -> label("age_now")
            minutes < 60 -> fill("age_min", minutes)
            minutes < 60 * 24 -> fill("age_h", minutes / 60)
            isYesterday(sinceMs, nowMs) -> label("age_yesterday")
            else -> fill("age_d", maxOf(1L, minutes / (60 * 24)))
        }
    }
}
