//
//  PortyWidgetFeed.swift
//  PortyWidget
//
//  Bloque `v2` del snapshot y reglas de qué dibuja cada tamaño
//  (docs/specs/home-widget-v2-tech.md §3.2 y §3.5). SOLO `import Foundation`:
//  este archivo se compila solo con `ios/tools/feed_cases_check.swift`.
//  Idéntico en reglas a `PortyFeedPicker.kt` (Android) y `WidgetFeedPicker` (Dart).
//  Ausente = no hay: nunca lanza.
//

import Foundation

// MARK: - Modelo (se decodifica con keyDecodingStrategy = .convertFromSnakeCase)

/// Decodifica un valor sin romper el resto si viene mal formado.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct FeedSegment: Decodable {
    var from: Double = 0
    var prio: Int = 3
    var short: String? = nil
    var title: String? = nil
    var meta: String? = nil
}

struct FeedOpen: Decodable {
    var target: String? = nil
    var id: String? = nil
}

struct FeedQuestion: Decodable {
    var ref: String
    var t: String
    var src: String
    var text: String
}

struct FeedItem: Decodable {
    var id: String? = nil
    var kind: String
    var icon: String? = nil
    var tag: String? = nil
    var paid: Bool? = nil
    var publishedAt: Double? = nil
    var expiresAt: Double
    var segments: [FeedSegment]
    var a11y: String? = nil
    var open: FeedOpen? = nil
    var q: FeedQuestion? = nil
}

struct FeedChart: Decodable {
    var kind: String
    var points: [Double]
    var baseline: Double? = nil

    /// Con menos de 2 puntos no hay línea que dibujar.
    var isDrawable: Bool { points.count >= 2 }
}

struct FeedQuestions {
    var fallback: FeedQuestion? = nil
    var large: [FeedQuestion] = []
}

extension FeedQuestions: Decodable {
    private enum Keys: String, CodingKey { case fallback, large }
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
        fallback = try? c.decodeIfPresent(FeedQuestion.self, forKey: .fallback)
        large = (try? c.decodeIfPresent([Lossy<FeedQuestion>].self, forKey: .large))?
            .compactMap { $0.value } ?? []
    }
}

struct FeedLabels: Decodable {
    var yourPortfolio: String? = nil
    var ageNow: String? = nil
    var ageMin: String? = nil
    var ageH: String? = nil
    var ageYesterday: String? = nil
    var ageD: String? = nil
    var headerOne: String? = nil
    var headerOther: String? = nil
    var headerNone: String? = nil
    var listTitle: String? = nil
    var next: String? = nil
    var nextA11y: String? = nil
    var hiddenCountOne: String? = nil
    var hiddenCountOther: String? = nil
    var noNews: String? = nil
    var redacted: String? = nil
    var chartA11yIntraday: String? = nil
    var chartA11yDays: String? = nil
}

struct V2Block {
    var positionsHidden: Bool = false
    var mood: String = "neutral"
    var planUntil: Double? = nil
    var chart: FeedChart? = nil
    var feedRev: String? = nil
    var feed: [FeedItem] = []
    var questions: FeedQuestions = FeedQuestions()
    var labels: FeedLabels = FeedLabels()
}

extension V2Block: Decodable {
    private enum Keys: String, CodingKey {
        case positionsHidden, mood, planUntil, chart, feedRev, feed, questions, labels
    }

