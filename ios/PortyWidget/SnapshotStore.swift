//
//  SnapshotStore.swift
//  PortyWidget
//
//  El widget es un visor tonto: lee el JSON que deja la app (schema v1, ver
//  docs/specs/home-widget-tech.md §3.2) y lo dibuja. Sin red, sin sesión.
//

import Foundation

enum SnapshotStore {
    static let appGroup = "group.com.portyassistant.app"
    static let key = "porty_widget_snapshot"

    /// `nil` = sin snapshot, JSON roto o `v` desconocido: la vista muestra el
    /// estado "abrí Porty".
    static func load() -> WidgetSnapshot? {
        guard
            let raw = UserDefaults(suiteName: appGroup)?.string(forKey: key),
            let data = raw.data(using: .utf8),
            var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
            snapshot.v == 1
        else { return nil }
        // Campos de la ampliación: opcionales y tolerantes. Un snapshot v1
        // viejo (sin ellos) queda con `extras` vacío y se dibuja como antes.
        snapshot.extras = (try? JSONDecoder().decode(WidgetExtras.self, from: data))
            ?? WidgetExtras()
        return snapshot
    }

    static let renderLogKey = "porty_widget_render_log"

    /// Lo único que escribe el widget (Am.4.8): qué dibujó por tamaño, solo
    /// conteos (nunca tickers ni titulares). La app lo lee al abrir.
    static func writeRenderLog(size: String, news: Int, earnings: Int, teaser: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        var log: [String: Any] = [:]
        if let raw = defaults.string(forKey: renderLogKey),
           let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            log = obj
        }
        log[size] = [
            "at": Int64(Date().timeIntervalSince1970 * 1000),
            "news": news,
            "earnings": earnings,
            "teaser": teaser,
        ] as [String: Any]
        if let data = try? JSONSerialization.data(withJSONObject: log, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: renderLogKey)
        }
    }
}

struct WidgetQuestion: Decodable, Hashable {
    let id: String
    let text: String
}

struct WidgetLabels: Decodable {
    let periodToday: String?
    let periodLastClose: String?
    let staleDate: String?
    let updatedNow: String?
    let updatedMin: String?
    let updatedH: String?
    let updatedD: String?
    let hiddenAmount: String?
    let hiddenA11y: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case periodToday = "period_today"
        case periodLastClose = "period_last_close"
        case staleDate = "stale_date"
        case updatedNow = "updated_now"
        case updatedMin = "updated_min"
        case updatedH = "updated_h"
        case updatedD = "updated_d"
        case hiddenAmount = "hidden_amount"
        case hiddenA11y = "hidden_a11y"
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
    let amountsHidden: Bool?
    let totalText: String?
    let changeText: String?
    let changePctText: String?
    let direction: String?     // "up" | "down" | "flat"
    let phrase: String?
    let phraseStale: String?
    let a11yValue: String?
    let labels: WidgetLabels?
    let questions: [WidgetQuestion]?
    /// Novedades (noticias y resultados). Fuera de `CodingKeys`: se decodifican aparte.
    var extras: WidgetExtras = WidgetExtras()

    enum CodingKeys: String, CodingKey {
        case v, state, lang, period, direction, phrase, labels, questions
        case writtenAt = "written_at"
        case dataAsOf = "data_as_of"
        case staleAt = "stale_at"
        case amountsHidden = "amounts_hidden"
        case totalText = "total_text"
        case changeText = "change_text"
        case changePctText = "change_pct_text"
        case phraseStale = "phrase_stale"
        case a11yValue = "a11y_value"
    }

    var hidden: Bool { amountsHidden ?? false }
    var isReady: Bool { state == "ready" && changePctText != nil }

    var dataAsOfDate: Date? { dataAsOf.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var staleAtDate: Date? { staleAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// Datos de ejemplo FICTICIOS para la galería y el placeholder: nunca la
    /// cartera real (compliance). Textos del `Localizable.strings` propio.
    static func sample(now: Date) -> WidgetSnapshot {
        func tr(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        let asOf = now.addingTimeInterval(-5 * 60).timeIntervalSince1970 * 1000
        return WidgetSnapshot(
            v: 1, state: "ready", lang: nil,
            writtenAt: asOf, dataAsOf: asOf,
            staleAt: now.addingTimeInterval(12 * 3600).timeIntervalSince1970 * 1000,
            period: "today", amountsHidden: false,
            totalText: "$10,000.00", changeText: "+$50.00", changePctText: "+0.5%",
            direction: "up",
            phrase: tr("sample_phrase"), phraseStale: tr("sample_phrase"),
            a11yValue: tr("sample_a11y"),
            labels: WidgetLabels(
                periodToday: tr("sample_period"), periodLastClose: tr("sample_period"),
                staleDate: nil, updatedNow: tr("sample_updated"),
                updatedMin: tr("sample_updated"), updatedH: tr("sample_updated"),
                updatedD: tr("sample_updated"), hiddenAmount: "••••",
                hiddenA11y: nil, message: nil),
            questions: [
                WidgetQuestion(id: "today", text: tr("sample_q_today")),
                WidgetQuestion(id: "top_mover", text: tr("sample_q_top_mover")),
            ],
            extras: sampleExtras(now: now))
    }

    /// Ítems FICTICIOS (tickers y titulares inventados, fuente "Fuente Ejemplo").
    private static func sampleExtras(now: Date) -> WidgetExtras {
        func tr(_ k: String) -> String { NSLocalizedString(k, comment: "") }
        let nowMs = now.timeIntervalSince1970 * 1000
        var e = WidgetExtras()
        e.itemsSection = true
        e.itemsCheckedAt = nowMs
        e.itemsLabels = WidgetItemsLabels(
            section: tr("sample_items_section"), empty: nil, allExpired: nil,
            redacted: tr("sample_items_redacted"),
            ageMin: tr("sample_age_min"), ageH: tr("sample_age_h"),
            ageYesterday: tr("sample_age_yesterday"), a11yNews: tr("sample_a11y_news"))
        e.items = [
            WidgetItem(
                id: "00000001", kind: "earnings", ticker: "ACME", source: nil,
                headline: nil, publishedAt: nil, expiresAt: nowMs + 24 * 3600_000,
                segments: [WidgetSegment(from: nowMs - 1000, text: tr("sample_item_earnings"))],
                a11y: tr("sample_item_earnings")),
            WidgetItem(
                id: "00000002", kind: "news", ticker: "ACME", source: tr("sample_item_source"),
                headline: tr("sample_item_news_1"), publishedAt: nowMs - 3 * 3600_000,
                expiresAt: nowMs + 45 * 3600_000, segments: nil, a11y: nil),
            WidgetItem(
                id: "00000003", kind: "news", ticker: "ZYNT", source: tr("sample_item_source"),
                headline: tr("sample_item_news_2"), publishedAt: nowMs - 5 * 3600_000,
                expiresAt: nowMs + 43 * 3600_000, segments: nil, a11y: nil),
        ]
        return e
    }
}
