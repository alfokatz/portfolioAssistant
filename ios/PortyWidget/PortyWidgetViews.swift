//
//  PortyWidgetViews.swift
//  PortyWidget
//
//  Vistas chico/mediano/grande del widget v2 (docs/specs/home-widget-v2-tech.md §3.5).
//  Paleta de DESIGN.md (assets con variante oscura), cifras tabulares, sin montos
//  ni valor total. `.privacySensitive()` en %, ticker, títulos, meta y preguntas; con
//  el sistema redactando se ve el texto aprobado `labels.redacted`.
//  Sin `v2` en el JSON (versión anterior de la app) = modo legado: solo cara,
//  período y %, más un texto propio que invita a abrir Porty.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - Estilo

private enum Fonts {
    static func regular(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-Medium", size: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom("PlusJakartaSans-SemiBold", size: size) }
}

private extension Color {
    static let portyBackground = Color("WidgetBackground")
    static let portyPrimary = Color("PortyTextPrimary")
    static let portySecondary = Color("PortyTextSecondary")
    static let widgetProfit = Color("PortyProfit")
    static let widgetLoss = Color("PortyLoss")
    static let widgetInset = Color("PortyInset")
    /// Terracota #D98E5D: solo como tinte bajo (chip de pregunta). El texto del
    /// chip es `portyPrimary` (tinta), que contrasta >= 4.5:1 sobre el tinte.
    static let widgetTerracotta = Color(red: 217.0 / 255, green: 142.0 / 255, blue: 93.0 / 255)
}

private extension View {
    /// iOS 17+: `containerBackground`; iOS 15/16: fondo + padding propio.
    @ViewBuilder
    func portyContainer() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self
                .padding(16)
                .containerBackground(for: .widget) { Color.portyBackground }
        } else {
            self
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.portyBackground)
        }
    }
}

// MARK: - URLs (§3.4)

