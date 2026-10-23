import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import LocalizedPeerData
import PromptUI

final class GfpramArguments {
    let toggle: (String, Bool) -> Void
    let perform: (Int32) -> Void

    init(toggle: @escaping (String, Bool) -> Void, perform: @escaping (Int32) -> Void) {
        self.toggle = toggle
        self.perform = perform
    }
}

enum GfpramEntry: ItemListNodeEntry {
    case header(Int32, String)
    case toggle(Int32, String, String, Bool)
    case action(Int32, String, String, Int32)
    case iconAction(Int32, String, String, Int32, Int32)
    case feature(Int32, String, String, Int32, Int32, Int32)
    case footer(Int32, String)
    case hero(Int32, String, String)

    var entryId: Int32 {
        switch self {
        case let .hero(entryId, _, _):
            return entryId
        case let .header(entryId, _):
            return entryId
        case let .toggle(entryId, _, _, _):
            return entryId
        case let .action(entryId, _, _, _):
            return entryId
        case let .iconAction(entryId, _, _, _, _):
            return entryId
        case let .feature(entryId, _, _, _, _, _):
            return entryId
        case let .footer(entryId, _):
            return entryId
        }
    }

    var section: ItemListSectionId {
        if self.entryId < 0 {
            return -1
        }
        return self.entryId / 100
    }

    var stableId: Int32 {
        return self.entryId
    }

    static func <(lhs: GfpramEntry, rhs: GfpramEntry) -> Bool {
        return lhs.entryId < rhs.entryId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GfpramArguments
        switch self {
        case let .hero(_, title, text):
            return GfpramPremiumHeaderItem(theme: presentationData.theme, title: title, text: text, icon: .carousel(gfpramPremiumIconKeys), locked: !AyuPremium.isActive, sectionId: self.section)
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, title, key, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggle(key, newValue)
            })
        case let .action(_, title, label, kind):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: title, label: label, labelStyle: .text, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                arguments.perform(kind)
            })
        case let .iconAction(_, title, label, kind, icon):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: gfpramFeatureIcon(icon), title: title, label: label, labelStyle: .text, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                arguments.perform(kind)
            })
        case let .feature(_, title, text, kind, icon, mode):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: gfpramFeatureIcon(icon), title: title, titleBadge: mode == 2 ? "ВКЛ" : nil, label: text, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: mode == 0 ? ItemListDisclosureStyle.arrow : ItemListDisclosureStyle.none, action: {
                arguments.perform(kind)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func gfpramEntries(adminUnlocked: Bool, ownId: Int64, ownPhone: String?, ownUsername: String?) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "АККАУНТ"))
    entries.append(.action(1, "ID", String(ownId), 20))
    entries.append(.action(2, "Страна номера", AyuProfile.country(phone: ownPhone) ?? "не определена", 21))
    if let ownUsername = ownUsername, !ownUsername.isEmpty {
        entries.append(.action(3, "Юзернейм", "@" + ownUsername, 22))
    }
    entries.append(.footer(4, "Нажмите на ID или юзернейм, чтобы скопировать. Страна определяется по коду номера телефона."))
    entries.append(.header(5, "PREMIUM"))
    entries.append(.iconAction(6, "GFPGRAM Premium", AyuPremium.statusText, 3, 100))
    entries.append(.iconAction(7, "Тех-поддержка", "@" + AyuPremium.supportUsername, 4, 101))
    var base: Int32 = 100
    for group in AyuSettings.groups {
        entries.append(.header(base, group.title))
        var index: Int32 = 1
        for toggle in group.toggles {
            entries.append(.toggle(base + index, toggle.title, toggle.key, AyuSettings.value(toggle.key)))
            index += 1
        }
        if !group.footer.isEmpty {
            entries.append(.footer(base + index, group.footer))
        }
        base += 100
    }
    entries.append(.header(base, "ПРИЛОЖЕНИЕ"))
    entries.append(.action(base + 1, "Иконка приложения", "", 0))
    entries.append(.action(base + 4, "Шрифт приложения", AyuSettings.fontFamily.isEmpty ? "Системный" : AyuSettings.fontFamily, 6))
    entries.append(.action(base + 5, "Подарки: добавить все в коллекцию", "", 5))
    entries.append(.action(base + 2, "О GFPGRAM", AyuSettings.version, 1))
    if adminUnlocked {
        entries.append(.action(base + 3, "Админ-панель", "", 2))
    }
    return entries
}

