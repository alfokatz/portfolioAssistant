//
//  PortyWidgetViews.swift
//  PortyWidget
//
//  Vistas chico/mediano/grande. Paleta de DESIGN.md (assets con variante oscura),
//  cifras tabulares, sin número gigante. `.privacySensitive()` en valor,
//  variación, % y frase; en las novedades, ticker, titular y fuente.
//

import WidgetKit
import SwiftUI

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

// MARK: - Helpers de texto

private func appURL(target: String, size: String, extra: String = "", age: Int? = nil) -> URL {
    var s = "porty-widget://open?homeWidget&target=\(target)&size=\(size)"
    if !extra.isEmpty { s += "&\(extra)" }
    if let age { s += "&age=\(age)" }
    return URL(string: s)!
}

extension PortyEntry {
    /// Minutos desde `data_as_of` hasta la hora de esta entrada.
    var ageMinutes: Int? {
        guard let asOf = snapshot?.dataAsOfDate else { return nil }
        return max(0, Int(date.timeIntervalSince(asOf) / 60))
    }

    var updatedText: String? {
        guard let labels = snapshot?.labels, let minutes = ageMinutes else { return nil }
        let template: String?
        let n: Int
        if minutes < 1 { template = labels.updatedNow; n = 0 }
        else if minutes < 60 { template = labels.updatedMin; n = minutes }
        else if minutes < 60 * 24 { template = labels.updatedH; n = minutes / 60 }
        else { template = labels.updatedD; n = minutes / (60 * 24) }
        return template?.replacingOccurrences(of: "{n}", with: String(n))
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

    /// Un solo texto para VoiceOver. Con montos ocultos nunca lee números.
    var a11yLabel: String {
        guard let s = snapshot, s.isReady else { return messageText }
        var parts: [String] = []
        if s.hidden {
            parts.append(s.labels?.hiddenA11y ?? "")
        } else if let v = s.a11yValue {
            parts.append(v)
        }
        if let p = periodText { parts.append(p) }
        if let u = updatedText { parts.append(u) }
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
        .widgetURL(entry.snapshot?.isReady == true
            ? appURL(target: "chat", size: size, age: entry.ageMinutes)
            : appURL(target: entry.emptyTarget, size: size, age: entry.ageMinutes))
    }
}

// MARK: - Piezas

private struct AvatarView: View {
    let side: CGFloat
    var body: some View {
        Image("PortyAvatar")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Valor + variación + período + "hace X". Un solo elemento de accesibilidad.
private struct ValueBlock: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot
    let totalSize: CGFloat

    var body: some View {
        let hidden = snapshot.hidden
        let dim: Double = entry.isStale ? 0.5 : 1
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AvatarView(side: 22)
                if let period = entry.periodText {
                    Text(period)
                        .font(Fonts.medium(12))
                        .foregroundColor(.portySecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            Text(hidden ? (snapshot.labels?.hiddenAmount ?? "••••") : (snapshot.totalText ?? ""))
                .font(Fonts.semibold(totalSize))
                .monospacedDigit()
                .foregroundColor(.portyPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
                .opacity(dim)
            HStack(spacing: 6) {
                if !hidden, let change = snapshot.changeText {
                    Text(change)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                }
                Text(snapshot.changePctText ?? "")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
            }
            .font(Fonts.medium(13))
            .monospacedDigit()
            .foregroundColor(entry.directionColor)
            .opacity(dim)
            if let updated = entry.updatedText {
                Text(updated)
                    .font(Fonts.regular(11))
                    .foregroundColor(.portySecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.a11yLabel)
    }
}

private struct SmallReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot
    var body: some View {
        ValueBlock(entry: entry, snapshot: snapshot, totalSize: 24)
    }
}

private struct MediumReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        let age = entry.ageMinutes
        HStack(alignment: .top, spacing: 16) {
            ValueBlock(entry: entry, snapshot: snapshot, totalSize: 24)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                if let item = entry.mediumItem {
                    ItemRow(entry: entry, item: item, size: "medium", headlineLines: 2)
                } else if let teaser = entry.mediumTeaser {
                    TeaserRow(entry: entry, teaser: teaser, size: "medium")
                } else {
                    Text((entry.isStale ? snapshot.phraseStale : snapshot.phrase) ?? "")
                        .font(Fonts.regular(12))
                        .foregroundColor(.portyPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .privacySensitive()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                ForEach(snapshot.questions ?? [], id: \.id) { q in
                    Link(destination: appURL(
                        target: "question", size: "medium", extra: "q=\(q.id)", age: age)) {
                        Text(q.text)
                            .font(Fonts.medium(12))
                            .foregroundColor(.portyPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .background(Color.widgetInset)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Noticia o resultado: un toque abre la hoja de la app con ese ítem. Ticker,
/// titular, fuente y texto de resultados son `.privacySensitive()`; con el
/// sistema redactando se ve el texto aprobado en lugar de los datos.
private struct ItemRow: View {
    let entry: PortyEntry
    let item: ResolvedItem
    let size: String
    let headlineLines: Int
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        let redacted = redaction.contains(.privacy)
        Link(destination: appURL(
            target: item.kind, size: size,
            extra: "id=\(item.id)&rank=\(item.rank)", age: entry.ageMinutes)) {
            VStack(alignment: .leading, spacing: 2) {
                if redacted {
                    Text(entry.extras.itemsLabels?.redacted ?? "")
                        .font(Fonts.regular(12))
                        .foregroundColor(.portySecondary)
                        .lineLimit(2)
                } else {
                    Group {
                        if let meta = item.meta {
                            Text(meta)
                                .font(Fonts.regular(11))
                                .foregroundColor(.portySecondary)
                                .lineLimit(1)
                        }
                        Text(item.text)
                            .font(Fonts.medium(12))
                            .foregroundColor(.portyPrimary)
                            .lineLimit(headlineLines)
                            .minimumScaleFactor(0.9)
                    }
                    .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(redacted ? (entry.extras.itemsLabels?.redacted ?? "") : item.a11y)
    }
}

/// Aviso del plan siguiente. En iOS es neutro (sin plan ni pago) y abre la app.
private struct TeaserRow: View {
    let entry: PortyEntry
    let teaser: WidgetTeaser
    let size: String

    var body: some View {
        Link(destination: appURL(
            target: "teaser_\(teaser.kind ?? "news")", size: size, age: entry.ageMinutes)) {
            HStack(spacing: 6) {
                Text(teaser.text ?? "")
                    .font(Fonts.medium(12))
                    .foregroundColor(.portyPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.portySecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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

private struct LargeReadyView: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        let age = entry.ageMinutes
        VStack(alignment: .leading, spacing: 8) {
            LargeHeader(entry: entry, snapshot: snapshot)
            Text((entry.isStale ? snapshot.phraseStale : snapshot.phrase) ?? "")
                .font(Fonts.regular(12))
                .foregroundColor(.portyPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .privacySensitive()
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.hasItemsSection {
                NewsSection(entry: entry)
                HStack(spacing: 8) {
                    ForEach(snapshot.questions ?? [], id: \.id) { q in
                        QuestionChip(q: q, age: age, height: 32)
                    }
                }
            } else {
                // Sin sección (Free sin aviso, solo cripto, snapshot viejo): preguntas grandes.
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    ForEach(snapshot.questions ?? [], id: \.id) { q in
                        QuestionChip(q: q, age: age, height: 44)
                    }
                }
            }
        }
    }
}

private struct QuestionChip: View {
    let q: WidgetQuestion
    let age: Int?
    let height: CGFloat

    var body: some View {
        Link(destination: appURL(
            target: "question", size: "large", extra: "q=\(q.id)", age: age)) {
            Text(q.text)
                .font(Fonts.medium(12))
                .foregroundColor(.portyPrimary)
                .lineLimit(height > 40 ? 2 : 1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .background(Color.widgetInset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// Encabezado del chico en una franja: Porty + período + "hace X", y debajo el
/// valor con la variación. Un solo elemento de accesibilidad.
private struct LargeHeader: View {
    let entry: PortyEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        let hidden = snapshot.hidden
        let dim: Double = entry.isStale ? 0.5 : 1
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AvatarView(side: 22)
                if let period = entry.periodText {
                    Text(period)
                        .font(Fonts.medium(12))
                        .foregroundColor(.portySecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let updated = entry.updatedText {
                    Text(updated)
                        .font(Fonts.regular(11))
                        .foregroundColor(.portySecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hidden ? (snapshot.labels?.hiddenAmount ?? "••••") : (snapshot.totalText ?? ""))
                    .font(Fonts.semibold(24))
                    .monospacedDigit()
                    .foregroundColor(.portyPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
                HStack(spacing: 6) {
                    if !hidden, let change = snapshot.changeText {
                        Text(change)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive()
                    }
                    Text(snapshot.changePctText ?? "")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                }
                .font(Fonts.medium(13))
                .monospacedDigit()
                .foregroundColor(entry.directionColor)
                Spacer(minLength: 0)
            }
            .opacity(dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.a11yLabel)
    }
}

/// "Novedades de tu cartera": hasta 4 filas (el aviso cuenta), líneas finas.
private struct NewsSection: View {
    let entry: PortyEntry

    var body: some View {
        let labels = entry.extras.itemsLabels
        let teaser = entry.visibleTeaser
        let items = Array(entry.resolvedItems.prefix(4 - (teaser == nil ? 0 : 1)))
        let rows = items.count + (teaser == nil ? 0 : 1)
        VStack(alignment: .leading, spacing: 6) {
            if let title = labels?.section {
                Text(title)
                    .font(Fonts.medium(12))
                    .foregroundColor(.portySecondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                // Con poco alto y muchas filas, el titular pasa a una línea.
                let perRow = rows == 0 ? geo.size.height : geo.size.height / CGFloat(rows)
                let lines = perRow >= 46 ? 2 : 1
                VStack(alignment: .leading, spacing: 0) {
                    if rows == 0 {
                        Text(entry.sectionPlaceholder ?? "")
                            .font(Fonts.regular(12))
                            .foregroundColor(.portySecondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { HairlineDivider() }
                        ItemRow(entry: entry, item: item, size: "large", headlineLines: lines)
                            .padding(.vertical, 4)
                            .frame(maxHeight: .infinity)
                    }
                    if let teaser {
                        if !items.isEmpty { HairlineDivider() }
                        TeaserRow(entry: entry, teaser: teaser, size: "large")
                            .padding(.vertical, 4)
                            .frame(maxHeight: .infinity)
                    }
                    if rows > 0 && rows < 4 { Spacer(minLength: 0) }
                }
            }
        }
    }
}

/// signed_out / no_portfolio / sin snapshot: Porty + el mensaje.
private struct MessageView: View {
    let entry: PortyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AvatarView(side: family == .systemSmall ? 30 : 36)
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