/// Solo caracteres de un id/plantilla: la URL nunca lleva texto libre.
private func safe(_ s: String) -> String {
    String(s.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
}

private func appURL(target: String, size: String, extra: String = "", age: Int? = nil) -> URL {
    var s = "porty-widget://open?homeWidget&target=\(target)&size=\(size)"
    if !extra.isEmpty { s += "&\(extra)" }
    if let age { s += "&age=\(age)" }
    return URL(string: s) ?? URL(string: "porty-widget://open?homeWidget&target=home")!
}

private func questionURL(_ q: FeedQuestion, size: String, age: Int?) -> URL {
    appURL(
        target: "question", size: size,
        extra: "q=\(safe(q.t))&ref=\(safe(q.ref))&src=\(safe(q.src))", age: age)
}

private func itemURL(
    _ item: FeedItem, nowMs: Double, size: String, rank: Int, age: Int?
) -> URL {
    var target = item.open?.target ?? "home"
    let allowed = ["news", "earnings", "teaser_news", "teaser_earnings", "home"]
    if !allowed.contains(target) { target = "home" }
    var parts: [String] = []
    if target == "news" || target == "earnings" {
        if let id = item.open?.id ?? item.id {
            parts.append("id=\(safe(id))")
            parts.append("rank=\(min(3, max(1, rank)))")
        } else {
            target = "home"
        }
    }
    if item.kind != "teaser" {
        parts.append("kind=\(safe(item.kind))")
        parts.append("prio=\(FeedPicker.prio(item, nowMs: nowMs))")
    }
    return appURL(target: target, size: size, extra: parts.joined(separator: "&"), age: age)
}

// MARK: - Datos derivados de la entrada

extension PortyEntry {
    var nowMs: Double { date.timeIntervalSince1970 * 1000 }

    /// Minutos desde `data_as_of` hasta la hora de esta entrada.
    var ageMinutes: Int? {
        guard let asOf = snapshot?.dataAsOfDate else { return nil }
        return max(0, Int(date.timeIntervalSince(asOf) / 60))
    }

    /// "tu cartera · hace 5 min". En modo legado, con textos propios del sistema.
    var ageLine: String? {
        guard let s = snapshot, let asOf = s.dataAsOf else { return nil }
        if let block = s.v2 {
            let age = FeedAge.text(sinceMs: asOf, nowMs: nowMs, labels: block.labels)
            let parts = [block.labels.yourPortfolio, age].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let minutes = max(0, Int((nowMs - asOf) / 60000))
        func tr(_ k: String, _ n: Int) -> String {
            NSLocalizedString(k, comment: "").replacingOccurrences(of: "{n}", with: String(n))
        }
        let age: String
        if minutes < 1 { age = tr("legacy_age_now", 0) }
        else if minutes < 60 { age = tr("legacy_age_min", minutes) }
        else if minutes < 60 * 24 { age = tr("legacy_age_h", minutes / 60) }
        else { age = tr("legacy_age_d", minutes / (60 * 24)) }
        return NSLocalizedString("legacy_your_portfolio", comment: "") + " · " + age
    }

    /// "Hoy" / "Último cierre", o "al 3 nov" si ya son datos viejos.
    var periodText: String? {
        guard let s = snapshot, let labels = s.labels else { return nil }
        if isStale { return labels.staleDate }
        return s.period == "last_close" ? labels.periodLastClose : labels.periodToday
    }

    var directionColor: Color {
        switch snapshot?.direction {
        case "up": return .widgetProfit
        case "down": return .widgetLoss
        default: return .portySecondary
        }
    }

    /// Cara de Porty: `mood` del v2; con datos viejos, neutral; en legado, por dirección.
    var mood: String {
        if isStale { return "neutral" }
        if let block = snapshot?.v2 { return block.mood }
        switch snapshot?.direction {
        case "up": return "happy"
        case "down": return "concerned"
        default: return "neutral"
        }
    }

    /// Un solo texto para VoiceOver del bloque del %. Nunca montos.
    var a11yLabel: String {
        guard let s = snapshot, s.isReady else { return messageText }
        var parts: [String] = []
        if s.v2 != nil, let v = s.a11yValue, !v.isEmpty {
            parts.append(v)
        } else {
            parts.append(s.changePctText ?? "")
            if let p = periodText { parts.append(p) }
        }
        if isStale, let p = periodText { parts.append(p) }
        if let a = ageLine { parts.append(a) }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var messageText: String {
        if let s = snapshot, s.state != "ready", let m = s.labels?.message, !m.isEmpty {
            return m
        }
        return NSLocalizedString("no_snapshot_message", comment: "")
    }

    var emptyTarget: String {
        snapshot?.state == "no_portfolio" ? "add_portfolio" : "app"
    }

    /// Cuenta de ítems del feed por tipo (para el render log y la galería).
    private func kindCounts(_ items: [FeedItem]) -> [String: Int] {
        var counts: [String: Int] = [
            "news": 0, "earnings": 0, "insight": 0, "mover": 0, "biggest": 0, "teaser": 0,
        ]
        for item in items where counts[item.kind] != nil { counts[item.kind]! += 1 }
        return counts
    }

    /// Qué se dibujó (§3.3): solo tipos y conteos, nunca ids, tickers ni textos.
    func renderFields(size: String) -> [String: Any] {
        guard let block = snapshot?.v2 else { return [:] }
        let live = FeedPicker.live(block, nowMs: nowMs)
        var f: [String: Any] = ["live": live.count]
        var shown: [FeedItem] = []
        switch size {
        case "small":
            switch FeedPicker.small(block, nowMs: nowMs) {
            case .item(let i):
                f["line"] = (i.kind == "news" || i.kind == "earnings") ? "dated" : "insight"
            case .chart: f["line"] = "chart"
            case .hiddenCount: f["line"] = "hidden_count"
            case .noNews: f["line"] = "none"
            }
            return f
        case "medium":
            let pick = FeedPicker.medium(block, nowMs: nowMs, cursor: cursor)
            if let item = pick.item {
                shown = [item]
                f["shown_kind"] = item.kind
                f["shown_prio"] = FeedPicker.prio(item, nowMs: nowMs)
            }
        default:
            shown = FeedPicker.large(block, nowMs: nowMs).rows
        }
        f["kinds"] = kindCounts(shown)
        // Campos de la ampliación, que la app sigue leyendo.
        f["news"] = shown.filter { $0.kind == "news" }.count
        f["earnings"] = shown.filter { $0.kind == "earnings" }.count
        var teaser = "none"
        if let t = shown.first(where: { $0.kind == "teaser" }) {
            teaser = (t.open?.target == "teaser_earnings") ? "earnings" : "news"
        }
        f["teaser"] = teaser
        return f
    }
}

// MARK: - Raíz

struct PortyWidgetView: View {
    let entry: PortyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let size: String = {
            switch family {
            case .systemLarge: return "large"
            case .systemMedium: return "medium"
            default: return "small"
            }
        }()
        Group {
            if let s = entry.snapshot, s.isReady {
                switch family {
                case .systemLarge: LargeReadyView(entry: entry, snapshot: s)
                case .systemMedium: MediumReadyView(entry: entry, snapshot: s)
                default: SmallReadyView(entry: entry, snapshot: s)
                }
            } else {
                MessageView(entry: entry)
            }
        }
        .portyContainer()
        .widgetURL(rootURL(size: size))
    }

    /// Chico: el `open` del ítem de su línea; con gráfico o línea oculta, la Home.
    private func rootURL(size: String) -> URL {
        guard let s = entry.snapshot, s.isReady else {
            return appURL(target: entry.emptyTarget, size: size, age: entry.ageMinutes)
        }
        if size == "small", let block = s.v2,
           case .item(let item) = FeedPicker.small(block, nowMs: entry.nowMs) {
            return itemURL(item, nowMs: entry.nowMs, size: size, rank: 1, age: entry.ageMinutes)
        }
        return appURL(target: "home", size: size, age: entry.ageMinutes)
    }
}

// MARK: - Piezas

private struct FaceView: View {
    let mood: String
    let side: CGFloat

    /// Las caras contenta/preocupada las exporta la herramienta de Dart. Hasta
    /// que estén en el catálogo se usa la cara normal.
    private var assetName: String {
        let name: String
        switch mood {
        case "happy": name = "PortyAvatarHappy"
        case "concerned": name = "PortyAvatarConcerned"
        default: name = "PortyAvatar"
        }
        if name != "PortyAvatar", UIImage(named: name) == nil { return "PortyAvatar" }
        return name
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

private struct ItemIcon: View {
    let icon: String?
    let kind: String

    private var symbol: String {
        switch icon ?? kind {
        case "calendar", "earnings": return "calendar"
        case "news", "teaser": return "newspaper"
        case "pie", "insight", "biggest": return "chart.pie"
        case "chart", "mover": return "chart.line.uptrend.xyaxis"
        default: return "newspaper"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.portySecondary)
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}

private struct TickerTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Fonts.semibold(10.5))
            .foregroundColor(.portyPrimary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.widgetInset)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .privacySensitive()
    }
}

/// Pregunta en chip terracota de baja opacidad; un toque abre el chat con la
/// pregunta ya enviada (resuelta en la app por `ref`).
private struct QuestionChip: View {
    let q: FeedQuestion
    let size: String
    let age: Int?
    let minHeight: CGFloat

    var body: some View {
        Link(destination: questionURL(q, size: size, age: age)) {
            Text(q.text)
                .font(Fonts.medium(11.5))
                .foregroundColor(.portyPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(Color.widgetTerracotta.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .privacySensitive()
        }
    }
}

/// Gráfico del día normalizado [0,1]: línea del color de la dirección y, si
/// hay, el cierre anterior punteado.
private struct ChartLine: View {
    let chart: FeedChart
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inset: CGFloat = 2
            let pts = chart.points
            ZStack {
                if let b = chart.baseline {
                    Path { p in
                        let y = inset + (h - 2 * inset) * (1 - CGFloat(min(1, max(0, b))))
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(
                        Color.portySecondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Path { p in
                    for (i, v) in pts.enumerated() {
                        let x = pts.count > 1 ? w * CGFloat(i) / CGFloat(pts.count - 1) : 0
                        let y = inset + (h - 2 * inset) * (1 - CGFloat(min(1, max(0, v))))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Botón "siguiente novedad": solo iOS 17+ (AppIntent interactivo). En 15/16 no se dibuja.
private struct NextButton: View {
    let label: String

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: NextNoveltyIntent()) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.portyPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.widgetInset)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }
}

private struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.portySecondary.opacity(0.25))
            .frame(height: 0.5)
    }
}

private func hiddenCountText(_ n: Int, _ labels: FeedLabels) -> String {
    let template = n == 1 ? labels.hiddenCountOne : labels.hiddenCountOther
    return (template ?? "").replacingOccurrences(of: "{n}", with: String(n))
}

private func legacyNote() -> String {
    NSLocalizedString("legacy_open_porty", comment: "")
}

/// Cara + período (arriba del %).
private struct FaceAndPeriod: View {
    let entry: PortyEntry
    let side: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            FaceView(mood: entry.mood, side: side)
            if let period = entry.periodText {
                Text(period)
                    .font(Fonts.medium(12))
                    .foregroundColor(.portySecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PctText: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot
    let size: CGFloat

    var body: some View {
        Text(snapshot.changePctText ?? "")
            .font(Fonts.semibold(size))
            .monospacedDigit()
            .foregroundColor(entry.directionColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .privacySensitive()
            .opacity(entry.isStale ? 0.5 : 1)
    }
}

// MARK: - Chico

private struct SmallReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FaceAndPeriod(entry: entry, side: 24)
            PctText(entry: entry, snapshot: snapshot, size: 30)
            Spacer(minLength: 2)
            line
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var line: some View {
        if let block = snapshot.v2 {
            switch FeedPicker.small(block, nowMs: entry.nowMs) {
            case .item(let item):
                let seg = FeedPicker.seg(item, nowMs: entry.nowMs)
                let age = item.publishedAt.flatMap {
                    FeedAge.text(sinceMs: $0, nowMs: entry.nowMs, labels: block.labels)
                }
                HStack(alignment: .top, spacing: 6) {
                    ItemIcon(icon: item.icon, kind: item.kind)
                    Text(FeedAge.resolve(seg.short, age: age) ?? "")
                        .font(Fonts.medium(11.5))
                        .foregroundColor(.portyPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .privacySensitive()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FeedAge.resolve(item.a11y ?? seg.short, age: age) ?? "")
            case .chart:
                if let chart = block.chart {
                    HStack(spacing: 6) {
                        ItemIcon(icon: "chart", kind: "mover")
                        ChartLine(chart: chart, color: entry.directionColor)
                            .frame(height: 22)
                            .opacity(entry.isStale ? 0.5 : 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chartLabel(chart, block.labels))
                }
            case .hiddenCount(let n):
                HStack(alignment: .top, spacing: 6) {
                    ItemIcon(icon: "news", kind: "news")
                    Text(hiddenCountText(n, block.labels))
                        .font(Fonts.medium(11.5))
                        .foregroundColor(.portyPrimary)
                        .lineLimit(2)
                }
            case .noNews:
                Text(block.labels.noNews ?? "")
                    .font(Fonts.regular(11.5))
                    .foregroundColor(.portySecondary)
                    .lineLimit(2)
            }
        } else {
            Text(legacyNote())
                .font(Fonts.regular(11.5))
                .foregroundColor(.portySecondary)
                .lineLimit(3)
        }
    }
}

private func chartLabel(_ chart: FeedChart, _ labels: FeedLabels) -> String {
    (chart.kind == "days" ? labels.chartA11yDays : labels.chartA11yIntraday) ?? ""
}

// MARK: - Mediano

private struct MediumReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            left.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 4) {
            FaceAndPeriod(entry: entry, side: 24)
            PctText(entry: entry, snapshot: snapshot, size: 28)
            if let chart = snapshot.v2?.chart, chart.isDrawable {
                ChartLine(chart: chart, color: entry.directionColor)
                    .frame(minHeight: 28, maxHeight: 44)
                    .opacity(entry.isStale ? 0.5 : 1)
            }
            Spacer(minLength: 0)
            if let line = entry.ageLine {
                Text(line)
                    .font(Fonts.regular(11))
                    .foregroundColor(.portySecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.a11yLabel)
    }

    @ViewBuilder
    private var right: some View {
        if let block = snapshot.v2 {
            let pick = FeedPicker.medium(block, nowMs: entry.nowMs, cursor: entry.cursor)
            VStack(alignment: .leading, spacing: 6) {
                if let item = pick.item {
                    MediumItem(entry: entry, block: block, item: item, showNext: pick.showNext)
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        ItemIcon(icon: "news", kind: "news")
                        Text(pick.hiddenCount.map { hiddenCountText($0, block.labels) }
                             ?? block.labels.noNews ?? "")
                            .font(Fonts.medium(12))
                            .foregroundColor(.portyPrimary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                if let q = pick.question {
                    QuestionChip(q: q, size: "medium", age: entry.ageMinutes, minHeight: 30)
                }
            }
        } else {
            Text(legacyNote())
                .font(Fonts.regular(12))
                .foregroundColor(.portySecondary)
                .lineLimit(4)
        }
    }
}

/// Ítem actual del mediano: ícono + ticker + (botón siguiente), meta y título a 2 líneas.
private struct MediumItem: View {
    let entry: PortyEntry
    let block: V2Block
    let item: FeedItem
    let showNext: Bool
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        let seg = FeedPicker.seg(item, nowMs: entry.nowMs)
        let age = item.publishedAt.flatMap {
            FeedAge.text(sinceMs: $0, nowMs: entry.nowMs, labels: block.labels)
        }
        let redacted = redaction.contains(.privacy)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ItemIcon(icon: item.icon, kind: item.kind)
                if let tag = item.tag, !tag.isEmpty { TickerTag(text: tag) }
                Spacer(minLength: 0)
                if showNext { NextButton(label: block.labels.nextA11y ?? block.labels.next ?? "") }
            }
            Link(destination: itemURL(
                item, nowMs: entry.nowMs, size: "medium", rank: 1, age: entry.ageMinutes)) {
                VStack(alignment: .leading, spacing: 2) {
                    if redacted {
                        Text(block.labels.redacted ?? "")
                            .font(Fonts.regular(12))
                            .foregroundColor(.portySecondary)
                            .lineLimit(2)
                    } else {
                        Group {
                            Text(FeedAge.resolve(seg.meta, age: age) ?? "")
                                .font(Fonts.regular(11))
                                .foregroundColor(.portySecondary)
                                .lineLimit(1)
                            Text(FeedAge.resolve(seg.title, age: age) ?? "")
                                .font(Fonts.medium(12))
                                .foregroundColor(.portyPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                        }
                        .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                redacted
                    ? (block.labels.redacted ?? "")
                    : (FeedAge.resolve(item.a11y ?? seg.title, age: age) ?? ""))
        }
    }
}

// MARK: - Grande

private struct LargeReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let block = snapshot.v2 {
                let pick = FeedPicker.large(block, nowMs: entry.nowMs)
                list(block: block, pick: pick)
                if !pick.questions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(pick.questions.enumerated()), id: \.offset) { _, q in
                            QuestionChip(q: q, size: "large", age: entry.ageMinutes, minHeight: 28)
                        }
                    }
                }
            } else {
                Text(legacyNote())
                    .font(Fonts.regular(12))
                    .foregroundColor(.portySecondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Cara + encabezado con la cantidad de novedades + "hace X"; abajo, % y gráfico.
    private var header: some View {
        let block = snapshot.v2
        let headerText: String? = block.map { (b: V2Block) -> String in
            let n = FeedPicker.large(b, nowMs: entry.nowMs).headerN
            switch n {
            case 0: return b.labels.headerNone ?? ""
            case 1: return b.labels.headerOne ?? ""
            default:
                return (b.labels.headerOther ?? "")
                    .replacingOccurrences(of: "{n}", with: String(n))
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                FaceView(mood: entry.mood, side: 24)
                if let text = headerText {
                    Text(text)
                        .font(Fonts.semibold(13))
                        .foregroundColor(.portyPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let period = entry.periodText {
                    Text(period)
                        .font(Fonts.medium(12))
                        .foregroundColor(.portySecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let line = entry.ageLine {
                    Text(line)
                        .font(Fonts.regular(11))
                        .foregroundColor(.portySecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    PctText(entry: entry, snapshot: snapshot, size: 30)
                    if block != nil, let period = entry.periodText {
                        Text(period)
                            .font(Fonts.medium(11))
                            .foregroundColor(.portySecondary)
                            .lineLimit(1)
                    }
                }
                if let chart = block?.chart, chart.isDrawable {
                    ChartLine(chart: chart, color: entry.directionColor)
                        .frame(height: 44)
                        .opacity(entry.isStale ? 0.5 : 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.a11yLabel)
    }

    @ViewBuilder
    private func list(block: V2Block, pick: LargePick) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = block.labels.listTitle {
                Text(title)
                    .font(Fonts.medium(12))
                    .foregroundColor(.portySecondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 0) {
                if block.positionsHidden || pick.rows.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        ItemIcon(icon: "news", kind: "news")
                        Text(pick.hiddenCount.map { hiddenCountText($0, block.labels) }
                             ?? block.labels.noNews ?? "")
                            .font(Fonts.medium(12))
                            .foregroundColor(
                                pick.hiddenCount == nil ? .portySecondary : .portyPrimary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(pick.rows.enumerated()), id: \.offset) { index, item in
                        if index > 0 { HairlineDivider() }
                        LargeRow(entry: entry, block: block, item: item, rank: index + 1)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Fila del grande: ícono, ticker, título (1 línea) y meta. Un toque abre el ítem.
private struct LargeRow: View {
    let entry: PortyEntry
    let block: V2Block
    let item: FeedItem
    let rank: Int
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        let seg = FeedPicker.seg(item, nowMs: entry.nowMs)
        let age = item.publishedAt.flatMap {
            FeedAge.text(sinceMs: $0, nowMs: entry.nowMs, labels: block.labels)
        }
        let redacted = redaction.contains(.privacy)
        Link(destination: itemURL(
            item, nowMs: entry.nowMs, size: "large", rank: rank, age: entry.ageMinutes)) {
            HStack(alignment: .center, spacing: 8) {
                ItemIcon(icon: item.icon, kind: item.kind)
                if redacted {
                    Text(block.labels.redacted ?? "")
                        .font(Fonts.regular(12))
                        .foregroundColor(.portySecondary)
                        .lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            if let tag = item.tag, !tag.isEmpty { TickerTag(text: tag) }
                            Text(FeedAge.resolve(seg.title, age: age) ?? "")
                                .font(Fonts.medium(12))
                                .foregroundColor(.portyPrimary)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                        Text(FeedAge.resolve(seg.meta, age: age) ?? "")
                            .font(Fonts.regular(11))
                            .foregroundColor(.portySecondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            redacted
                ? (block.labels.redacted ?? "")
                : (FeedAge.resolve(item.a11y ?? seg.title, age: age) ?? ""))
    }
}

// MARK: - Sin datos

/// signed_out / no_portfolio / sin snapshot: Porty + el mensaje.
private struct MessageView: View {
    let entry: PortyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceView(mood: "neutral", side: family == .systemSmall ? 30 : 36)
            Text(entry.messageText)
                .font(Fonts.medium(family == .systemSmall ? 13 : 15))
                .foregroundColor(.portyPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.messageText)
    }
}

// MARK: - Previews (datos ficticios, sin montos)

struct PortyWidgetPreviews: PreviewProvider {
    static var previews: some View {
        let now = Date()
        var hidden = WidgetSnapshot.sample(now: now)
        hidden.v2?.positionsHidden = true
        return Group {
            ForEach([WidgetFamily.systemSmall, .systemMedium, .systemLarge], id: \.self) { family in
                PortyWidgetView(entry: PortyEntry(date: now, snapshot: .sample(now: now)))
                    .previewContext(WidgetPreviewContext(family: family))
                PortyWidgetView(entry: PortyEntry(date: now, snapshot: .sample(now: now)))
                    .previewContext(WidgetPreviewContext(family: family))
                    .environment(\.colorScheme, .dark)
                PortyWidgetView(entry: PortyEntry(date: now, snapshot: hidden))
                    .previewContext(WidgetPreviewContext(family: family))
            }
        }
    }
}
