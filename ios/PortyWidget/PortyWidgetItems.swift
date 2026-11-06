//
//  PortyWidgetItems.swift
//  PortyWidget
//
//  Novedades del widget (noticias y resultados): campos opcionales del
//  snapshot v1 (docs/specs/home-widget-tech.md, Am.4.1) y las reglas de
//  vencimiento sin red (Am.4.9). Ausente = no hay: nunca error.
//

import Foundation

/// Decodifica un valor sin romper el resto si viene mal formado.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct WidgetSegment: Decodable {
    let from: Double?
    let text: String?
}

struct WidgetItem: Decodable {
    let id: String?
    let kind: String?          // "news" | "earnings"
    let ticker: String?
    let source: String?
    let headline: String?
    let publishedAt: Double?
    let expiresAt: Double?
    let segments: [WidgetSegment]?
    let a11y: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, ticker, source, headline, segments, a11y
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
    }

    var isEarnings: Bool { kind == "earnings" }
}

struct WidgetTeaser: Decodable {
    let kind: String?          // "news" | "earnings"
    let text: String?
    let count: Int?
    /// Flutter lo pone en true solo si el aviso puede reemplazar a la frase en el mediano.
    let medium: Bool?
}

struct WidgetItemsLabels: Decodable {
    let section: String?
    let empty: String?
    let allExpired: String?
    let redacted: String?
    let ageMin: String?
    let ageH: String?
    let ageYesterday: String?
    let a11yNews: String?

    enum CodingKeys: String, CodingKey {
        case section, empty, redacted
        case allExpired = "all_expired"
        case ageMin = "age_min"
        case ageH = "age_h"
        case ageYesterday = "age_yesterday"
        case a11yNews = "a11y_news"
    }
}

/// Todo lo nuevo de la ampliación. Cada campo se decodifica por separado: uno
/// roto no tira abajo el resto ni el snapshot.
struct WidgetExtras: Decodable {
    var itemsSection: Bool? = nil
    var itemsCheckedAt: Double? = nil
    var planUntil: Double? = nil
    var items: [WidgetItem] = []
    var teaser: WidgetTeaser? = nil
    var itemsLabels: WidgetItemsLabels? = nil

    init() {}

    private enum Keys: String, CodingKey {
        case itemsSection = "items_section"
        case itemsCheckedAt = "items_checked_at"
        case planUntil = "plan_until"
        case items, teaser
        case itemsLabels = "items_labels"
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
        itemsSection = try? c.decodeIfPresent(Bool.self, forKey: .itemsSection)
        itemsCheckedAt = try? c.decodeIfPresent(Double.self, forKey: .itemsCheckedAt)
        planUntil = try? c.decodeIfPresent(Double.self, forKey: .planUntil)
        items = ((try? c.decodeIfPresent([Lossy<WidgetItem>].self, forKey: .items)) ?? nil)?
            .compactMap { $0.value } ?? []
        teaser = (try? c.decodeIfPresent(WidgetTeaser.self, forKey: .teaser)) ?? nil
        itemsLabels = (try? c.decodeIfPresent(WidgetItemsLabels.self, forKey: .itemsLabels)) ?? nil
    }
}

// MARK: - Reglas de tiempo (sin red)

/// Un ítem ya resuelto para la hora de la entrada: texto, rango y destino.
struct ResolvedItem {
    let id: String
    let kind: String
    let rank: Int
    let meta: String?        // "NVDA · fuente · hace 3 h" (solo noticias)
    let text: String         // titular, o el segmento vigente de resultados
    let a11y: String
    var isEarnings: Bool { kind == "earnings" }
}

extension PortyEntry {
    var extras: WidgetExtras { snapshot?.extras ?? WidgetExtras() }
    private var nowMs: Double { date.timeIntervalSince1970 * 1000 }

    /// Plan vencido: se ocultan ítems y aviso (Am.4.9).
    var planExpired: Bool {
        guard let until = extras.planUntil else { return false }
        return nowMs >= until
    }

    /// La sección existe (el grande la dibuja). Snapshot v1 viejo: no.
    var hasItemsSection: Bool { extras.itemsSection == true }