    /// Cada campo por separado: uno roto no tira abajo el resto. Si `v2` ni
    /// siquiera es un objeto, lanza y el llamador cae al modo legado.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        positionsHidden = (try? c.decodeIfPresent(Bool.self, forKey: .positionsHidden)) ?? false
        mood = (try? c.decodeIfPresent(String.self, forKey: .mood)) ?? "neutral"
        planUntil = try? c.decodeIfPresent(Double.self, forKey: .planUntil)
        chart = try? c.decodeIfPresent(FeedChart.self, forKey: .chart)
        feedRev = try? c.decodeIfPresent(String.self, forKey: .feedRev)
        feed = (try? c.decodeIfPresent([Lossy<FeedItem>].self, forKey: .feed))?
            .compactMap { $0.value }
            .filter { !$0.segments.isEmpty } ?? []
        questions = (try? c.decodeIfPresent(FeedQuestions.self, forKey: .questions)) ?? FeedQuestions()
        labels = (try? c.decodeIfPresent(FeedLabels.self, forKey: .labels)) ?? FeedLabels()
    }

    /// Decodifica el bloque `v2` de un snapshot (JSON completo). `nil` = no hay
    /// `v2` o no es un objeto -> modo legado.
    static func parse(snapshotJSON data: Data) -> V2Block? {
        struct Wrapper: Decodable { let v2: V2Block? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let wrapper = try? decoder.decode(Wrapper.self, from: data) else { return nil }
        return wrapper.v2
    }
}

/// Lo que escribe el nativo al tocar "siguiente" (`porty_widget_cursor`).
struct FeedCursor: Codable, Equatable {
    var rev: String
    var index: Int
    var at: Double
}

// MARK: - Antigüedad ("hace X")

enum FeedAge {
    /// `< 1 min` ahora; `< 60 min` minutos; `< 24 h` horas; día calendario anterior
    /// "ayer"; si no, días.
    static func text(
        sinceMs: Double, nowMs: Double, labels: FeedLabels, calendar: Calendar = .current
    ) -> String? {
        let minutes = max(0, Int((nowMs - sinceMs) / 60000))
        func fill(_ template: String?, _ n: Int) -> String? {
            template?.replacingOccurrences(of: "{n}", with: String(n))
        }
        if minutes < 1 { return labels.ageNow }
        if minutes < 60 { return fill(labels.ageMin, minutes) }
        if minutes < 60 * 24 { return fill(labels.ageH, minutes / 60) }
        let then = Date(timeIntervalSince1970: sinceMs / 1000)
        let now = Date(timeIntervalSince1970: nowMs / 1000)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(then, inSameDayAs: yesterday) {
            return labels.ageYesterday
        }
        return fill(labels.ageD, max(1, minutes / (60 * 24)))
    }

    /// Reemplaza `{age}` (vacío si no hay dato).
    static func resolve(_ text: String?, age: String?) -> String? {
        text?.replacingOccurrences(of: "{age}", with: age ?? "")
    }
}

// MARK: - Selector (§3.5)

enum SmallLine {
    case item(FeedItem)
    case chart
    case hiddenCount(Int)
    case noNews
}

struct MediumPick {
    var item: FeedItem? = nil
    /// Con posiciones ocultas: cuántas novedades (nil = `no_news`).
    var hiddenCount: Int? = nil
    var question: FeedQuestion? = nil
    var showNext: Bool = false
    var index: Int = 0
}

struct LargePick {
    var headerN: Int = 0
    var rows: [FeedItem] = []
    var hiddenCount: Int? = nil
    var questions: [FeedQuestion] = []
}

enum FeedPicker {
    /// Último segmento con `from <= now` (si ninguno, el primero).
    static func seg(_ item: FeedItem, nowMs: Double) -> FeedSegment {
        var current: FeedSegment? = nil
        for s in item.segments where s.from <= nowMs { current = s }
        return current ?? item.segments[0]
    }

    static func prio(_ item: FeedItem, nowMs: Double) -> Int {
        seg(item, nowMs: nowMs).prio
    }

