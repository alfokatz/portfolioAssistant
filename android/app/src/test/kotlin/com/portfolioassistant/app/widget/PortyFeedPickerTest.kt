package com.portfolioassistant.app.widget

import com.portfolioassistant.app.widget.PortyFeedPicker.SmallLine
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Cubre `PortyFeedPicker` (docs/specs/home-widget-v2-tech.md §3.5, §7.2): el
 * ejemplo de §3.2, los casos compartidos de `test/fixtures/home_widget/v2/feed_cases.json`
 * (los mismos que corren Dart y Swift) y el modo legado.
 * Correr: `cd android && ./gradlew :app:testDevelopmentDebugUnitTest --tests '*PortyFeedPickerTest*'`
 */
class PortyFeedPickerTest {

    private val t0 = 1794067200000L
    private val t1 = 1794106800000L

    /** Ejemplo de §3.2 (feed de 4 ítems), con `plan_until` y `feed_rev`. */
    private fun example(hidden: Boolean = false): JSONObject = JSONObject(
        """
        {"v":1,"state":"ready","change_pct_text":"+1,2 %","stale_at":$t1,"direction":"up",
         "v2":{"positions_hidden":$hidden,"mood":"happy","plan_until":1794500000000,
          "chart":{"kind":"intraday","points":[0.1,0.5,1.0],"baseline":0.2},
          "feed_rev":"5be0a1c9",
          "feed":[
           {"id":"51c0e7d2","kind":"earnings","icon":"calendar","tag":"AAPL","paid":true,"expires_at":1794193199000,
            "segments":[{"from":$t0,"prio":1,"short":"AAPL · resultados mañana (estimado)","title":"t","meta":"m"},
                        {"from":$t1,"prio":1,"short":"AAPL · resultados hoy (estimado)","title":"t","meta":"m"}],
            "open":{"target":"earnings","id":"51c0e7d2"},
            "q":{"ref":"0c9d2e11","t":"earnings_last","src":"novelty","text":"¿Qué presentó AAPL la última vez?"}},
           {"id":"9f2c41ab","kind":"news","icon":"news","tag":"NVDA","paid":true,"published_at":1794060000000,"expires_at":1794232800000,
            "segments":[{"from":$t0,"prio":1,"short":"NVDA · noticia de hoy","title":"Nvidia","meta":"Noticia · {age}"},
                        {"from":$t1,"prio":3,"short":"NVDA · noticia de ayer","title":"Nvidia","meta":"Noticia · {age}"}],
            "open":{"target":"news","id":"9f2c41ab"},
            "q":{"ref":"7a1f0b33","t":"news_what","src":"novelty","text":"¿Qué pasó con NVDA?"}},
           {"id":"e40d7a19","kind":"insight","icon":"pie","expires_at":1794153600000,
            "segments":[{"from":$t0,"prio":2,"short":"Viaje a Japón viene atrasada","title":"x","meta":"Porty te marca"}],
            "open":{"target":"home"},
            "q":{"ref":"c21e9a04","t":"goal_progress","src":"novelty","text":"¿Cómo voy con Viaje a Japón?"}},
           {"id":"3b77c0de","kind":"mover","icon":"chart","tag":"MELI","expires_at":$t1,
            "segments":[{"from":$t0,"prio":3,"short":"MELI +4,1 % hoy","title":"MELI +4,1 % hoy","meta":"Lo que más se movió hoy"}],
            "open":{"target":"home"}}
          ],
          "questions":{"fallback":{"ref":"b0d4c3e2","t":"biggest","src":"biggest","text":"¿Qué tanto depende mi cartera de NVDA?"},
                       "large":[{"ref":"0c9d2e11","t":"earnings_last","src":"novelty","text":"a"},
                                {"ref":"c21e9a04","t":"goal_progress","src":"goal","text":"b"}]},
          "labels":{"age_now":"recién","age_min":"hace {n} min","age_h":"hace {n} h","age_yesterday":"ayer","age_d":"hace {n} d"}}}
        """.trimIndent(),
    )

    private fun block(snap: JSONObject) = PortyFeedPicker.parse(snap)!!

    private fun ids(items: List<PortyFeedPicker.Item>) = items.map { it.id }