    /// Ítems vigentes, con rank 1..4. Nunca más de 4.
    var resolvedItems: [ResolvedItem] {
        guard !planExpired else { return [] }
        var result: [ResolvedItem] = []
        for item in extras.items {
            if let expires = item.expiresAt, nowMs >= expires { continue }
            guard let id = item.id, let kind = item.kind else { continue }
            let rank = result.count + 1
            if item.isEarnings {
                let segs = item.segments ?? []
                let current = segs.last(where: { ($0.from ?? 0) <= nowMs }) ?? segs.first
                guard let text = current?.text, !text.isEmpty else { continue }
                result.append(ResolvedItem(
                    id: id, kind: kind, rank: rank, meta: nil, text: text,
                    a11y: item.a11y ?? text))
            } else {
                guard let headline = item.headline, !headline.isEmpty else { continue }
                let age = ageText(item.publishedAt)
                let parts = [item.ticker, item.source, age].compactMap { $0 }.filter { !$0.isEmpty }
                result.append(ResolvedItem(
                    id: id, kind: kind, rank: rank,
                    meta: parts.isEmpty ? nil : parts.joined(separator: " · "),
                    text: headline,
                    a11y: newsA11y(item, age: age)))
            }
            if result.count == 4 { break }
        }
        return result
    }

    /// "hace 25 min" / "hace 3 h" / "ayer" desde `published_at`.
    private func ageText(_ publishedAt: Double?) -> String? {
        guard let publishedAt, let labels = extras.itemsLabels else { return nil }
        let minutes = max(0, Int((nowMs - publishedAt) / 60000))
        if minutes < 60 {
            return labels.ageMin?.replacingOccurrences(of: "{n}", with: String(minutes))
        }
        if minutes < 60 * 24 {
            return labels.ageH?.replacingOccurrences(of: "{n}", with: String(minutes / 60))
        }
        return labels.ageYesterday
    }

    private func newsA11y(_ item: WidgetItem, age: String?) -> String {
        let headline = item.headline ?? ""
        guard var template = extras.itemsLabels?.a11yNews else {
            return [item.ticker, item.source, age, headline].compactMap { $0 }.joined(separator: ". ")
        }
        // La plantilla dice "hace {age}"; la antigüedad ya viene con "hace" o es "ayer".
        if age != nil, template.contains("hace {age}") { template = template.replacingOccurrences(of: "hace {age}", with: "{age}") }
        return template
            .replacingOccurrences(of: "{ticker}", with: item.ticker ?? "")
            .replacingOccurrences(of: "{source}", with: item.source ?? "")
            .replacingOccurrences(of: "{age}", with: age ?? "")
            .replacingOccurrences(of: "{headline}", with: headline)
    }

    /// Aviso de plan, si corresponde a esta hora.
    var visibleTeaser: WidgetTeaser? {
        guard !planExpired, let teaser = extras.teaser,
              let text = teaser.text, !text.isEmpty else { return nil }
        return teaser
    }

    /// Texto de la sección del grande cuando no hay ítems vigentes (nil = hay ítems).
    var sectionPlaceholder: String? {
        guard resolvedItems.isEmpty else { return nil }
        let labels = extras.itemsLabels
        let hadItems = !extras.items.isEmpty
        let checkedOld = extras.itemsCheckedAt.map { nowMs > $0 + 48 * 3600 * 1000 } ?? false
        if planExpired || hadItems || checkedOld { return labels?.allExpired }
        return visibleTeaser == nil ? labels?.empty : nil
    }

    /// Mediano: el primer ítem vigente reemplaza a la frase.
    var mediumItem: ResolvedItem? { resolvedItems.first }

    /// Mediano: el aviso solo entra sin ítems vigentes y si Flutter lo habilitó.
    var mediumTeaser: WidgetTeaser? {
        guard mediumItem == nil, let t = visibleTeaser, t.medium == true else { return nil }
        return t
    }

    /// Conteos de lo que se dibuja para el log de render (Am.4.8).
    func renderSummary(medium: Bool) -> (news: Int, earnings: Int, teaser: String) {
        if medium {
            if let item = mediumItem {
                return (item.isEarnings ? 0 : 1, item.isEarnings ? 1 : 0, "none")
            }
            return (0, 0, mediumTeaser?.kind ?? "none")
        }
        guard hasItemsSection else { return (0, 0, "none") }
        let teaser = visibleTeaser
        let items = resolvedItems.prefix(4 - (teaser == nil ? 0 : 1))
        return (items.filter { !$0.isEarnings }.count,
                items.filter { $0.isEarnings }.count,
                teaser?.kind ?? "none")
    }
}

extension WidgetSnapshot {
    /// Horas futuras en las que cambia lo que se dibuja (Am.4.9): vencimiento
    /// de ítems, cambio de segmento de resultados y fin del plan.
    func itemBoundaries(after now: Date) -> [Date] {
        let nowMs = now.timeIntervalSince1970 * 1000
        var ms: [Double] = []
        if let p = extras.planUntil { ms.append(p) }
        for item in extras.items {
            if let e = item.expiresAt { ms.append(e) }
            for seg in item.segments ?? [] { if let f = seg.from { ms.append(f) } }
        }
        return ms.filter { $0 > nowMs }.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
