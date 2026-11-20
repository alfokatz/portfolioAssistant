//
//  SnapshotStore.swift
//  PortyWidget
//
//  El widget es un visor tonto: lee el JSON que deja la app (schema v1 + bloque
//  opcional `v2`, ver docs/specs/home-widget-v2-tech.md §3) y lo dibuja. Sin red,
//  sin sesión. Lo único que escribe: el cursor de "siguiente" y el render log.
//

import Foundation

enum SnapshotStore {
    static let appGroup = "group.com.portyassistant.app"
    static let key = "porty_widget_snapshot"
    static let cursorKey = "porty_widget_cursor"
    static let renderLogKey = "porty_widget_render_log"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// `nil` = sin snapshot, JSON roto o `v` desconocido: la vista muestra el
    /// estado "abrí Porty".
    static func load() -> WidgetSnapshot? {
        guard
            let raw = defaults?.string(forKey: key),
            let data = raw.data(using: .utf8),
            var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
            snapshot.v == 1
        else { return nil }
        // Sin `v2` (JSON de la versión anterior) = modo legado: nunca se lee
        // nada de novedades, montos ni preguntas del JSON viejo (§3.1).
        snapshot.v2 = V2Block.parse(snapshotJSON: data)
        return snapshot
    }

    // MARK: Cursor del mediano

    static func readCursor() -> FeedCursor? {
        guard
            let raw = defaults?.string(forKey: cursorKey),
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(FeedCursor.self, from: data)
    }

    static func writeCursor(_ cursor: FeedCursor) {
        guard
            let data = try? JSONEncoder().encode(cursor),
            let text = String(data: data, encoding: .utf8)
        else { return }
        defaults?.set(text, forKey: cursorKey)
    }

    /// "Siguiente" (§3.5): avanza el índice del mediano, suma 1 a `next_taps`.
    /// Lo llama `NextNoveltyIntent`; sin red ni app.
    static func advanceCursor(now: Date = Date()) {
        guard
            let block = load()?.v2,
            !block.positionsHidden
        else { return }
        let nowMs = now.timeIntervalSince1970 * 1000
        guard let next = FeedPicker.advance(block, nowMs: nowMs, cursor: readCursor()) else { return }
        writeCursor(next)
        var log = readRenderLog()
        var medium = (log["medium"] as? [String: Any]) ?? [:]
        medium["next_taps"] = ((medium["next_taps"] as? Int) ?? 0) + 1
        log["medium"] = medium
        saveRenderLog(log)
    }

    // MARK: Render log

    private static func readRenderLog() -> [String: Any] {
        guard
            let raw = defaults?.string(forKey: renderLogKey),
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func saveRenderLog(_ log: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: log, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            defaults?.set(text, forKey: renderLogKey)
        }
    }

    /// Lo que dibujó el widget por tamaño (§3.3): solo conteos y tipos, nunca ids,
    /// tickers ni textos. `next_taps` (contador del mediano) se conserva.
    static func writeRenderLog(size: String, fields: [String: Any]) {
        guard defaults != nil else { return }
        var log = readRenderLog()
        var entry = fields
        entry["at"] = Int64(Date().timeIntervalSince1970 * 1000)
        if size == "medium" {
            let previous = (log["medium"] as? [String: Any]) ?? [:]
            entry["next_taps"] = (previous["next_taps"] as? Int) ?? 0
        }
        log[size] = entry
        saveRenderLog(log)
    }
}

/// Etiquetas del bloque v1 que el nativo sigue usando (período y "datos viejos").
struct WidgetLabels: Decodable {
    let periodToday: String?
    let periodLastClose: String?
    let staleDate: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case periodToday = "period_today"
        case periodLastClose = "period_last_close"
        case staleDate = "stale_date"
        case message
    }
}

struct WidgetSnapshot: Decodable {
    let v: Int
    let state: String          // "signed_out" | "no_portfolio" | "ready"
    let lang: String?
    let writtenAt: Double?
    let dataAsOf: Double?
    let staleAt: Double?
    let period: String?        // "today" | "last_close"
    let changePctText: String?
    let direction: String?     // "up" | "down" | "flat"
    let a11yValue: String?
    let labels: WidgetLabels?
    /// Bloque v2 (se decodifica aparte, tolerante). `nil` = modo legado.
    var v2: V2Block? = nil

