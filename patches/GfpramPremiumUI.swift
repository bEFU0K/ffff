import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import ItemListUI
import SwiftSignalKit

// MARK: - Значки

private var gfpramPremiumImageCache: UIImage?

/// Золотой значок «#» — значок GFPGRAM Premium.
public func gfpramPremiumImage() -> UIImage? {
    if let image = gfpramPremiumImageCache {
        return image
    }
    guard let data = Data(base64Encoded: gfpramPremiumImageBase64, options: .ignoreUnknownCharacters), let image = UIImage(data: data, scale: 2.0) else {
        return nil
    }
    gfpramPremiumImageCache = image
    return image
}

private func gfpramTileIcon(symbol: String, color: UIColor) -> UIImage {
    let size = CGSize(width: 30.0, height: 30.0)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        color.setFill()
        UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: 7.0).fill()
        let configuration = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold)
        if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let rect = CGRect(x: (size.width - glyph.size.width) / 2.0, y: (size.height - glyph.size.height) / 2.0, width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: rect)
        }
    }
}

private func gfpramPremiumTileIcon() -> UIImage? {
    guard let source = gfpramPremiumImage() else {
        return nil
    }
    let size = CGSize(width: 30.0, height: 30.0)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        UIColor(white: 0.08, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: 7.0).fill()
        source.draw(in: CGRect(x: 3.0, y: 3.0, width: 24.0, height: 24.0))
    }
}

private var gfpramIconCache: [Int32: UIImage] = [:]

/// Иконки строк: 100 — золотой «#» (Premium), 101 — тех-поддержка, 1...9 — функции Premium.
public func gfpramFeatureIcon(_ code: Int32) -> UIImage? {
    if let image = gfpramIconCache[code] {
        return image
    }
    let image: UIImage?
    switch code {
    case 100:
        image = gfpramPremiumTileIcon()
    case 101:
        image = gfpramTileIcon(symbol: "lifepreserver.fill", color: UIColor(rgb: 0x32ade6))
    case 1:
        image = gfpramTileIcon(symbol: "paperplane.fill", color: UIColor(rgb: 0xf29c38))
    case 2:
        image = gfpramTileIcon(symbol: "at", color: UIColor(rgb: 0x9472fd))
    case 3:
        image = gfpramTileIcon(symbol: "lock.shield.fill", color: UIColor(rgb: 0x34c759))
    case 4:
        image = gfpramTileIcon(symbol: "star.fill", color: UIColor(rgb: 0xf9b004))
    case 5:
        image = gfpramTileIcon(symbol: "arrowshape.turn.up.left.fill", color: UIColor(rgb: 0x3e88f7))
    case 6:
        image = gfpramTileIcon(symbol: "text.bubble.fill", color: UIColor(rgb: 0xe26bd3))
    case 7:
        image = gfpramTileIcon(symbol: "tray.and.arrow.down.fill", color: UIColor(rgb: 0x2dc7c0))
    case 8:
        image = gfpramTileIcon(symbol: "heart.fill", color: UIColor(rgb: 0xff4d5e))
    case 9:
        image = gfpramTileIcon(symbol: "list.bullet", color: UIColor(rgb: 0x6a6cf0))
    case 10:
        image = gfpramTileIcon(symbol: "square.grid.2x2.fill", color: UIColor(rgb: 0xff9f0a))
    default:
        image = nil
    }
    if let image = image {
        gfpramIconCache[code] = image
    }
    return image
}

// MARK: - Шапка окон (иконка, заголовок, описание)
// Шапка — обычная строка списка (первая). Раньше это был ItemListControllerHeaderItem: его положение зависит от высоты навигации,
// из-за чего иконка уезжала под статус-бар, а текст — слишком высоко. Строка списка всегда стоит ровно под навигацией.

/// Что рисовать вверху окна.
enum GfpramHeaderIcon {
    /// Просто картинка (золотой значок «#»)
    case image(UIImage?)
    /// Квадратная иконка с закруглением
    case tile(UIImage?)
    /// Иконки, плавно сменяющие друг друга
    case carousel([String])
    /// Без иконки
    case none

    var identity: String {
        switch self {
        case let .image(image):
            return "image-\(image.map { ObjectIdentifier($0).hashValue } ?? 0)"
        case let .tile(image):
            return "tile-\(image.map { ObjectIdentifier($0).hashValue } ?? 0)"
        case let .carousel(keys):
            return "carousel-" + keys.joined(separator: ",")
        case .none:
            return "none"
        }
    }
}