    @Test
    fun `live keeps Dart order inside each priority and drops expired items`() {
        val b = block(example())
        assertEquals(listOf("51c0e7d2", "9f2c41ab", "e40d7a19", "3b77c0de"), ids(PortyFeedPicker.live(b, t0)))
        // Pasado t1: la noticia baja a prio 3 (queda tras el insight) y el mover venció (now == expires_at).
        assertEquals(listOf("51c0e7d2", "e40d7a19", "9f2c41ab"), ids(PortyFeedPicker.live(b, t1)))
    }

    @Test
    fun `plan_until removes paid items`() {
        val snap = example()
        snap.getJSONObject("v2").put("plan_until", t0 + 1)
        val b = block(snap)
        assertEquals(listOf("51c0e7d2", "9f2c41ab", "e40d7a19", "3b77c0de"), ids(PortyFeedPicker.live(b, t0)))
        assertEquals(listOf("e40d7a19", "3b77c0de"), ids(PortyFeedPicker.live(b, t0 + 1)))
    }

    @Test
    fun `small shows first item with prio le 2, else chart, else no news`() {
        val b = block(example())
        val line = PortyFeedPicker.small(b, t0) as SmallLine.ItemLine
        assertEquals("51c0e7d2", line.item.id)
        // Con todo vencido salvo prio 3 -> gráfico.
        assertTrue(PortyFeedPicker.small(b, 1794200000000L) is SmallLine.ChartLine)
        val noChart = example()
        noChart.getJSONObject("v2").put("chart", JSONObject.NULL)
        assertTrue(PortyFeedPicker.small(block(noChart), 1794200000000L) is SmallLine.NoNews)
    }

    @Test
    fun `medium follows the cursor only when rev matches`() {
        val b = block(example())
        val same = PortyFeedPicker.Cursor("5be0a1c9", 2, t0)
        val other = PortyFeedPicker.Cursor("deadbeef", 2, t0)
        assertEquals("e40d7a19", PortyFeedPicker.medium(b, t0, same).item!!.id)
        assertEquals("51c0e7d2", PortyFeedPicker.medium(b, t0, other).item!!.id)
        assertEquals("51c0e7d2", PortyFeedPicker.medium(b, t0, null).item!!.id)
        val pick = PortyFeedPicker.medium(b, t0, null)
        assertEquals("0c9d2e11", pick.question!!.ref)
        assertTrue(pick.showNext)
        // Un ítem sin q cae al fallback.
        val mover = PortyFeedPicker.medium(b, t0, PortyFeedPicker.Cursor("5be0a1c9", 3, t0))
        assertEquals("b0d4c3e2", mover.question!!.ref)
    }

    @Test
    fun `medium without live items shows fallback and no next button`() {
        val pick = PortyFeedPicker.medium(block(example()), 1794600000000L, null)
        assertNull(pick.item)
        assertFalse(pick.showNext)
        assertEquals("b0d4c3e2", pick.question!!.ref)
    }

    @Test
    fun `advance cycles through live and wraps to the first`() {
        val b = block(example())
        var cursor: PortyFeedPicker.Cursor? = null
        val seen = ArrayList<Int>()
        repeat(5) {
            cursor = PortyFeedPicker.advance(b, t0, cursor)
            seen.add(cursor!!.index)
        }
        assertEquals(listOf(1, 2, 3, 0, 1), seen)
        assertEquals("5be0a1c9", cursor!!.rev)
    }

    @Test
    fun `advance resets when the feed changes and does nothing when hidden`() {
        val b = block(example())
        val stale = PortyFeedPicker.Cursor("old", 3, t0)
        assertEquals(1, PortyFeedPicker.advance(b, t0, stale)!!.index)
        assertNull(PortyFeedPicker.advance(block(example(hidden = true)), t0, null))
    }

    @Test
    fun `large takes 3 rows with at most 2 of the same kind then fills with skipped`() {
        val feed = JSONArray()
        fun add(id: String, kind: String) = feed.put(
            JSONObject("""{"id":"$id","kind":"$kind","expires_at":${t0 + 1000000},"segments":[{"from":0,"prio":1}]}"""),
        )
        add("n1", "news"); add("n2", "news"); add("n3", "news"); add("i1", "insight")
        val snap = example()
        snap.getJSONObject("v2").put("feed", feed)
        val rows = PortyFeedPicker.large(block(snap), t0).rows
        assertEquals(listOf("n1", "n2", "i1"), ids(rows))
        // Sin otro kind: completa con los salteados.
        val only = JSONArray()
        for (n in 1..4) only.put(JSONObject("""{"id":"n$n","kind":"news","expires_at":${t0 + 1000000},"segments":[{"from":0,"prio":1}]}"""))
        snap.getJSONObject("v2").put("feed", only)
        assertEquals(listOf("n1", "n2", "n3"), ids(PortyFeedPicker.large(block(snap), t0).rows))
    }

