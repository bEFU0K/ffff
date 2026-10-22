import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - Список иконок приложения

struct GfpramAppIcon {
    /// Ключ превью в gfpramIconPreviews
    let key: String
    /// Имя альтернативной иконки (nil — основная)
    let name: String?
    let title: String
    let premium: Bool
}

let gfpramAppIcons: [GfpramAppIcon] = [
    GfpramAppIcon(key: "main", name: nil, title: "Основная", premium: false),
    GfpramAppIcon(key: "red", name: "GfpRed", title: "Красная", premium: false),
    GfpramAppIcon(key: "black", name: "GfpBlack", title: "Чёрная", premium: false),
    GfpramAppIcon(key: "anime", name: "GfpAnime", title: "Аниме", premium: false),
    GfpramAppIcon(key: "ocean", name: "GfpOcean", title: "Океан", premium: false),
    GfpramAppIcon(key: "sponge", name: "GfpSponge", title: "Губка Боб", premium: false),
    GfpramAppIcon(key: "gold", name: "GfpGold", title: "Золото", premium: true),
    GfpramAppIcon(key: "turbo", name: "GfpTurbo", title: "Турбо", premium: true),
    GfpramAppIcon(key: "night", name: "GfpNight", title: "Лунная ночь", premium: true),
    GfpramAppIcon(key: "duck", name: "GfpDuck", title: "Утёнок", premium: true)
]

let gfpramPremiumIconKeys: [String] = ["gold", "turbo", "night", "duck"]

private var gfpramPreviewCache: [String: UIImage] = [:]

/// Превью иконки (встроено в приложение, не зависит от того, как iOS хранит альтернативные иконки).
func gfpramIconPreview(_ key: String) -> UIImage? {
    if let image = gfpramPreviewCache[key] {
        return image
    }
    guard let base64 = gfpramIconPreviews[key], let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), let image = UIImage(data: data, scale: 2.0) else {
        return nil
    }
    gfpramPreviewCache[key] = image
    return image
}

private var gfpramTileCache: [String: UIImage] = [:]

/// Квадратик с закруглением для строки списка; для закрытых иконок затемнён и с замком.
func gfpramIconTile(key: String, side: CGFloat, locked: Bool) -> UIImage? {
    let cacheKey = "\(key)-\(Int(side))-\(locked)"
    if let image = gfpramTileCache[cacheKey] {
        return image
    }
    guard let source = gfpramIconPreview(key) else {
        return nil
    }
    let size = CGSize(width: side, height: side)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
        let rect = CGRect(origin: CGPoint(), size: size)
        UIBezierPath(roundedRect: rect, cornerRadius: side * 0.23).addClip()
        source.draw(in: rect)
        if locked {
            UIColor(white: 0.0, alpha: 0.45).setFill()
            UIRectFill(rect)
            let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .bold)
            if let glyph = UIImage(systemName: "lock.fill", withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(in: CGRect(x: (size.width - glyph.size.width) / 2.0, y: (size.height - glyph.size.height) / 2.0, width: glyph.size.width, height: glyph.size.height))
            }
        }
    }
    gfpramTileCache[cacheKey] = image
    return image
}

// MARK: - Плавно меняющиеся иконки (шапка окна Premium)

final class GfpramIconCarouselView: UIView {
    private let imageView = UIImageView()
    private let lockBackground = UIView()
    private let lockView = UIImageView()
    private var keys: [String] = []
    private var index: Int = 0
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.addSubview(self.imageView)