final class GfpramPremiumHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let text: String
    let icon: GfpramHeaderIcon
    let locked: Bool
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, title: String, text: String, icon: GfpramHeaderIcon? = nil, locked: Bool = false, sectionId: ItemListSectionId = 0) {
        self.theme = theme
        self.title = title
        self.text = text
        self.icon = icon ?? .carousel(gfpramPremiumIconKeys)
        self.locked = locked
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = GfpramPremiumHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? GfpramPremiumHeaderItemNode {
                let layoutAndApply = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = layoutAndApply(self, params)
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

final class GfpramPremiumHeaderItemNode: ListViewItemNode {
    private let titleNode = ImmediateTextNode()
    private let textNode = ImmediateTextNode()
    private let imageView = UIImageView()
    private let carouselView = GfpramIconCarouselView(frame: CGRect())

    private var item: GfpramPremiumHeaderItem?
    private var iconSide: CGFloat = 0.0

    init() {
        super.init(layerBacked: false)

        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.maximumNumberOfLines = 0
        self.textNode.isUserInteractionEnabled = false
        self.textNode.maximumNumberOfLines = 0
        self.imageView.contentMode = .scaleAspectFit

        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
    }

    override func didLoad() {
        super.didLoad()

        self.view.addSubview(self.imageView)
        self.view.addSubview(self.carouselView)
    }

    private static func iconSide(for icon: GfpramHeaderIcon) -> CGFloat {
        switch icon {
        case .image, .carousel:
            return 116.0
        case .tile:
            return 96.0
        case .none:
            return 0.0
        }
    }

    private static func measure(_ string: String, font: UIFont, width: CGFloat) -> CGFloat {
        let rect = (string as NSString).boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return ceil(rect.height)
    }

    func asyncLayout() -> (_ item: GfpramPremiumHeaderItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params in
            let sideInset: CGFloat = 28.0 + max(params.leftInset, params.rightInset)
            let textWidth = max(10.0, params.width - sideInset * 2.0)
            let side = GfpramPremiumHeaderItemNode.iconSide(for: item.icon)
            let topPadding: CGFloat = 12.0
            let titleHeight = GfpramPremiumHeaderItemNode.measure(item.title, font: Font.semibold(26.0), width: textWidth)
            let textHeight = GfpramPremiumHeaderItemNode.measure(item.text, font: Font.regular(15.0), width: textWidth)
            var height = topPadding
            if side > 0.0 {
                height += side + 16.0
            }
            height += titleHeight + 10.0 + textHeight + 28.0

            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets())

            return (layout, { [weak self] in
                guard let self = self else {
                    return
                }
                self.item = item
                self.iconSide = side

                self.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.semibold(26.0), textColor: item.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
                self.textNode.attributedText = NSAttributedString(string: item.text, font: Font.regular(15.0), textColor: item.theme.list.freeTextColor, paragraphAlignment: .center)

                switch item.icon {
                case let .image(image):
                    self.imageView.isHidden = false
                    self.carouselView.isHidden = true
                    self.imageView.image = image ?? gfpramPremiumImage()
                    self.imageView.contentMode = .scaleAspectFit
                    self.imageView.layer.cornerRadius = 0.0
                    self.imageView.clipsToBounds = false
                case let .tile(image):
                    self.imageView.isHidden = false
                    self.carouselView.isHidden = true
                    self.imageView.image = image
                    self.imageView.contentMode = .scaleAspectFill
                    self.imageView.layer.cornerRadius = side * 0.23
                    self.imageView.clipsToBounds = true
                case let .carousel(keys):
                    self.imageView.isHidden = true
                    self.carouselView.isHidden = false
                    self.carouselView.configure(keys: keys, locked: item.locked)
                case .none:
                    self.imageView.isHidden = true
                    self.carouselView.isHidden = true
                }

                let constrained = CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
                let titleSize = self.titleNode.updateLayout(constrained)
                let textSize = self.textNode.updateLayout(constrained)

                var y = topPadding
                if side > 0.0 {
                    let iconFrame = CGRect(x: floor((params.width - side) / 2.0), y: y, width: side, height: side)
                    self.imageView.frame = iconFrame
                    self.carouselView.frame = iconFrame
                    y += side + 16.0
                }
                self.titleNode.frame = CGRect(origin: CGPoint(x: floor((params.width - titleSize.width) / 2.0), y: y), size: titleSize)
                y += titleSize.height + 10.0
                self.textNode.frame = CGRect(origin: CGPoint(x: floor((params.width - textSize.width) / 2.0), y: y), size: textSize)
            })
        }
    }
}
