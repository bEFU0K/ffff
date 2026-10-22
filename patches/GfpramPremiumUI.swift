import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import ItemListUI

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

// MARK: - Шапка окна Premium (как в Telegram Premium)

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

final class GfpramPremiumHeaderItem: ItemListControllerHeaderItem {
    let theme: PresentationTheme
    let title: String
    let text: String
    let icon: GfpramHeaderIcon
    let locked: Bool

    init(theme: PresentationTheme, title: String, text: String, icon: GfpramHeaderIcon? = nil, locked: Bool = false) {
        self.theme = theme
        self.title = title
        self.text = text
        self.icon = icon ?? .carousel(gfpramPremiumIconKeys)
        self.locked = locked
    }

    func isEqual(to: ItemListControllerHeaderItem) -> Bool {
        if let item = to as? GfpramPremiumHeaderItem {
            return self.theme === item.theme && self.title == item.title && self.text == item.text && self.icon.identity == item.icon.identity && self.locked == item.locked
        } else {
            return false
        }
    }

    func node(current: ItemListControllerHeaderItemNode?) -> ItemListControllerHeaderItemNode {
        if let current = current as? GfpramPremiumHeaderItemNode {
            current.item = self
            return current
        } else {
            return GfpramPremiumHeaderItemNode(item: self)
        }
    }
}

final class GfpramPremiumHeaderItemNode: ItemListControllerHeaderItemNode {
    private let titleNode = ImmediateTextNode()
    private let textNode = ImmediateTextNode()
    private let imageView = UIImageView()
    private let carouselView = GfpramIconCarouselView(frame: CGRect())

    private var validLayout: ContainerViewLayout?
    private var titleSize = CGSize()
    private var textSize = CGSize()
    private var scrollOffset: CGFloat = 0.0
    private var iconSide: CGFloat = 116.0

    var item: GfpramPremiumHeaderItem {
        didSet {
            self.updateItem()
            if let layout = self.validLayout {
                let _ = self.updateLayout(layout: layout, transition: .immediate)
            }
        }
    }

    init(item: GfpramPremiumHeaderItem) {
        self.item = item

        super.init()

        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.maximumNumberOfLines = 0
        self.textNode.isUserInteractionEnabled = false
        self.textNode.maximumNumberOfLines = 0
        self.imageView.contentMode = .scaleAspectFit

        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)

        self.updateItem()
    }

    override func didLoad() {
        super.didLoad()

        self.view.addSubview(self.imageView)
        self.view.addSubview(self.carouselView)
    }

    private func updateItem() {
        self.titleNode.attributedText = NSAttributedString(string: self.item.title, font: Font.semibold(26.0), textColor: self.item.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.textNode.attributedText = NSAttributedString(string: self.item.text, font: Font.regular(15.0), textColor: self.item.theme.list.freeTextColor, paragraphAlignment: .center)

        switch self.item.icon {
        case let .image(image):
            self.iconSide = 116.0
            self.imageView.isHidden = false
            self.carouselView.isHidden = true
            self.imageView.image = image ?? gfpramPremiumImage()
            self.imageView.contentMode = .scaleAspectFit
            self.imageView.layer.cornerRadius = 0.0
            self.imageView.clipsToBounds = false
        case let .tile(image):
            self.iconSide = 96.0
            self.imageView.isHidden = false
            self.carouselView.isHidden = true
            self.imageView.image = image
            self.imageView.contentMode = .scaleAspectFill
            self.imageView.layer.cornerRadius = self.iconSide * 0.23
            self.imageView.clipsToBounds = true
        case let .carousel(keys):
            self.iconSide = 116.0
            self.imageView.isHidden = true
            self.carouselView.isHidden = false
            self.carouselView.configure(keys: keys, locked: self.item.locked)
        case .none:
            self.iconSide = 0.0
            self.imageView.isHidden = true
            self.carouselView.isHidden = true
        }
    }

    private func updateFrames() {
        guard let layout = self.validLayout else {
            return
        }
        let width = layout.size.width
        let offset = self.scrollOffset
        let side = self.iconSide
        let iconFrame = CGRect(x: floor((width - side) / 2.0), y: 28.0 - offset, width: side, height: side)
        self.imageView.frame = iconFrame
        self.carouselView.frame = iconFrame
        let titleY = side > 0.0 ? 28.0 + side + 14.0 : 24.0
        self.titleNode.frame = CGRect(origin: CGPoint(x: floor((width - self.titleSize.width) / 2.0), y: titleY - offset), size: self.titleSize)
        self.textNode.frame = CGRect(origin: CGPoint(x: floor((width - self.textSize.width) / 2.0), y: titleY + self.titleSize.height + 10.0 - offset), size: self.textSize)
    }

    override func updateContentOffset(_ contentOffset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.scrollOffset = contentOffset
        self.updateFrames()
    }

    override func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        let sideInset: CGFloat = 28.0
        let constrainedSize = CGSize(width: layout.size.width - sideInset * 2.0, height: CGFloat.greatestFiniteMagnitude)
        self.titleSize = self.titleNode.updateLayout(constrainedSize)
        self.textSize = self.textNode.updateLayout(constrainedSize)
        self.validLayout = layout
        self.updateFrames()
        return (self.iconSide > 0.0 ? 28.0 + self.iconSide + 14.0 : 24.0) + self.titleSize.height + 10.0 + self.textSize.height + 24.0
    }
}