    /// Ítems vigentes, ordenados de forma estable por prioridad del segmento.
    static func live(_ block: V2Block, nowMs: Double) -> [FeedItem] {
        let planOver = block.planUntil.map { nowMs >= $0 } ?? false
        let alive = block.feed.filter { item in
            guard nowMs < item.expiresAt, !item.segments.isEmpty else { return false }
            if planOver && item.paid == true { return false }
            return true
        }
        return alive.enumerated()
            .sorted { a, b in
                let pa = prio(a.element, nowMs: nowMs)
                let pb = prio(b.element, nowMs: nowMs)
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            .map { $0.element }
    }

    static func nearCount(_ live: [FeedItem], nowMs: Double) -> Int {
        live.filter { prio($0, nowMs: nowMs) <= 2 }.count
    }

    static func small(_ block: V2Block, nowMs: Double) -> SmallLine {
        let live = Self.live(block, nowMs: nowMs)
        let near = live.filter { prio($0, nowMs: nowMs) <= 2 }
        let hasChart = block.chart?.isDrawable == true
        if block.positionsHidden {
            if !near.isEmpty { return .hiddenCount(near.count) }
            return hasChart ? .chart : .noNews
        }
        if let first = near.first { return .item(first) }
        return hasChart ? .chart : .noNews
    }

    /// Índice actual del mediano: el del cursor si es del mismo feed, si no 0.
    static func currentIndex(_ block: V2Block, liveCount: Int, cursor: FeedCursor?) -> Int {
        guard liveCount > 0, let cursor, let rev = block.feedRev, cursor.rev == rev else { return 0 }
        return ((cursor.index % liveCount) + liveCount) % liveCount
    }

    static func medium(_ block: V2Block, nowMs: Double, cursor: FeedCursor?) -> MediumPick {
        let live = Self.live(block, nowMs: nowMs)
        if block.positionsHidden {
            let n = nearCount(live, nowMs: nowMs)
            return MediumPick(
                hiddenCount: n > 0 ? n : nil, question: block.questions.fallback)
        }
        guard !live.isEmpty else {
            return MediumPick(question: block.questions.fallback)
        }
        let index = currentIndex(block, liveCount: live.count, cursor: cursor)
        let item = live[index]
        return MediumPick(
            item: item, question: item.q ?? block.questions.fallback,
            showNext: live.count >= 2, index: index)
    }

    static func large(_ block: V2Block, nowMs: Double) -> LargePick {
        let live = Self.live(block, nowMs: nowMs)
        let n = nearCount(live, nowMs: nowMs)
        if block.positionsHidden {
            return LargePick(
                headerN: n, rows: [], hiddenCount: n > 0 ? n : nil,
                questions: block.questions.large)
        }
        var rows: [FeedItem] = []
        var skipped: [FeedItem] = []
        var perKind: [String: Int] = [:]
        for item in live {
            if rows.count == 3 { break }
            if (perKind[item.kind] ?? 0) >= 2 {
                skipped.append(item)
            } else {
                rows.append(item)
                perKind[item.kind, default: 0] += 1
            }
        }
        for item in skipped where rows.count < 3 { rows.append(item) }
        return LargePick(headerN: n, rows: rows, questions: block.questions.large)
    }

    /// Cursor que deja "siguiente" (nil si no hay nada que avanzar).
    static func advance(_ block: V2Block, nowMs: Double, cursor: FeedCursor?) -> FeedCursor? {
        let live = Self.live(block, nowMs: nowMs)
        guard live.count >= 1, !block.positionsHidden else { return nil }
        let i = currentIndex(block, liveCount: live.count, cursor: cursor)
        return FeedCursor(rev: block.feedRev ?? "", index: (i + 1) % live.count, at: nowMs)
    }

    /// Horas futuras en que cambia lo que se dibuja: vencimientos, segmentos y fin del plan.
    static func boundaries(_ block: V2Block, afterMs nowMs: Double) -> [Double] {
        var ms: [Double] = []
        if let p = block.planUntil { ms.append(p) }
        for item in block.feed {
            ms.append(item.expiresAt)
            for s in item.segments { ms.append(s.from) }
        }
        return ms.filter { $0 > nowMs }
    }
}
