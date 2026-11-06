package com.portfolioassistant.app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.portfolioassistant.app.MainActivity
import com.portfolioassistant.app.R
import com.portfolioassistant.app.widget.PortyFeedPicker.Block
import com.portfolioassistant.app.widget.PortyFeedPicker.Item
import com.portfolioassistant.app.widget.PortyFeedPicker.Question
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject
import java.util.Calendar

/**
 * Dibuja el snapshot JSON (docs/specs/home-widget-v2-tech.md §3). Visor tonto:
 * sin negocio, sin red. Elige qué fila va en cada tamaño con [PortyFeedPicker]
 * (mismas reglas que iOS), calcula "hace X" y compara la hora con `stale_at`.
 *
 * Sin bloque `v2` (JSON de la versión anterior) dibuja el modo legado: nunca
 * lee montos, ítems, teaser ni preguntas del JSON viejo (§3.1).
 */
enum class WidgetSize(val key: String) { SMALL("small"), MEDIUM("medium"), LARGE("large") }

object PortyWidgetRenderer {
    private const val KEY = "porty_widget_snapshot"
    private const val RENDER_LOG_KEY = "porty_widget_render_log"
    private const val CURSOR_KEY = "porty_widget_cursor"
    private const val REFRESH_MS = 15 * 60 * 1000L

    /** Acción del botón "siguiente novedad" del mediano (§3.5). */
    const val ACTION_NEXT_NOVELTY = "com.portfolioassistant.app.widget.ACTION_NEXT_NOVELTY"

    fun update(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        prefs: SharedPreferences,
        size: WidgetSize,
        provider: Class<*>,
    ) {
        val snap = load(prefs)
        val now = System.currentTimeMillis()
        val cursor = PortyFeedPicker.parseCursor(prefs.getString(CURSOR_KEY, null))
        for (id in ids) {
            manager.updateAppWidget(id, build(context, snap, size, now, cursor, id))
        }
        writeRenderLog(prefs, snap, size, now, cursor)
        scheduleNext(context, provider, ids, snap, now)
    }

