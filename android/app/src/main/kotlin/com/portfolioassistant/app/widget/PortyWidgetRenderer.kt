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
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject

/**
 * Dibuja el snapshot JSON (schema v1, docs/specs/home-widget-tech.md §3.2 y
 * Am.4.1). Visor tonto: sin negocio, sin red. Solo calcula "hace X", compara
 * la hora con `stale_at` y filtra por tiempo las novedades (Am.4.9).
 */
enum class WidgetSize(val key: String) { SMALL("small"), MEDIUM("medium"), LARGE("large") }

object PortyWidgetRenderer {
    private const val KEY = "porty_widget_snapshot"
    private const val RENDER_LOG_KEY = "porty_widget_render_log"
    private const val REFRESH_MS = 15 * 60 * 1000L

    /** Un ítem ya resuelto para la hora actual. */
    private class Item(
        val id: String,
        val kind: String,
        val rank: Int,
        val meta: String?,
        val text: String,
        val a11y: String,
    ) {
        val isEarnings get() = kind == "earnings"
    }

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
        for (id in ids) {
            manager.updateAppWidget(id, build(context, snap, size, now))
        }
        writeRenderLog(prefs, snap, size, now)
        scheduleNext(context, provider, ids, snap, now)
    }

    /** `null` = sin snapshot, JSON roto o `v` desconocido. */
    private fun load(prefs: SharedPreferences): JSONObject? = try {
        val raw = prefs.getString(KEY, null)
        val json = if (raw == null) null else JSONObject(raw)
        if (json != null && json.optInt("v", -1) == 1) json else null
    } catch (e: Exception) {
        null
    }

    private fun build(context: Context, snap: JSONObject?, widgetSize: WidgetSize, now: Long): RemoteViews {
        val medium = widgetSize == WidgetSize.MEDIUM
        val large = widgetSize == WidgetSize.LARGE
        val views = RemoteViews(
            context.packageName,
            when (widgetSize) {
                WidgetSize.SMALL -> R.layout.porty_widget_small
                WidgetSize.MEDIUM -> R.layout.porty_widget_medium
                WidgetSize.LARGE -> R.layout.porty_widget_large
            },
        )
        val size = widgetSize.key
        val dataAsOf = snap?.optLong("data_as_of", 0L) ?: 0L
        val ageMin = if (dataAsOf > 0) maxOf(0L, (now - dataAsOf) / 60000L) else null
        val age = ageMin?.let { "&age=$it" } ?: ""

        if (snap == null || snap.optString("state") != "ready" || !snap.has("change_pct_text")) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            val message = snap?.optJSONObject("labels")?.optString("message", "")
                ?.takeIf { it.isNotEmpty() && snap.optString("state") != "ready" }
                ?: context.getString(R.string.widget_no_snapshot)
            views.setTextViewText(R.id.widget_empty_text, message)
            views.setContentDescription(R.id.widget_empty, message)
            val target = if (snap?.optString("state") == "no_portfolio") "add_portfolio" else "app"
            views.setOnClickPendingIntent(
                R.id.widget_root, launch(context, "target=$target&size=$size$age"),
            )
            return views
        }
        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        val labels = snap.optJSONObject("labels") ?: JSONObject()
        val stale = now >= snap.optLong("stale_at", Long.MAX_VALUE)
        val hidden = snap.optBoolean("amounts_hidden", false)

        val period = when {
            stale -> labels.optString("stale_date")
            snap.optString("period") == "last_close" -> labels.optString("period_last_close")
            else -> labels.optString("period_today")
        }
        views.setTextViewText(R.id.widget_period, period)

        val total = if (hidden) labels.optString("hidden_amount", "••••") else snap.optString("total_text")
        views.setTextViewText(R.id.widget_total, total)
        views.setTextViewText(R.id.widget_change, if (hidden) "" else snap.optString("change_text"))
        views.setTextViewText(R.id.widget_pct, snap.optString("change_pct_text"))
        views.setViewVisibility(R.id.widget_change, if (hidden) View.GONE else View.VISIBLE)

        // Dirección → color (profit / loss / neutro). Datos viejos: atenuados.
        val colorRes = when (snap.optString("direction")) {
            "up" -> R.color.porty_widget_profit
            "down" -> R.color.porty_widget_loss
            else -> R.color.porty_widget_secondary
        }
        val dim = if (stale) 0x80 else 0xFF
        val change = withAlpha(context.getColor(colorRes), dim)
        views.setTextColor(R.id.widget_change, change)
        views.setTextColor(R.id.widget_pct, change)
        views.setTextColor(R.id.widget_total, withAlpha(context.getColor(R.color.porty_widget_primary), dim))

        val updated = updatedText(labels, ageMin)
        views.setTextViewText(R.id.widget_updated, updated ?: "")

        // Un solo elemento para TalkBack; con montos ocultos nunca lee números.
        val a11y = listOf(
            if (hidden) labels.optString("hidden_a11y") else snap.optString("a11y_value"),
            period,
            updated ?: "",
        ).filter { it.isNotEmpty() }.joinToString(". ")
        views.setContentDescription(R.id.widget_value_block, a11y)

        views.setOnClickPendingIntent(
            R.id.widget_root, launch(context, "target=chat&size=$size$age"),
        )

        val phrase = snap.optString(if (stale) "phrase_stale" else "phrase")
        if (medium) {
            views.setTextViewText(R.id.widget_phrase, phrase)
            bindMediumItem(context, views, snap, now, age)
            bindQuestions(context, views, snap, intArrayOf(R.id.widget_q1, R.id.widget_q2), "medium", age)
        } else if (large) {
            views.setTextViewText(R.id.widget_phrase, phrase)
            bindLarge(context, views, snap, now, age)
        }
        return views
    }

    private fun bindQuestions(
        context: Context,
        views: RemoteViews,
        snap: JSONObject,
        slots: IntArray,
        size: String,
        age: String,
    ) {
        val qs = snap.optJSONArray("questions")
        for ((i, slot) in slots.withIndex()) {
            val q = qs?.optJSONObject(i)
            if (q == null) {
                views.setViewVisibility(slot, View.GONE)
                continue
            }
            views.setViewVisibility(slot, View.VISIBLE)
            views.setTextViewText(slot, q.optString("text"))
            views.setOnClickPendingIntent(
                slot,
                launch(context, "target=question&q=${Uri.encode(q.optString("id"))}&size=$size$age"),
            )
        }
    }

    // --- Novedades (Am.4.1 / Am.4.9) -------------------------------------

    /** Plan vencido: se ocultan ítems y aviso. */
    private fun planExpired(snap: JSONObject, now: Long): Boolean {
        val until = snap.optLong("plan_until", 0L)
        return until > 0 && now >= until
    }

    private fun itemLabels(snap: JSONObject): JSONObject =
        snap.optJSONObject("items_labels") ?: JSONObject()

    /** Ítems vigentes (rank 1..4). */
    private fun resolveItems(snap: JSONObject, now: Long): List<Item> {
        if (planExpired(snap, now)) return emptyList()
        val labels = itemLabels(snap)
        val arr = snap.optJSONArray("items") ?: return emptyList()
        val out = ArrayList<Item>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (now >= o.optLong("expires_at", Long.MAX_VALUE)) continue
            val id = o.optString("id", "")
            val kind = o.optString("kind", "")
            if (id.isEmpty() || kind.isEmpty()) continue
            val rank = out.size + 1
            if (kind == "earnings") {
                val segs = o.optJSONArray("segments")
                var text: String? = null
                if (segs != null) {
                    for (j in 0 until segs.length()) {
                        val seg = segs.optJSONObject(j) ?: continue
                        if (text == null || seg.optLong("from", 0L) <= now) {
                            text = seg.optString("text", "").ifEmpty { text }
                        }
                    }
                }
                if (text.isNullOrEmpty()) continue
                out.add(Item(id, kind, rank, null, text, o.optString("a11y", "").ifEmpty { text }))
            } else {
                val headline = o.optString("headline", "")
                if (headline.isEmpty()) continue
                val ticker = o.optString("ticker", "")
                val source = o.optString("source", "")
                val age = ageText(labels, o, now)
                val meta = listOf(ticker, source, age ?: "").filter { it.isNotEmpty() }
                    .joinToString(" · ").ifEmpty { null }
                out.add(Item(id, kind, rank, meta, headline, newsA11y(labels, ticker, source, age, headline)))
            }
            if (out.size == 4) break
        }
        return out
    }

    /** "hace 25 min" / "hace 3 h" / "ayer" desde `published_at`. */
    private fun ageText(labels: JSONObject, item: JSONObject, now: Long): String? {
        val published = item.optLong("published_at", 0L)
        if (published <= 0) return null
        val minutes = maxOf(0L, (now - published) / 60000L)
        val (key, n) = when {
            minutes < 60 -> "age_min" to minutes
            minutes < 60 * 24 -> "age_h" to minutes / 60
            else -> "age_yesterday" to 0L
        }
        return labels.optString(key).takeIf { it.isNotEmpty() }?.replace("{n}", n.toString())
    }

    private fun newsA11y(labels: JSONObject, ticker: String, source: String, age: String?, headline: String): String {
        var template = labels.optString("a11y_news", "")
        if (template.isEmpty()) {
            return listOf(ticker, source, age ?: "", headline).filter { it.isNotEmpty() }.joinToString(". ")
        }
        // La plantilla dice "hace {age}"; la antigüedad ya trae "hace" o es "ayer".
        template = template.replace("hace {age}", "{age}")
        return template.replace("{ticker}", ticker).replace("{source}", source)
            .replace("{age}", age ?: "").replace("{headline}", headline)
    }

    private fun teaser(snap: JSONObject, now: Long): JSONObject? {
        if (planExpired(snap, now)) return null
        val t = snap.optJSONObject("teaser") ?: return null
        return t.takeIf { it.optString("text", "").isNotEmpty() }
    }

    private fun itemUrl(item: Item, size: String, age: String) =
        "target=${item.kind}&id=${Uri.encode(item.id)}&rank=${item.rank}&size=$size$age"

    private fun teaserUrl(t: JSONObject, size: String, age: String) =
        "target=teaser_${t.optString("kind", "news")}&size=$size$age"

    /** Mediano: el primer ítem vigente reemplaza a la frase; el aviso solo si Flutter lo habilitó. */
    private fun bindMediumItem(context: Context, views: RemoteViews, snap: JSONObject, now: Long, age: String) {
        val item = resolveItems(snap, now).firstOrNull()
        val teaser = teaser(snap, now)?.takeIf { it.optBoolean("medium", false) }
        views.setViewVisibility(R.id.widget_item, View.GONE)
        views.setViewVisibility(R.id.widget_teaser, View.GONE)
        if (item != null) {
            views.setViewVisibility(R.id.widget_phrase, View.GONE)
            views.setViewVisibility(R.id.widget_item, View.VISIBLE)
            bindItemText(views, R.id.widget_item_meta, R.id.widget_item_text, item)
            views.setContentDescription(R.id.widget_item, item.a11y)
            views.setOnClickPendingIntent(R.id.widget_item, launch(context, itemUrl(item, "medium", age)))
        } else if (teaser != null) {
            views.setViewVisibility(R.id.widget_phrase, View.GONE)
            views.setViewVisibility(R.id.widget_teaser, View.VISIBLE)
            views.setTextViewText(R.id.widget_teaser, teaser.optString("text"))
            views.setOnClickPendingIntent(R.id.widget_teaser, launch(context, teaserUrl(teaser, "medium", age)))
        } else {
            views.setViewVisibility(R.id.widget_phrase, View.VISIBLE)
        }
    }

    private fun bindItemText(views: RemoteViews, metaId: Int, textId: Int, item: Item) {
        if (item.meta == null) {
            views.setViewVisibility(metaId, View.GONE)
        } else {
            views.setViewVisibility(metaId, View.VISIBLE)
            views.setTextViewText(metaId, item.meta)
        }
        views.setTextViewText(textId, item.text)
    }

    /** Grande: sección de novedades (hasta 4 filas, el aviso cuenta) + preguntas. */
    private fun bindLarge(context: Context, views: RemoteViews, snap: JSONObject, now: Long, age: String) {
        val section = snap.optBoolean("items_section", false)
        val rows = intArrayOf(R.id.widget_item_1, R.id.widget_item_2, R.id.widget_item_3, R.id.widget_item_4)
        val metas = intArrayOf(R.id.widget_item_1_meta, R.id.widget_item_2_meta, R.id.widget_item_3_meta, R.id.widget_item_4_meta)
        val texts = intArrayOf(R.id.widget_item_1_text, R.id.widget_item_2_text, R.id.widget_item_3_text, R.id.widget_item_4_text)
        if (!section) {
            // Sin sección (Free sin aviso, solo cripto, snapshot viejo): preguntas grandes.
            views.setViewVisibility(R.id.widget_section, View.INVISIBLE)
            views.setViewVisibility(R.id.widget_q_row, View.GONE)
            views.setViewVisibility(R.id.widget_q_big, View.VISIBLE)
            bindQuestions(context, views, snap, intArrayOf(R.id.widget_qb1, R.id.widget_qb2), "large", age)
            return
        }
        views.setViewVisibility(R.id.widget_section, View.VISIBLE)
        views.setViewVisibility(R.id.widget_q_row, View.VISIBLE)
        views.setViewVisibility(R.id.widget_q_big, View.GONE)
        bindQuestions(context, views, snap, intArrayOf(R.id.widget_q1, R.id.widget_q2), "large", age)

        val labels = itemLabels(snap)
        views.setTextViewText(R.id.widget_section_title, labels.optString("section", ""))
        val teaser = teaser(snap, now)
        val items = resolveItems(snap, now).take(4 - if (teaser == null) 0 else 1)
        for (i in rows.indices) {
            val item = items.getOrNull(i)
            when {
                item != null -> {
                    views.setViewVisibility(rows[i], View.VISIBLE)
                    bindItemText(views, metas[i], texts[i], item)
                    views.setContentDescription(rows[i], item.a11y)
                    views.setOnClickPendingIntent(rows[i], launch(context, itemUrl(item, "large", age)))
                }
                i == items.size && teaser != null -> {
                    views.setViewVisibility(rows[i], View.VISIBLE)
                    views.setViewVisibility(metas[i], View.GONE)
                    views.setTextViewText(texts[i], teaser.optString("text"))
                    views.setContentDescription(rows[i], teaser.optString("text"))
                    views.setOnClickPendingIntent(rows[i], launch(context, teaserUrl(teaser, "large", age)))
                }
                else -> views.setViewVisibility(rows[i], View.GONE)
            }
        }
        val rowCount = items.size + if (teaser == null) 0 else 1
        val placeholder = if (rowCount > 0) null else sectionPlaceholder(snap, labels, now, teaser)
        views.setViewVisibility(R.id.widget_section_empty, if (placeholder == null) View.GONE else View.VISIBLE)
        if (placeholder != null) views.setTextViewText(R.id.widget_section_empty, placeholder)
    }

    /** Sin ítems vigentes: "vencieron" (o plan vencido) o "sin novedades". */
    private fun sectionPlaceholder(snap: JSONObject, labels: JSONObject, now: Long, teaser: JSONObject?): String? {
        val hadItems = (snap.optJSONArray("items")?.length() ?: 0) > 0
        val checkedAt = snap.optLong("items_checked_at", 0L)
        val checkedOld = checkedAt > 0 && now > checkedAt + 48 * 3600 * 1000L
        return if (planExpired(snap, now) || hadItems || checkedOld) {
            labels.optString("all_expired", "").ifEmpty { null }
        } else if (teaser == null) {
            labels.optString("empty", "").ifEmpty { null }
        } else null
    }

    /** Lo único que escribe el widget (Am.4.8): conteos por tamaño, sin tickers. */
    private fun writeRenderLog(prefs: SharedPreferences, snap: JSONObject?, size: WidgetSize, now: Long) {
        if (size == WidgetSize.SMALL) return
        if (snap == null || snap.optString("state") != "ready" || !snap.has("change_pct_text")) return
        try {
            var news = 0
            var earnings = 0
            var teaserKind = "none"
            val items = resolveItems(snap, now)
            if (size == WidgetSize.MEDIUM) {
                val first = items.firstOrNull()
                if (first != null) {
                    if (first.isEarnings) earnings = 1 else news = 1
                } else {
                    val t = teaser(snap, now)?.takeIf { it.optBoolean("medium", false) }
                    if (t != null) teaserKind = t.optString("kind", "news")
                }
            } else if (snap.optBoolean("items_section", false)) {
                val t = teaser(snap, now)
                val shown = items.take(4 - if (t == null) 0 else 1)
                news = shown.count { !it.isEarnings }
                earnings = shown.count { it.isEarnings }
                if (t != null) teaserKind = t.optString("kind", "news")
            }
            val log = try {
                JSONObject(prefs.getString(RENDER_LOG_KEY, null) ?: "{}")
            } catch (e: Exception) {
                JSONObject()
            }
            log.put(
                size.key,
                JSONObject()
                    .put("at", now)
                    .put("news", news)
                    .put("earnings", earnings)
                    .put("teaser", teaserKind),
            )
            prefs.edit().putString(RENDER_LOG_KEY, log.toString()).apply()
        } catch (e: Exception) {
            // El log es una aproximación: nunca debe romper el dibujo.
        }
    }

    private fun withAlpha(color: Int, alpha: Int) = (color and 0x00FFFFFF) or (alpha shl 24)

    private fun updatedText(labels: JSONObject, minutes: Long?): String? {
        if (minutes == null) return null
        val (key, n) = when {
            minutes < 1 -> "updated_now" to 0L
            minutes < 60 -> "updated_min" to minutes
            minutes < 60 * 24 -> "updated_h" to minutes / 60
            else -> "updated_d" to minutes / (60 * 24)
        }
        return labels.optString(key).takeIf { it.isNotEmpty() }?.replace("{n}", n.toString())
    }

    private fun launch(context: Context, query: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("porty-widget://open?homeWidget&$query"),
        )

    /**
     * Sin red ni WorkManager que lo redibuje, "hace X" y "datos viejos"
     * necesitan un empujón: una alarma inexacta (sin permiso especial) cada
     * 15 min o en `stale_at`, lo que llegue primero.
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
        // Próximo límite: stale_at, plan_until, vencimiento de ítems o cambio
        // de segmento de resultados (Am.4.9). Alarma inexacta, sin permisos.
        fun consider(t: Long) { if (t > now && t < at) at = t }
        consider(snap.optLong("stale_at", 0L))
        consider(snap.optLong("plan_until", 0L))
        val arr = snap.optJSONArray("items")
        if (arr != null) {
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                consider(o.optLong("expires_at", 0L))
                val segs = o.optJSONArray("segments") ?: continue
                for (j in 0 until segs.length()) consider(segs.optJSONObject(j)?.optLong("from", 0L) ?: 0L)
            }
        }
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