        self.lockBackground.backgroundColor = UIColor(white: 0.0, alpha: 0.78)
        self.lockBackground.layer.borderColor = UIColor.white.cgColor
        self.lockBackground.layer.borderWidth = 2.0
        self.lockView.contentMode = .center
        self.lockBackground.addSubview(self.lockView)
        self.addSubview(self.lockBackground)

        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.28
        self.layer.shadowRadius = 10.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.timer?.invalidate()
    }

    func configure(keys: [String], locked: Bool) {
        if self.keys != keys {
            self.keys = keys
            self.index = 0
            if let first = keys.first {
                self.imageView.image = gfpramIconPreview(first)
            }
        }
        self.lockBackground.isHidden = !locked
        if self.window != nil {
            self.startTimer()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil {
            self.startTimer()
        } else {
            self.stopTimer()
        }
    }

    private func startTimer() {
        if self.timer != nil || self.keys.count < 2 {
            return
        }
        let timer = Timer(timeInterval: 2.8, repeats: true, block: { [weak self] _ in
            self?.advance()
        })
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func advance() {
        if self.keys.count < 2 {
            return
        }
        self.index = (self.index + 1) % self.keys.count
        guard let next = gfpramIconPreview(self.keys[self.index]) else {
            return
        }
        UIView.transition(with: self.imageView, duration: 0.9, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
            self.imageView.image = next
        }, completion: nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
        self.imageView.layer.cornerRadius = self.bounds.width * 0.23
        let diameter = floor(self.bounds.width * 0.32)
        self.lockBackground.frame = CGRect(x: self.bounds.width - diameter + 4.0, y: self.bounds.height - diameter + 4.0, width: diameter, height: diameter)
        self.lockBackground.layer.cornerRadius = diameter / 2.0
        self.lockView.frame = self.lockBackground.bounds
        let configuration = UIImage.SymbolConfiguration(pointSize: diameter * 0.46, weight: .bold)
        self.lockView.image = UIImage(systemName: "lock.fill", withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal)
    }
}

// MARK: - Окно «Иконка приложения»

private final class GfpramIconArguments {
    let select: (Int32) -> Void

    init(select: @escaping (Int32) -> Void) {
        self.select = select
    }
}

private enum GfpramIconEntry: ItemListNodeEntry {
    case header(Int32, String)
    case icon(Int32, Int32, Bool, Bool)
    case footer(Int32, String)

    var entryId: Int32 {
        switch self {
        case let .header(entryId, _):
            return entryId
        case let .icon(entryId, _, _, _):
            return entryId
        case let .footer(entryId, _):
            return entryId
        }
    }

    var section: ItemListSectionId {
        return self.entryId / 100
    }

    var stableId: Int32 {
        return self.entryId
    }

    static func <(lhs: GfpramIconEntry, rhs: GfpramIconEntry) -> Bool {
        return lhs.entryId < rhs.entryId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GfpramIconArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .icon(_, index, locked, selected):
            let icon = gfpramAppIcons[Int(index)]
            let label: String
            if locked {
                label = "🔒 Доступно с GFPGRAM Premium"
            } else if icon.premium {
                label = "Эксклюзив Premium"
            } else {
                label = "Бесплатная"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: gfpramIconTile(key: icon.key, side: 30.0, locked: locked), title: icon.title, titleBadge: selected ? "СЕЙЧАС" : nil, label: label, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: ItemListDisclosureStyle.none, action: {
                arguments.select(index)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func gfpramIconEntries() -> [GfpramIconEntry] {
    let current = UIApplication.shared.alternateIconName
    let unlocked = AyuPremium.isActive
    var entries: [GfpramIconEntry] = []
    entries.append(.header(0, "ОБЫЧНЫЕ ИКОНКИ"))
    var freeId: Int32 = 1
    var premiumId: Int32 = 101
    var index: Int32 = 0
    for icon in gfpramAppIcons where !icon.premium {
        let selected = icon.name == current || (icon.name == nil && current == "BlueIcon")
        entries.append(.icon(freeId, index, false, selected))
        freeId += 1
        index += 1
    }
    entries.append(.footer(freeId, "Иконка меняется сразу. iOS покажет системное уведомление о смене иконки."))
    entries.append(.header(100, "PREMIUM-ИКОНКИ"))
    for icon in gfpramAppIcons where icon.premium {
        let selected = icon.name == current
        entries.append(.icon(premiumId, index, !unlocked, selected))
        premiumId += 1
        index += 1
    }
    entries.append(.footer(premiumId, unlocked ? "Подписка активна: все четыре эксклюзивные иконки доступны." : "Эти четыре иконки доступны только с GFPGRAM Premium. Нажмите на любую, чтобы открыть окно подписки."))
    return entries
}

public func gfpramIconsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramIconArguments(select: { index in
        let icon = gfpramAppIcons[Int(index)]
        if icon.premium && !AyuPremium.isActive {
            presentImpl?(gfpramAlert(context: context, title: "Иконка «\(icon.title)» — только для Premium", text: "Четыре эксклюзивные иконки (Золото, Турбо, Лунная ночь и Утёнок) доступны с подпиской GFPGRAM Premium за \(AyuPremium.price) в месяц.", actions: [
                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                TextAlertAction(type: .defaultAction, title: "Открыть Premium", action: {
                    pushImpl?(gfpramPremiumController(context: context))
                })
            ]))
            return
        }
        UIApplication.shared.setAlternateIconName(icon.name, completionHandler: { error in
            DispatchQueue.main.async {
                if error != nil {
                    presentImpl?(gfpramAlert(context: context, title: nil, text: "Не удалось сменить иконку. Попробуйте ещё раз."))
                } else {
                    AyuIconKeeper.remember(name: icon.name, premium: icon.premium)
                }
                refresh.set(true)
            }
        })
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(""), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let header = GfpramPremiumHeaderItem(theme: presentationData.theme, title: "Иконка приложения", text: "Выберите иконку GFPGRAM. Значок замка — иконка доступна только с Premium.", icon: .carousel(gfpramPremiumIconKeys), locked: !AyuPremium.isActive)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramIconEntries(), style: .blocks, headerItem: header, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