    /**
     * "Siguiente" (§3.5): avanza el cursor del mediano, suma 1 a `next_taps` y
     * redibuja todos los medianos. Sin app ni red.
     */
    fun advanceAndUpdate(context: Context, prefs: SharedPreferences) {
        val snap = load(prefs)
        val block = PortyFeedPicker.parse(snap)
        val now = System.currentTimeMillis()
        if (block != null) {
            val cursor = PortyFeedPicker.parseCursor(prefs.getString(CURSOR_KEY, null))
            val next = PortyFeedPicker.advance(block, now, cursor)
            if (next != null) {
                prefs.edit().putString(CURSOR_KEY, next.toJson()).apply()
                bumpNextTaps(prefs)
            }
        }
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, PortyMediumWidgetProvider::class.java))
        if (ids.isNotEmpty()) {
            update(context, manager, ids, prefs, WidgetSize.MEDIUM, PortyMediumWidgetProvider::class.java)
        }
    }

    /** `null` = sin snapshot, JSON roto o `v` desconocido. */
    private fun load(prefs: SharedPreferences): JSONObject? = try {
        val raw = prefs.getString(KEY, null)
        val json = if (raw == null) null else JSONObject(raw)
        if (json != null && json.optInt("v", -1) == 1) json else null
    } catch (e: Exception) {
        null
    }

    private fun layoutOf(size: WidgetSize) = when (size) {
        WidgetSize.SMALL -> R.layout.porty_widget_small
        WidgetSize.MEDIUM -> R.layout.porty_widget_medium
        WidgetSize.LARGE -> R.layout.porty_widget_large
    }

    private fun isReady(snap: JSONObject?) =
        snap != null && snap.optString("state") == "ready" && snap.has("change_pct_text")

    private fun build(
        context: Context,
        snap: JSONObject?,
        widgetSize: WidgetSize,
        now: Long,
        cursor: PortyFeedPicker.Cursor?,
        appWidgetId: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, layoutOf(widgetSize))
        val size = widgetSize.key
        val dataAsOf = snap?.optLong("data_as_of", 0L) ?: 0L
        val ageMin = if (dataAsOf > 0) maxOf(0L, (now - dataAsOf) / 60000L) else null
        val age = ageMin?.let { "&age=$it" } ?: ""

        if (snap == null || !isReady(snap)) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            val message = snap?.optJSONObject("labels")?.optString("message", "")
                ?.takeIf { it.isNotEmpty() && snap.optString("state") != "ready" }
                ?: context.getString(R.string.widget_no_snapshot)
            views.setTextViewText(R.id.widget_empty_text, message)
            views.setContentDescription(R.id.widget_empty, message)
            val target = if (snap?.optString("state") == "no_portfolio") "add_portfolio" else "app"
            views.setOnClickPendingIntent(R.id.widget_root, launch(context, "target=$target&size=$size$age"))
            return views
        }
        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        val block = PortyFeedPicker.parse(snap)
        val labels = snap.optJSONObject("labels") ?: JSONObject()
        val stale = now >= snap.optLong("stale_at", Long.MAX_VALUE)
        val direction = snap.optString("direction")

        // Período, cara y % (el único número grande; nunca montos).
        val period = when {
            stale -> labels.optString("stale_date")
            snap.optString("period") == "last_close" -> labels.optString("period_last_close")
            else -> labels.optString("period_today")
        }
        views.setTextViewText(R.id.widget_period, period)
        val mood = when {
            stale -> "neutral"
            block != null -> block.mood
            direction == "up" -> "happy"
            direction == "down" -> "concerned"
            else -> "neutral"
        }
        views.setImageViewResource(R.id.widget_face, faceRes(context, mood))
        val colorRes = when (direction) {
            "up" -> R.color.porty_widget_profit
            "down" -> R.color.porty_widget_loss
            else -> R.color.porty_widget_secondary
        }
        val dirColor = withAlpha(context.getColor(colorRes), if (stale) 0x80 else 0xFF)
        views.setTextViewText(R.id.widget_pct, snap.optString("change_pct_text"))
        views.setTextColor(R.id.widget_pct, dirColor)

        val ageLine = ageLine(context, block, snap, dataAsOf, now)
        if (widgetSize != WidgetSize.SMALL) views.setTextViewText(R.id.widget_updated, ageLine ?: "")

        // Un solo elemento para TalkBack; nunca lee montos.
        views.setContentDescription(
            R.id.widget_value_block,
            listOf(snap.optString("a11y_value"), period, if (widgetSize == WidgetSize.SMALL) "" else ageLine ?: "")
                .filter { it.isNotEmpty() }.joinToString(". "),
        )

        // Toque por defecto: la Home (el chico lo pisa con el ítem de su línea).
        views.setOnClickPendingIntent(R.id.widget_root, launch(context, "target=home&size=$size$age"))

        if (block == null) {
            bindLegacy(context, views, widgetSize)
            return views
        }
        val chart = block.chart?.takeIf { it.isDrawable }
        when (widgetSize) {
            WidgetSize.SMALL -> bindSmall(context, views, block, now, age, dirColor)
            WidgetSize.MEDIUM -> bindMedium(context, views, block, now, cursor, age, dirColor, appWidgetId)
            WidgetSize.LARGE -> bindLarge(context, views, block, now, age, dirColor)
        }
        // Gráfico del día (mediano/grande; el chico lo dibuja en su línea).
        if (widgetSize != WidgetSize.SMALL) {
            bindChart(context, views, R.id.widget_chart, chart, widgetSize, dirColor, block)
        }
        return views
    }

    // --- Modo legado (§3.1) -----------------------------------------------

    private fun bindLegacy(context: Context, views: RemoteViews, size: WidgetSize) {
        val note = context.getString(R.string.widget_legacy_open_porty)
        when (size) {
            WidgetSize.SMALL -> {
                views.setViewVisibility(R.id.widget_line, View.VISIBLE)
                views.setViewVisibility(R.id.widget_line_icon, View.GONE)
                views.setViewVisibility(R.id.widget_chart, View.GONE)
                views.setTextViewText(R.id.widget_line_text, note)
            }
            WidgetSize.MEDIUM -> {
                showRight(views, hiddenText = note)
                views.setViewVisibility(R.id.widget_chart, View.GONE)
                views.setViewVisibility(R.id.widget_next, View.GONE)
                views.setViewVisibility(R.id.widget_q1, View.GONE)
            }
            WidgetSize.LARGE -> {
                views.setTextViewText(R.id.widget_header, context.getString(R.string.widget_legacy_your_portfolio))
                views.setViewVisibility(R.id.widget_chart, View.GONE)
                views.setViewVisibility(R.id.widget_list_title, View.GONE)
                for (r in LARGE_ROWS) views.setViewVisibility(r.row, View.GONE)
                views.setViewVisibility(R.id.widget_hidden_text, View.VISIBLE)
                views.setTextViewText(R.id.widget_hidden_text, note)
                views.setViewVisibility(R.id.widget_q1, View.GONE)
                views.setViewVisibility(R.id.widget_q2, View.GONE)
            }
        }
    }

    /** "tu cartera · hace X". Legado: textos propios del sistema. */
    private fun ageLine(context: Context, block: Block?, snap: JSONObject, dataAsOf: Long, now: Long): String? {
        if (dataAsOf <= 0) return null
        if (block != null) {
            val age = PortyFeedPicker.ageText(dataAsOf, now, { block.label(it) }, { s, n -> wasYesterday(s, n) })
            return listOfNotNull(block.label("your_portfolio"), age).filter { it.isNotEmpty() }
                .joinToString(" · ").ifEmpty { null }
        }
        val minutes = maxOf(0L, (now - dataAsOf) / 60000L)
        val age = when {
            minutes < 1 -> context.getString(R.string.widget_legacy_age_now)
            minutes < 60 -> context.getString(R.string.widget_legacy_age_min).replace("{n}", minutes.toString())
            minutes < 60 * 24 -> context.getString(R.string.widget_legacy_age_h).replace("{n}", (minutes / 60).toString())
            else -> context.getString(R.string.widget_legacy_age_d).replace("{n}", (minutes / (60 * 24)).toString())
        }
        return context.getString(R.string.widget_legacy_your_portfolio) + " · " + age
    }

    private fun wasYesterday(sinceMs: Long, nowMs: Long): Boolean {
        val y = Calendar.getInstance().apply { timeInMillis = nowMs; add(Calendar.DAY_OF_YEAR, -1) }
        val t = Calendar.getInstance().apply { timeInMillis = sinceMs }
        return y.get(Calendar.YEAR) == t.get(Calendar.YEAR) && y.get(Calendar.DAY_OF_YEAR) == t.get(Calendar.DAY_OF_YEAR)
    }

    // --- Chico ------------------------------------------------------------

    private fun bindSmall(context: Context, views: RemoteViews, block: Block, now: Long, age: String, dirColor: Int) {
        views.setViewVisibility(R.id.widget_line, View.VISIBLE)
        views.setViewVisibility(R.id.widget_line_icon, View.VISIBLE)
        views.setViewVisibility(R.id.widget_chart, View.GONE)
        views.setViewVisibility(R.id.widget_line_text, View.VISIBLE)
        val line = PortyFeedPicker.small(block, now)
        when (line) {
            is PortyFeedPicker.SmallLine.ItemLine -> {
                val item = line.item
                val seg = PortyFeedPicker.seg(item, now)
                val text = resolveAge(seg.short ?: seg.title ?: "", item, block, now)
                views.setImageViewResource(R.id.widget_line_icon, iconRes(item.icon, item.kind))
                views.setTextViewText(R.id.widget_line_text, text)
                views.setContentDescription(R.id.widget_line, resolveAge(item.a11y ?: text, item, block, now))
                views.setOnClickPendingIntent(
                    R.id.widget_root, launch(context, itemQuery(item, now, "small", 1, age)),
                )
            }
            is PortyFeedPicker.SmallLine.ChartLine -> {
                views.setImageViewResource(R.id.widget_line_icon, R.drawable.ic_widget_chart)
                views.setViewVisibility(R.id.widget_line_text, View.GONE)
                bindChart(context, views, R.id.widget_chart, block.chart, WidgetSize.SMALL, dirColor, block)
            }
            is PortyFeedPicker.SmallLine.HiddenCount -> {
                views.setImageViewResource(R.id.widget_line_icon, R.drawable.ic_widget_news)
                views.setTextViewText(R.id.widget_line_text, hiddenCountText(block, line.n))
            }
            is PortyFeedPicker.SmallLine.NoNews -> {
                views.setViewVisibility(R.id.widget_line_icon, View.GONE)
                views.setTextViewText(R.id.widget_line_text, block.label("no_news") ?: "")
            }
        }
    }

    // --- Mediano ----------------------------------------------------------

    private fun bindMedium(
        context: Context,
        views: RemoteViews,
        block: Block,
        now: Long,
        cursor: PortyFeedPicker.Cursor?,
        age: String,
        dirColor: Int,
        appWidgetId: Int,
    ) {
        val pick = PortyFeedPicker.medium(block, now, cursor)
        val item = pick.item
        if (item != null) {
            val seg = PortyFeedPicker.seg(item, now)
            showRight(views, hiddenText = null)
            bindItemHead(views, R.id.widget_item_icon, R.id.widget_tag, R.id.widget_item_meta, item, resolveAge(seg.meta, item, block, now))
            views.setTextViewText(R.id.widget_item_text, resolveAge(seg.title ?: "", item, block, now))
            val url = launch(context, itemQuery(item, now, "medium", 1, age))
            views.setOnClickPendingIntent(R.id.widget_item_head, url)
            views.setOnClickPendingIntent(R.id.widget_item_text, url)
            views.setContentDescription(R.id.widget_item, resolveAge(item.a11y ?: seg.title ?: "", item, block, now))
        } else {
            val text = pick.hiddenCount?.let { hiddenCountText(block, it) } ?: (block.label("no_news") ?: "")
            showRight(views, hiddenText = text)
        }
        // Botón "siguiente": solo con >= 2 novedades y posiciones visibles.
        if (pick.showNext) {
            views.setViewVisibility(R.id.widget_next, View.VISIBLE)
            views.setContentDescription(R.id.widget_next, block.label("next_a11y") ?: block.label("next") ?: "")
            views.setOnClickPendingIntent(R.id.widget_next, nextIntent(context, appWidgetId))
        } else {
            views.setViewVisibility(R.id.widget_next, View.GONE)
        }
        bindQuestion(context, views, R.id.widget_q1, pick.question, "medium", age)
    }

    /** Derecha del mediano: o el ítem (cabecera + título) o un texto suelto. */
    private fun showRight(views: RemoteViews, hiddenText: String?) {
        val showItem = hiddenText == null
        views.setViewVisibility(R.id.widget_item, if (showItem) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.widget_hidden_text, if (showItem) View.GONE else View.VISIBLE)
        if (hiddenText != null) views.setTextViewText(R.id.widget_hidden_text, hiddenText)
    }

    // --- Grande -----------------------------------------------------------

    private class LargeRow(val row: Int, val icon: Int, val tag: Int, val title: Int, val meta: Int)

    private val LARGE_ROWS = listOf(
        LargeRow(R.id.widget_row_1, R.id.widget_row_1_icon, R.id.widget_row_1_tag, R.id.widget_row_1_title, R.id.widget_row_1_meta),
        LargeRow(R.id.widget_row_2, R.id.widget_row_2_icon, R.id.widget_row_2_tag, R.id.widget_row_2_title, R.id.widget_row_2_meta),
        LargeRow(R.id.widget_row_3, R.id.widget_row_3_icon, R.id.widget_row_3_tag, R.id.widget_row_3_title, R.id.widget_row_3_meta),
    )

    private fun bindLarge(context: Context, views: RemoteViews, block: Block, now: Long, age: String, dirColor: Int) {
        val pick = PortyFeedPicker.large(block, now)
        val n = pick.headerN
        val header = when (n) {
            0 -> block.label("header_none")
            1 -> block.label("header_one")
            else -> block.label("header_other")?.replace("{n}", n.toString())
        } ?: ""
        views.setTextViewText(R.id.widget_header, header)

        val hiddenText = if (block.positionsHidden || pick.rows.isEmpty()) {
            pick.hiddenCount?.let { hiddenCountText(block, it) } ?: (block.label("no_news") ?: "")
        } else null
        views.setViewVisibility(R.id.widget_list_title, if (hiddenText == null) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_list_title, block.label("list_title") ?: "")
        views.setViewVisibility(R.id.widget_hidden_text, if (hiddenText == null) View.GONE else View.VISIBLE)
        if (hiddenText != null) views.setTextViewText(R.id.widget_hidden_text, hiddenText)

        for ((i, r) in LARGE_ROWS.withIndex()) {
            val item = if (hiddenText == null) pick.rows.getOrNull(i) else null
            if (item == null) {
                views.setViewVisibility(r.row, View.GONE)
                continue
            }
            val seg = PortyFeedPicker.seg(item, now)
            views.setViewVisibility(r.row, View.VISIBLE)
            bindItemHead(views, r.icon, r.tag, r.meta, item, resolveAge(seg.meta, item, block, now))
            views.setTextViewText(r.title, resolveAge(seg.title ?: "", item, block, now))
            views.setContentDescription(r.row, resolveAge(item.a11y ?: seg.title ?: "", item, block, now))
            views.setOnClickPendingIntent(r.row, launch(context, itemQuery(item, now, "large", i + 1, age)))
        }
        bindQuestion(context, views, R.id.widget_q1, pick.questions.getOrNull(0), "large", age)
        bindQuestion(context, views, R.id.widget_q2, pick.questions.getOrNull(1), "large", age)
    }

    // --- Piezas compartidas -----------------------------------------------

    /** Ícono + etiqueta de ticker (fondo inset) + meta. */
    private fun bindItemHead(views: RemoteViews, iconId: Int, tagId: Int, metaId: Int, item: Item, meta: String?) {
        views.setImageViewResource(iconId, iconRes(item.icon, item.kind))
        if (item.tag == null) {
            views.setViewVisibility(tagId, View.GONE)
        } else {
            views.setViewVisibility(tagId, View.VISIBLE)
            views.setTextViewText(tagId, item.tag)
        }
        if (meta.isNullOrEmpty()) {
            views.setViewVisibility(metaId, View.GONE)
        } else {
            views.setViewVisibility(metaId, View.VISIBLE)
            views.setTextViewText(metaId, meta)
        }
    }

    private fun bindQuestion(context: Context, views: RemoteViews, slot: Int, q: Question?, size: String, age: String) {
        if (q == null) {
            views.setViewVisibility(slot, View.GONE)
            return
        }
        views.setViewVisibility(slot, View.VISIBLE)
        views.setTextViewText(slot, q.text)
        views.setOnClickPendingIntent(
            slot,
            launch(context, "target=question&q=${safe(q.t)}&ref=${safe(q.ref)}&src=${safe(q.src)}&size=$size$age"),
        )
    }

    private fun bindChart(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        chart: PortyFeedPicker.Chart?,
        size: WidgetSize,
        color: Int,
        block: Block,
    ) {
        val drawable = chart?.takeIf { it.isDrawable }
        if (drawable == null) {
            views.setViewVisibility(viewId, View.GONE)
            return
        }
        val bitmap = PortyChartBitmap.render(
            drawable, size, color, context.getColor(R.color.porty_widget_secondary),
        )
        views.setImageViewBitmap(viewId, bitmap)
        views.setViewVisibility(viewId, View.VISIBLE)
        views.setContentDescription(
            viewId,
            block.label(if (drawable.kind == "days") "chart_a11y_days" else "chart_a11y_intraday") ?: "",
        )
    }

    private fun hiddenCountText(block: Block, n: Int): String =
        (if (n == 1) block.label("hidden_count_one") else block.label("hidden_count_other"))
            ?.replace("{n}", n.toString()) ?: ""

    /** Reemplaza `{age}` desde `published_at` con `labels.age_*` (vacío si no hay dato). */
    private fun resolveAge(text: String?, item: Item, block: Block, now: Long): String {
        if (text == null) return ""
        if (!text.contains("{age}")) return text
        val published = item.publishedAt
        val age = if (published == null) "" else
            PortyFeedPicker.ageText(published, now, { block.label(it) }, { s, n -> wasYesterday(s, n) }) ?: ""
        return text.replace("{age}", age)
    }

    private fun iconRes(icon: String?, kind: String): Int = when (icon ?: kind) {
        "calendar", "earnings" -> R.drawable.ic_widget_calendar
        "pie", "insight", "biggest" -> R.drawable.ic_widget_pie
        "chart", "mover" -> R.drawable.ic_widget_chart
        else -> R.drawable.ic_widget_news
    }

    /**
     * Cara por `mood`. Las caras contenta/preocupada las exporta el tool de Dart
     * (`porty_widget_avatar_{happy,concerned}`): si todavía no están en el
     * proyecto se usa el avatar actual. Se busca por nombre para que compile
     * con o sin los PNG (los mantiene `res/values/widget_keep.xml`).
     */
    private fun faceRes(context: Context, mood: String): Int {
        val fallback = R.drawable.porty_widget_avatar
        if (mood != "happy" && mood != "concerned") return fallback
        val id = context.resources.getIdentifier("porty_widget_avatar_$mood", "drawable", context.packageName)
        return if (id != 0) id else fallback
    }

    // --- URLs (§3.4) ------------------------------------------------------

    /** Solo caracteres de un id/plantilla: la URL nunca lleva texto libre. */
    private fun safe(s: String) = s.filter { it.code < 128 && (it.isLetterOrDigit() || it == '_') }

    /** Misma regla que `itemURL` de iOS. */
    private fun itemQuery(item: Item, now: Long, size: String, rank: Int, age: String): String {
        var target = item.openTarget ?: "home"
        if (target !in setOf("news", "earnings", "teaser_news", "teaser_earnings", "home")) target = "home"
        val parts = ArrayList<String>()
        if (target == "news" || target == "earnings") {
            val id = item.openId ?: item.id
            if (id != null) {
                parts.add("id=${safe(id)}")
                parts.add("rank=${rank.coerceIn(1, 3)}")
            } else {
                target = "home"
            }
        }
        if (item.kind != "teaser") {
            parts.add("kind=${safe(item.kind)}")
            parts.add("prio=${PortyFeedPicker.prio(item, now)}")
        }
        val extra = if (parts.isEmpty()) "" else "&" + parts.joinToString("&")
        return "target=$target&size=$size$extra$age"
    }

    private fun launch(context: Context, query: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("porty-widget://open?homeWidget&$query"),
        )

    /** Broadcast explícito al receiver del mediano; un request code por widget. */
    private fun nextIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, PortyMediumWidgetProvider::class.java).apply {
            action = ACTION_NEXT_NOVELTY
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, appWidgetId, intent, flags)
    }

    private fun withAlpha(color: Int, alpha: Int) = (color and 0x00FFFFFF) or (alpha shl 24)

    // --- Render log (§3.3) ------------------------------------------------

    private fun readLog(prefs: SharedPreferences): JSONObject = try {
        JSONObject(prefs.getString(RENDER_LOG_KEY, null) ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    private fun bumpNextTaps(prefs: SharedPreferences) {
        try {
            val log = readLog(prefs)
            val medium = log.optJSONObject("medium") ?: JSONObject()
            medium.put("next_taps", medium.optInt("next_taps", 0) + 1)
            log.put("medium", medium)
            prefs.edit().putString(RENDER_LOG_KEY, log.toString()).apply()
        } catch (e: Exception) {
            // El log es una aproximación: nunca debe romper el botón.
        }
    }

    /** Lo único que escribe el widget: tipos y conteos por tamaño, nunca ids, tickers ni textos. */
    private fun writeRenderLog(
        prefs: SharedPreferences,
        snap: JSONObject?,
        size: WidgetSize,
        now: Long,
        cursor: PortyFeedPicker.Cursor?,
    ) {
        if (!isReady(snap)) return
        val block = PortyFeedPicker.parse(snap) ?: return
        try {
            val live = PortyFeedPicker.live(block, now)
            val entry = JSONObject().put("at", now).put("live", live.size)
            var shown: List<Item> = emptyList()
            when (size) {
                WidgetSize.SMALL -> entry.put(
                    "line",
                    when (val l = PortyFeedPicker.small(block, now)) {
                        is PortyFeedPicker.SmallLine.ItemLine ->
                            if (l.item.kind == "news" || l.item.kind == "earnings") "dated" else "insight"
                        is PortyFeedPicker.SmallLine.ChartLine -> "chart"
                        is PortyFeedPicker.SmallLine.HiddenCount -> "hidden_count"
                        is PortyFeedPicker.SmallLine.NoNews -> "none"
                    },
                )
                WidgetSize.MEDIUM -> {
                    val item = PortyFeedPicker.medium(block, now, cursor).item
                    if (item != null) {
                        shown = listOf(item)
                        entry.put("shown_kind", item.kind).put("shown_prio", PortyFeedPicker.prio(item, now))
                    }
                }
                WidgetSize.LARGE -> shown = PortyFeedPicker.large(block, now).rows
            }
            if (size != WidgetSize.SMALL) {
                val kinds = JSONObject()
                for (k in listOf("news", "earnings", "insight", "mover", "biggest", "teaser")) {
                    kinds.put(k, shown.count { it.kind == k })
                }
                entry.put("kinds", kinds)
                // Campos de la ampliación, que la app sigue leyendo.
                entry.put("news", shown.count { it.kind == "news" })
                entry.put("earnings", shown.count { it.kind == "earnings" })
                val teaser = shown.firstOrNull { it.kind == "teaser" }
                entry.put(
                    "teaser",
                    if (teaser == null) "none" else if (teaser.openTarget == "teaser_earnings") "earnings" else "news",
                )
            }
            val log = readLog(prefs)
            if (size == WidgetSize.MEDIUM) {
                entry.put("next_taps", log.optJSONObject("medium")?.optInt("next_taps", 0) ?: 0)
            }
            log.put(size.key, entry)
            prefs.edit().putString(RENDER_LOG_KEY, log.toString()).apply()
        } catch (e: Exception) {
            // El log es una aproximación: nunca debe romper el dibujo.
        }
    }

    // --- Alarma -----------------------------------------------------------

    /**
     * Sin red ni WorkManager que lo redibuje, "hace X", los vencimientos y
     * "datos viejos" necesitan un empujón: una alarma inexacta (sin permiso
     * especial) cada 15 min o en el próximo límite del feed (`expires_at`,
     * `segments[].from`, `plan_until`) o `stale_at`, lo que llegue primero.
     */
    private fun scheduleNext(
        context: Context,
        provider: Class<*>,
        ids: IntArray,
        snap: JSONObject?,
        now: Long,
    ) {
        if (snap == null || snap.optString("state") != "ready") {
            cancelNext(context, provider)
            return
        }
        var at = now + REFRESH_MS
        fun consider(t: Long) { if (t > now && t < at) at = t }
        consider(snap.optLong("stale_at", 0L))
        PortyFeedPicker.parse(snap)?.let { b -> PortyFeedPicker.boundaries(b, now).forEach { consider(it) } }
        at = maxOf(at, now + 1000L)
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.set(AlarmManager.RTC, at, updateIntent(context, provider, ids))
    }

    fun cancelNext(context: Context, provider: Class<*>) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(updateIntent(context, provider, null))
    }

    private fun updateIntent(context: Context, provider: Class<*>, ids: IntArray?): PendingIntent {
        val all = ids ?: AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, provider))
        val intent = Intent(context, provider).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, all)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, provider.name.hashCode(), intent, flags)
    }
}