    @Test
    fun `header and hidden_count count live items with prio le 2`() {
        val b = block(example())
        assertEquals(3, PortyFeedPicker.large(b, t0).headerN)
        val hidden = block(example(hidden = true))
        assertEquals(3, PortyFeedPicker.large(hidden, t0).hiddenCount)
        assertEquals(3, (PortyFeedPicker.small(hidden, t0) as SmallLine.HiddenCount).n)
        assertEquals(3, PortyFeedPicker.medium(hidden, t0, null).hiddenCount)
        // Solo quedan prio 3: no_news.
        assertNull(PortyFeedPicker.medium(hidden, 1794200000000L, null).hiddenCount)
        assertFalse(PortyFeedPicker.medium(hidden, t0, null).showNext)
    }

    @Test
    fun `age text follows the spec buckets`() {
        val labels = mapOf(
            "age_now" to "recién", "age_min" to "hace {n} min", "age_h" to "hace {n} h",
            "age_yesterday" to "ayer", "age_d" to "hace {n} d",
        )
        fun age(minutes: Long, yesterday: Boolean = false) =
            PortyFeedPicker.ageText(0L, minutes * 60000L, { labels[it] }, { _, _ -> yesterday })
        assertEquals("recién", age(0))
        assertEquals("hace 59 min", age(59))
        assertEquals("hace 3 h", age(190))
        assertEquals("ayer", age(60 * 30, yesterday = true))
        assertEquals("hace 2 d", age(60 * 24 * 2 + 5))
    }

    @Test
    fun `boundaries lists future expirations segments and plan end`() {
        val list = PortyFeedPicker.boundaries(block(example()), t0)
        assertTrue(list.contains(t1))
        assertTrue(list.contains(1794500000000L))
        assertTrue(list.none { it <= t0 })
    }

    @Test
    fun `legacy json without v2 or with a broken v2 does not throw`() {
        val legacy = JSONObject("""{"v":1,"state":"ready","change_pct_text":"+1 %","total_text":"US${'$'}1.000","items":[{"ticker":"AAPL"}]}""")
        assertNull(PortyFeedPicker.parse(legacy))
        assertNull(PortyFeedPicker.parse(JSONObject("""{"v":1,"v2":"roto"}""")))
        // Ítems rotos se descartan sin tirar el resto.
        val broken = example()
        broken.getJSONObject("v2").getJSONArray("feed").put(JSONObject("""{"kind":"news"}""")).put("x")
        val b = block(broken)
        assertEquals(4, b.feed.size)
        // Campos con tipos raros no lanzan.
        val weird = JSONObject("""{"v2":{"feed":"nope","questions":3,"chart":{"kind":"days","points":["a"]},"mood":null}}""")
        val wb = block(weird)
        assertEquals("neutral", wb.mood)
        assertNull(wb.chart)
        assertTrue(PortyFeedPicker.small(wb, t0) is SmallLine.NoNews)
    }

    @Test
    fun `cursor round trips and rejects garbage`() {
        val c = PortyFeedPicker.Cursor("5be0a1c9", 2, 123L)
        val back = PortyFeedPicker.parseCursor(c.toJson())!!
        assertEquals("5be0a1c9", back.rev)
        assertEquals(2, back.index)
        assertNull(PortyFeedPicker.parseCursor("no json"))
        assertNull(PortyFeedPicker.parseCursor(null))
    }

    // --- Casos compartidos con Dart y Swift ------------------------------

    private fun cases(): JSONArray? {
        val file = listOf(
            File("../../test/fixtures/home_widget/v2/feed_cases.json"),
            File("test/fixtures/home_widget/v2/feed_cases.json"),
        ).firstOrNull { it.exists() } ?: return null
        val raw = file.readText()
        return if (raw.trimStart().startsWith("[")) JSONArray(raw) else JSONObject(raw).getJSONArray("cases")
    }

