import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class GfpramEditArguments {
    let copy: (String) -> Void

    init(copy: @escaping (String) -> Void) {
        self.copy = copy
    }
}

private enum GfpramEditEntry: ItemListNodeEntry {
    case version(Int32, String, String, String?)
    case footer(Int32, String)
    case hero(Int32, String, String)

    var entryId: Int32 {
        switch self {
        case let .hero(entryId, _, _):
            return entryId
        case let .version(entryId, _, _, _):
            return entryId
        case let .footer(entryId, _):
            return entryId
        }
    }

    var section: ItemListSectionId {
        if self.entryId < 0 {
            return -1
        }
        return self.entryId / 1000
    }

    var stableId: Int32 {
        return self.entryId
    }

    static func <(lhs: GfpramEditEntry, rhs: GfpramEditEntry) -> Bool {
        return lhs.entryId < rhs.entryId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GfpramEditArguments
        switch self {
        case let .hero(_, title, text):
            return GfpramPremiumHeaderItem(theme: presentationData.theme, title: title, text: text, icon: GfpramHeaderIcon.none, locked: false, sectionId: self.section)
        case let .version(_, title, text, badge):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: title, titleBadge: badge, label: text, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: ItemListDisclosureStyle.none, action: {
                arguments.copy(text)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func gfpramEditDateString(_ timestamp: Double) -> String {
    if timestamp <= 0 {
        return "ранее"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM, HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

/// Отдельное окно со всеми вариантами изменённого сообщения: сверху оригинал, дальше правки по порядку, внизу — текущая версия.
public func gfpramEditHistoryController(context: AccountContext, messageText: String, editDate: Int32?, entries: [AyuEditEntry]) -> ViewController {
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramEditArguments(copy: { text in
        UIPasteboard.general.string = text
        presentImpl?(gfpramAlert(context: context, title: nil, text: "Текст версии скопирован"))
    })

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var list: [GfpramEditEntry] = []
        var index: Int32 = 0
        for (position, entry) in entries.enumerated() {
            if position == 0 {
                list.append(.version(1000 + index, "Оригинал", entry.text, nil))
            } else {
                list.append(.version(1000 + index, "Версия \(position) · " + gfpramEditDateString(entries[position - 1].date), entry.text, nil))
            }
            index += 1
        }
        var currentDate: Double = 0.0
        if let editDate = editDate {
            currentDate = Double(editDate)
        } else if let last = entries.last {
            currentDate = last.date
        }
        let currentTitle = entries.isEmpty ? "Текст сообщения" : "Сейчас · " + gfpramEditDateString(currentDate)
        list.append(.version(1000 + index, currentTitle, messageText, "СЕЙЧАС"))
        list.append(.footer(9000, "Нажмите на версию, чтобы скопировать её текст. История хранится на устройстве и остаётся после обновления клиента."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(""), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let headerText = entries.isEmpty ? "Для этого сообщения сохранённых правок нет." : "Все варианты сообщения: от оригинала до текущего. Правок: \(entries.count)."
        list.insert(.hero(-1, "История изменений", headerText), at: 0)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: list, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