public func gfpramSettingsController(context: AccountContext) -> ViewController {
    AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramArguments(
        toggle: { key, newValue in
            AyuSettings.set(key, newValue)
            refresh.set(true)
        },
        perform: { kind in
            switch kind {
            case 0:
                pushImpl?(gfpramIconsController(context: context))
            case 5:
                pushImpl?(gfpramGiftsController(context: context))
            case 6:
                pushImpl?(gfpramFontController(context: context))
            case 1:
                presentImpl?(promptController(context: context, text: "Введите ключ", value: nil, placeholder: "", apply: { value in
                    guard let value = value else {
                        return
                    }
                    if AyuSettings.verifyAdminCode(value) {
                        refresh.set(true)
                        pushImpl?(gfpramAdminController(context: context))
                    }
                }))
            case 2:
                pushImpl?(gfpramAdminController(context: context))
            case 3:
                pushImpl?(gfpramPremiumController(context: context))
            case 4:
                gfpramOpenSupport(context: context)
            case 22:
                if let name = AyuSettings.ownUsername {
                    UIPasteboard.general.string = "@" + name
                }
            case 20:
                UIPasteboard.general.string = String(context.account.peerId.id._internalGetInt64Value())
            default:
                break
            }
        }
    )

    let ownPeer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get(), ownPeer)
    |> deliverOnMainQueue
    |> map { presentationData, _, ownPeer -> (ItemListControllerState, (ItemListNodeState, Any)) in
        AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
        var ownPhone: String?
        var ownUsername: String?
        if let ownPeer = ownPeer, case let .user(user) = ownPeer {
            ownPhone = user.phone
            ownUsername = user.username
            AyuSettings.ownUsername = user.username
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("GFPGRAM"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramEntries(adminUnlocked: AyuSettings.adminUnlocked, ownId: context.account.peerId.id._internalGetInt64Value(), ownPhone: ownPhone, ownUsername: ownUsername), style: .blocks, animateChanges: false)
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

// MARK: - Админ-панель

private func gfpramAdminEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ЗНАЧОК «#»"))
    entries.append(.action(1, "Выдать значок: @username, ссылка или ID", "", 10))
    entries.append(.action(2, "Выдать значок себе", "", 11))
    var index: Int32 = 3
    var listIndex: Int32 = 0
    for entry in AyuBadges.entries() {
        entries.append(.action(index, "# " + entry.name, "убрать", 1000 + listIndex))
        index += 1
        listIndex += 1
    }
    entries.append(.footer(index, "Значок «#» показывается рядом с именем пользователя или названием канала только на этом устройстве. Другие пользователи его не видят. Быстрее всего: зажать любое сообщение в канале или чате и выбрать «Выдать значок #»."))
    entries.append(.header(100, "ДАННЫЕ"))
    entries.append(.action(101, "Забыть маркеры удалённых сообщений", "", 12))
    entries.append(.header(200, "PREMIUM"))
    entries.append(.action(201, "Выдать Premium пользователю", "", 20))
    entries.append(.action(202, "Выдать Premium себе", AyuPremium.statusText, 21))
    entries.append(.action(203, "Снять свой Premium", "", 22))
    entries.append(.footer(204, "Срок задаёте вы: «30» = 30 дней, «7д», «12ч», «90м». Создаётся ключ для конкретного аккаунта, его можно отправить прямо в чат. Изменить срок уже выданного ключа нельзя: выдайте новый. Ниже журнал выдачи, нажмите запись, чтобы скопировать ключ."))
    var issuedIndex: Int32 = 0
    for row in AyuPremium.issuedLog() {
        entries.append(.action(205 + issuedIndex, row.name, "до " + AyuPremium.format(row.until), 2000 + issuedIndex))
        issuedIndex += 1
    }
    return entries
}

public func gfpramAdminController(context: AccountContext) -> ViewController {
    AyuScope.setUI(context.account.peerId.id._internalGetInt64Value())
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?

    let showMessage: (String) -> Void = { text in
        presentImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]))
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            if kind >= 2000 {
                let log = AyuPremium.issuedLog()
                let index = Int(kind - 2000)
                if index >= 0 && index < log.count {
                    UIPasteboard.general.string = log[index].key
                    showMessage("Ключ скопирован")
                }
                return
            }
            if kind >= 1000 {
                let entries = AyuBadges.entries()
                let index = Int(kind - 1000)
                if index >= 0 && index < entries.count {
                    AyuBadges.remove(id: entries[index].id)
                    refresh.set(true)
                }
                return
            }
            switch kind {
            case 10:
                presentImpl?(promptController(context: context, text: "@username, ссылка t.me или числовой ID канала/пользователя", value: nil, placeholder: "@channel", apply: { value in
                    guard let value = value else {
                        return
                    }
                    var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    for prefix in ["https://", "http://", "t.me/", "telegram.me/", "@"] {
                        if name.hasPrefix(prefix) {
                            name.removeFirst(prefix.count)
                        }
                    }
                    if let slash = name.firstIndex(where: { $0 == "/" || $0 == "?" }) {
                        name = String(name[name.startIndex ..< slash])
                    }
                    if name.isEmpty {
                        return
                    }
                    if let numeric = Int64(name.hasPrefix("-100") ? String(name.dropFirst(4)) : name), numeric > 0 {
                        AyuBadges.add(id: numeric, name: "ID " + String(numeric))
                        refresh.set(true)
                        return
                    }
                    let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
                    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                        switch result {
                        case .progress:
                            return .complete()
                        case let .result(peer):
                            return .single(peer)
                        }
                    }
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { peer in
                        if let peer = peer {
                            AyuBadges.add(id: peer.id.id._internalGetInt64Value(), name: peer.compactDisplayTitle)
                            refresh.set(true)
                        } else {
                            showMessage("Не найдено")
                        }
                    })
                }))
            case 11:
                AyuBadges.add(id: context.account.peerId.id._internalGetInt64Value(), name: "Я")
                refresh.set(true)
            case 12:
                AyuDeleted.clearAll()
                showMessage("Готово")
            case 20:
                gfpramAdminIssuePremium(context: context, selfOnly: false, present: { c in presentImpl?(c) }, done: { refresh.set(true) })
            case 21:
                gfpramAdminIssuePremium(context: context, selfOnly: true, present: { c in presentImpl?(c) }, done: { refresh.set(true) })
            case 22:
                AyuPremium.revokeLocal()
                refresh.set(true)
                showMessage("Premium снят на этом устройстве")
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Админ-панель"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramAdminEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