    private fun ref(q: PortyFeedPicker.Question?): Any = q?.ref ?: JSONObject.NULL

    @Test
    fun `matches shared feed_cases json`() {
        val all = cases()
        assumeTrue("feed_cases.json todavía no existe", all != null)
        assertNotNull(all)
        assertTrue(all!!.length() > 0)
        for (i in 0 until all.length()) {
            val c = all.getJSONObject(i)
            val name = c.optString("name", "case $i")
            val snap = c.getJSONObject("snapshot")
            val now = c.getLong("now")
            val cursor = if (c.isNull("cursor") || !c.has("cursor")) null
            else PortyFeedPicker.parseCursor(c.getJSONObject("cursor").toString())
            val exp = c.getJSONObject("expected")
            val b = block(snap)
            val live = PortyFeedPicker.live(b, now)

            assertEquals("$name stale", exp.getBoolean("stale"), now >= snap.optLong("stale_at", Long.MAX_VALUE))
            assertEquals("$name header_n", exp.getInt("header_n"), PortyFeedPicker.nearCount(live, now))

            val es = exp.getJSONObject("small")
            when (val l = PortyFeedPicker.small(b, now)) {
                is SmallLine.ItemLine -> {
                    assertEquals("$name small", "item", es.getString("line"))
                    assertEquals("$name small index", es.getInt("feed_index"), l.item.index)
                }
                is SmallLine.HiddenCount -> {
                    assertEquals("$name small", "hidden_count", es.getString("line"))
                    assertEquals("$name small n", es.getInt("n"), l.n)
                }
                is SmallLine.ChartLine -> assertEquals("$name small", "chart", es.getString("line"))
                is SmallLine.NoNews -> assertEquals("$name small", "no_news", es.getString("line"))
            }

            val em = exp.getJSONObject("medium")
            val m = PortyFeedPicker.medium(b, now, cursor)
            val mode = when {
                m.item != null -> "item"
                m.hiddenCount != null -> "hidden_count"
                else -> "no_news"
            }
            assertEquals("$name medium mode", em.getString("mode"), mode)
            assertEquals("$name medium question", em.opt("question") ?: JSONObject.NULL, ref(m.question))
            assertEquals("$name medium next", em.getBoolean("next_button"), m.showNext)
            if (mode == "item") assertEquals("$name medium index", em.getInt("feed_index"), m.item!!.index)
            if (mode == "hidden_count") assertEquals("$name medium n", em.getInt("n"), m.hiddenCount)

            val el = exp.getJSONObject("large")
            val l = PortyFeedPicker.large(b, now)
            val lmode = when {
                l.rows.isNotEmpty() -> "rows"
                l.hiddenCount != null -> "hidden_count"
                else -> "no_news"
            }
            assertEquals("$name large mode", el.getString("mode"), lmode)
            if (lmode == "rows") {
                val want = el.getJSONArray("rows")
                assertEquals("$name large rows", (0 until want.length()).map { want.getInt(it) }, l.rows.map { it.index })
            }
            if (lmode == "hidden_count") assertEquals("$name large n", el.getInt("n"), l.hiddenCount)
            val wantQ = el.getJSONArray("questions")
            assertEquals("$name large questions", (0 until wantQ.length()).map { wantQ.opt(it) ?: JSONObject.NULL }, l.questions.map { it.ref })

            val next = PortyFeedPicker.advance(b, now, cursor)
            if (exp.isNull("next_index")) assertNull("$name next", next)
            else assertEquals("$name next", exp.getInt("next_index"), next!!.index)
        }
    }

    @Test
    fun `shared v2 fixtures parse without throwing`() {
        val dir = listOf(File("../../test/fixtures/home_widget/v2"), File("test/fixtures/home_widget/v2"))
            .firstOrNull { it.isDirectory }
        assumeTrue("fixtures v2 no encontrados", dir != null)
        val files = dir!!.listFiles { f -> f.name.startsWith("ready_") && f.name.endsWith(".json") }!!
        assertTrue(files.isNotEmpty())
        for (f in files) {
            val b = PortyFeedPicker.parse(JSONObject(f.readText()))
            assertNotNull(f.name, b)
            val now = System.currentTimeMillis()
            PortyFeedPicker.small(b!!, now); PortyFeedPicker.medium(b, now, null); PortyFeedPicker.large(b, now)
        }
    }
}