    // Nunca se decodifican `total_text`, `change_text`, `questions`, `phrase` ni
    // `items*` / `teaser`: un JSON viejo podría traer montos o tickers (§3.1).
    enum CodingKeys: String, CodingKey {
        case v, state, lang, period, direction, labels
        case writtenAt = "written_at"
        case dataAsOf = "data_as_of"
        case staleAt = "stale_at"
        case changePctText = "change_pct_text"
        case a11yValue = "a11y_value"
    }

    var isReady: Bool { state == "ready" && changePctText != nil }

    var dataAsOfDate: Date? { dataAsOf.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var staleAtDate: Date? { staleAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// Datos de ejemplo FICTICIOS para la galería y el placeholder: nunca la
    /// cartera real ni montos. Textos del `Localizable.strings` propio.
    static func sample(now: Date) -> WidgetSnapshot {
        func tr(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        let nowMs = now.timeIntervalSince1970 * 1000
        let asOf = nowMs - 5 * 60_000
        let labels = FeedLabels(
            yourPortfolio: tr("sample_your_portfolio"),
            ageNow: nil, ageMin: tr("sample_age_min"), ageH: tr("sample_age_h"),
            ageYesterday: nil, ageD: nil,
            headerOne: tr("sample_header_one"), headerOther: tr("sample_header_other"),
            headerNone: nil, listTitle: tr("sample_list_title"),
            next: nil, nextA11y: tr("sample_next_a11y"),
            hiddenCountOne: nil, hiddenCountOther: nil, noNews: nil,
            redacted: tr("sample_redacted"),
            chartA11yIntraday: nil, chartA11yDays: nil)
        let far = nowMs + 24 * 3_600_000
        let feed: [FeedItem] = [
            FeedItem(
                id: "00000001", kind: "earnings", icon: "calendar", tag: "ACME",
                expiresAt: far,
                segments: [FeedSegment(
                    from: nowMs - 1000, prio: 1, short: tr("sample_earn_short"),
                    title: tr("sample_earn_title"), meta: tr("sample_earn_meta"))],
                a11y: tr("sample_earn_title"),
                open: FeedOpen(target: "home", id: nil),
                q: FeedQuestion(ref: "00000011", t: "earnings_last", src: "novelty",
                                text: tr("sample_q_earnings"))),
            FeedItem(
                id: "00000002", kind: "news", icon: "news", tag: "ZYNT",
                publishedAt: nowMs - 3 * 3_600_000, expiresAt: far,
                segments: [FeedSegment(
                    from: nowMs - 1000, prio: 1, short: tr("sample_news_short"),
                    title: tr("sample_news_title"), meta: tr("sample_news_meta"))],
                a11y: tr("sample_news_title"),
                open: FeedOpen(target: "home", id: nil), q: nil),
            FeedItem(
                id: "00000003", kind: "insight", icon: "pie",
                expiresAt: far,
                segments: [FeedSegment(
                    from: nowMs - 1000, prio: 2, short: tr("sample_insight_title"),
                    title: tr("sample_insight_title"), meta: tr("sample_insight_meta"))],
                a11y: tr("sample_insight_title"),
                open: FeedOpen(target: "home", id: nil), q: nil),
        ]
        let block = V2Block(
            positionsHidden: false, mood: "happy", planUntil: nil,
            chart: FeedChart(
                kind: "intraday",
                points: [0.15, 0.1, 0.25, 0.4, 0.35, 0.7, 0.6, 0.85, 1.0], baseline: 0.2),
            feedRev: "00000000", feed: feed,
            questions: FeedQuestions(
                fallback: FeedQuestion(ref: "00000012", t: "goal_progress", src: "goal",
                                       text: tr("sample_q_goal")),
                large: [
                    FeedQuestion(ref: "00000011", t: "earnings_last", src: "novelty",
                                 text: tr("sample_q_earnings")),
                    FeedQuestion(ref: "00000012", t: "goal_progress", src: "goal",
                                 text: tr("sample_q_goal")),
                ]),
            labels: labels)
        return WidgetSnapshot(
            v: 1, state: "ready", lang: nil, writtenAt: asOf, dataAsOf: asOf,
            staleAt: nowMs + 12 * 3_600_000, period: "today",
            changePctText: tr("sample_pct"), direction: "up",
            a11yValue: tr("sample_a11y"),
            labels: WidgetLabels(
                periodToday: tr("sample_period"), periodLastClose: tr("sample_period"),
                staleDate: nil, message: nil),
            v2: block)
    }
}
