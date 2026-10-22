import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI

// MARK: - Общие помощники

/// Жёлтая плитка со значком «#» для строки GFPGRAM в Настройках.
private var gfpramHashIconCache: UIImage?
public func gfpramHashIcon() -> UIImage? {
    if let image = gfpramHashIconCache { return image }
    let size = CGSize(width: 30, height: 30)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
        UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7).fill()
        let text = "#" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 21, weight: .heavy), .foregroundColor: UIColor.white]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (size.width - textSize.width) / 2.0, y: (size.height - textSize.height) / 2.0), withAttributes: attributes)
    }
    gfpramHashIconCache = image
    return image
}

func gfpramResolve(context: AccountContext, name: String, completion: @escaping (EnginePeer?) -> Void) {
    var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["https://", "http://", "t.me/", "telegram.me/", "@"] {
        if clean.hasPrefix(prefix) {
            clean.removeFirst(prefix.count)
        }
    }
    if let slash = clean.firstIndex(where: { $0 == "/" || $0 == "?" }) {
        clean = String(clean[clean.startIndex ..< slash])
    }
    if clean.isEmpty {
        completion(nil)
        return
    }
    let _ = (context.engine.peers.resolvePeerByName(name: clean, referrer: nil)
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
        completion(peer)
    })
}

/// Открывает чат с тех-поддержкой.
public func gfpramOpenSupport(context: AccountContext) {
    gfpramResolve(context: context, name: AyuPremium.supportUsername, completion: { peer in
        if let peer = peer {
            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peer.id, messageId: nil)
        }
    })
}

func gfpramAlert(context: AccountContext, title: String?, text: String, actions: [TextAlertAction]? = nil) -> ViewController {
    return textAlertController(context: context, title: title, text: text, actions: actions ?? [TextAlertAction(type: .defaultAction, title: "OK", action: {})])
}

private func gfpramShort(_ text: String, _ limit: Int = 22) -> String {
    let single = text.replacingOccurrences(of: "\n", with: " ")
    return single.count > limit ? String(single.prefix(limit)) + "…" : single
}

// MARK: - Окно GFPGRAM Premium

private func gfpramToggleKey(_ kind: Int32) -> String? {
    switch kind {
    case 31:
        return "premiumStub"
    case 32:
        return "premiumBackup"
    case 33:
        return "premiumStar"
    case 34:
        return "premiumDmReply"
    case 35:
        return "premiumKeyword"
    case 36:
        return "premiumMirror"
    case 37:
        return "premiumReact"
    case 38:
        return "premiumMentions"
    default:
        return nil
    }
}

private func gfpramMode(_ key: String) -> Int32 {
    return AyuPremium.isActive && AyuSettings.value(key) ? 2 : 1
}

private func gfpramPremiumEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ПОДПИСКА"))
    entries.append(.action(1, "Статус", AyuPremium.statusText, 0))
    entries.append(.action(2, "Цена", AyuPremium.price + " / месяц", 0))
    entries.append(.action(3, "Купить премиум", "", 1))
    entries.append(.action(4, "Активировать ключ", "", 2))
    entries.append(.footer(5, "Кнопка «Купить премиум» отправит в @\(AyuPremium.supportUsername) сообщение «\(AyuPremium.buyText)». После оплаты вам пришлют ключ — введите его через «Активировать ключ». Ключ привязан к вашему аккаунту и действует до даты, которую поставил администратор."))

    entries.append(.header(100, "ПРЕИМУЩЕСТВА ПОДПИСКИ"))
    entries.append(.feature(101, "Эксклюзивные иконки приложения", "Золото, Турбо, Лунная ночь и Утёнок: 4 иконки только для Premium. Нажмите, чтобы посмотреть и выбрать.", 40, 10, 0))
    entries.append(.feature(102, "Спам сообщениями", "Серия сообщений в выбранный чат с вашей паузой и счётчиком.", 10, 1, 0))
    entries.append(.feature(103, "Заглушка при упоминании", "Автоответ вашим текстом, когда вас тегают в группе. Раз в 2 минуты на группу.", 31, 2, gfpramMode("premiumStub")))
    entries.append(.feature(104, "Бэкап данных аккаунта", "Имя, ID, юзернейм и номер сохраняются в связку ключей iOS и переживают удаление приложения.", 32, 3, gfpramMode("premiumBackup")))
    entries.append(.feature(105, "⭐ рядом с моим именем", "Звезда рядом с вашим именем на этом устройстве.", 33, 4, gfpramMode("premiumStar")))
    entries.append(.feature(106, "Автоответчик в личных чатах", "Отвечает вашим текстом каждому, кто пишет вам в личку. Раз в 10 минут на человека.", 34, 5, gfpramMode("premiumDmReply")))
    entries.append(.feature(107, "Ответ на слово-триггер", "Слово в сообщении — и приложение само отправляет заданный ответ. Личные чаты и группы.", 35, 6, gfpramMode("premiumKeyword")))
    entries.append(.feature(108, "Копия личных сообщений в Избранное", "Все входящие личные сообщения дублируются в «Избранное», даже если собеседник их удалит.", 36, 7, gfpramMode("premiumMirror")))
    entries.append(.feature(109, "Авто-реакция на личные сообщения", "Ставит выбранную реакцию на каждое входящее личное сообщение.", 37, 8, gfpramMode("premiumReact")))
    entries.append(.feature(110, "Журнал упоминаний", "Каждое упоминание вас в группе копируется в «Избранное» с названием чата.", 38, 9, gfpramMode("premiumMentions")))
    entries.append(.footer(111, "Нажмите на функцию, чтобы включить или выключить её. Тексты, слово-триггер и реакция настраиваются ниже."))

    entries.append(.header(200, "НАСТРОЙКИ ФУНКЦИЙ"))
    entries.append(.action(201, "Текст заглушки", gfpramShort(AyuPremiumService.stubText), 11))
    entries.append(.action(202, "Текст автоответчика", gfpramShort(AyuPremiumService.dmReplyText), 13))
    entries.append(.action(203, "Слово-триггер", AyuPremiumService.keywordTrigger.isEmpty ? "не задано" : gfpramShort(AyuPremiumService.keywordTrigger), 14))
    entries.append(.action(204, "Ответ на слово", AyuPremiumService.keywordReply.isEmpty ? "не задан" : gfpramShort(AyuPremiumService.keywordReply), 15))
    entries.append(.action(205, "Реакция", AyuPremiumService.reactEmoji, 16))
    entries.append(.action(206, "Бэкапы аккаунтов", String(AyuBackup.entries().count), 12))
    entries.append(.footer(207, "Автоответы и копии работают только пока приложение запущено. Автоответ не отправляется ботам. Бэкап сохраняет имя, ID, юзернейм и номер в связку ключей iOS; сам вход (сессию) он не хранит: чтобы вернуться в аккаунт, нужен код из Telegram."))

    entries.append(.header(300, "ПОДДЕРЖКА"))
    entries.append(.iconAction(301, "Тех-поддержка", "@" + AyuPremium.supportUsername, 20, 101))
    return entries
}

public func gfpramPremiumController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let needPremium: () -> Void = {
        presentImpl?(gfpramAlert(context: context, title: "Нужен GFPGRAM Premium", text: "Функция доступна по подписке: \(AyuPremium.price) в месяц. Нажмите «Купить премиум» вверху этого окна."))
    }

    let promptText: (String, String, @escaping (String) -> Void) -> Void = { title, current, apply in
        if !AyuPremium.isActive {
            needPremium()
            return
        }
        presentImpl?(promptController(context: context, text: title, value: current, placeholder: "", apply: { value in
            guard let value = value else {
                return
            }
            apply(value.trimmingCharacters(in: .whitespacesAndNewlines))
            refresh.set(true)
        }))
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            if let key = gfpramToggleKey(kind) {
                if !AyuPremium.isActive {
                    needPremium()
                    return
                }
                let newValue = !AyuSettings.value(key)
                AyuSettings.set(key, newValue)
                if key == "premiumBackup" && newValue {
                    AyuPremiumService.snapshot(account: context.account)
                }
                refresh.set(true)
                return
            }
            switch kind {
            case 1:
                presentImpl?(gfpramAlert(context: context, title: "Купить GFPGRAM Premium", text: "Цена \(AyuPremium.price) за месяц. В @\(AyuPremium.supportUsername) будет отправлено сообщение «\(AyuPremium.buyText)».", actions: [
                    TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                    TextAlertAction(type: .defaultAction, title: "Отправить", action: {
                        gfpramResolve(context: context, name: AyuPremium.supportUsername, completion: { peer in
                            guard let peer = peer else {
                                presentImpl?(gfpramAlert(context: context, title: nil, text: "Не удалось найти @\(AyuPremium.supportUsername). Проверьте интернет."))
                                return
                            }
                            let _ = context.engine.messages.enqueueOutgoingMessage(to: peer.id, replyTo: nil, content: .text(AyuPremium.buyText)).start()
                            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peer.id, messageId: nil)
                        })
                    })
                ]))
            case 2:
                presentImpl?(promptController(context: context, text: "Введите ключ активации", value: nil, placeholder: "GFP-...", apply: { value in
                    guard let value = value else {
                        return
                    }
                    let ownId = context.account.peerId.id._internalGetInt64Value()
                    switch AyuPremium.activate(key: value, ownId: ownId) {
                    case let .ok(date):
                        AyuPremiumService.snapshot(account: context.account)
                        presentImpl?(gfpramAlert(context: context, title: "Premium активирован", text: "Действует до " + AyuPremium.format(date)))
                    case .invalid:
                        presentImpl?(gfpramAlert(context: context, title: nil, text: "Неверный ключ"))
                    case .expired:
                        presentImpl?(gfpramAlert(context: context, title: nil, text: "Срок этого ключа уже истёк"))
                    case .wrongAccount:
                        presentImpl?(gfpramAlert(context: context, title: nil, text: "Этот ключ выдан для другого аккаунта"))
                    }
                    refresh.set(true)
                }))
            case 10:
                if AyuPremium.isActive {
                    pushImpl?(gfpramSpamController(context: context))
                } else {
                    needPremium()
                }
            case 11:
                promptText("Текст заглушки", AyuPremiumService.stubText, { value in
                    AyuPremiumService.stubText = value
                })
            case 12:
                if AyuPremium.isActive {
                    pushImpl?(gfpramBackupController(context: context))
                } else {
                    needPremium()
                }
            case 13:
                promptText("Текст автоответчика в личных чатах", AyuPremiumService.dmReplyText, { value in
                    AyuPremiumService.dmReplyText = value
                })
            case 14:
                promptText("Слово-триггер (ищется в входящих сообщениях)", AyuPremiumService.keywordTrigger, { value in
                    AyuPremiumService.keywordTrigger = value
                })
            case 15:
                promptText("Ответ на слово-триггер", AyuPremiumService.keywordReply, { value in
                    AyuPremiumService.keywordReply = value
                })
            case 16:
                promptText("Эмодзи для авто-реакции (одна реакция, например 👍 ❤️ 🔥)", AyuPremiumService.reactEmoji, { value in
                    AyuPremiumService.reactEmoji = value
                })
            case 20:
                gfpramOpenSupport(context: context)
            case 40:
                pushImpl?(gfpramIconsController(context: context))
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(""), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let headerText: String
        if AyuPremium.isActive {
            headerText = "Подписка активна " + AyuPremium.statusText + ". Все функции и 4 эксклюзивные иконки доступны."
        } else {
            headerText = "Эксклюзивные функции клиента GFPGRAM: автоответы, копии сообщений, спам-режим, бэкап аккаунта и 4 эксклюзивные иконки приложения."
        }
        let header = GfpramPremiumHeaderItem(theme: presentationData.theme, title: "GFPGRAM Premium", text: headerText, icon: .carousel(gfpramPremiumIconKeys), locked: !AyuPremium.isActive)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramPremiumEntries(), style: .blocks, headerItem: header, animateChanges: false)
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

// MARK: - Окно «Спам сообщениями»

private final class GfpramSpamState {
    var targetTitle: String = "Избранное"
    var targetPeerId: EnginePeer.Id?
    var text: String = ""
    var count: Int = 5
    var interval: Int = 2
    var running: Bool = false
    var sent: Int = 0
    var generation: Int = 0
}

private func gfpramSpamStep(context: AccountContext, state: GfpramSpamState, generation: Int, refresh: ValuePromise<Bool>) {
    if !state.running || state.generation != generation {
        return
    }
    if !AyuPremium.isActive || state.sent >= state.count {
        state.running = false
        refresh.set(true)
        return
    }
    let peerId = state.targetPeerId ?? context.account.peerId
    let _ = context.engine.messages.enqueueOutgoingMessage(to: peerId, replyTo: nil, content: .text(state.text)).start()
    state.sent += 1
    refresh.set(true)
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(state.interval), execute: {
        gfpramSpamStep(context: context, state: state, generation: generation, refresh: refresh)
    })
}

private func gfpramSpamEntries(state: GfpramSpamState) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "СПАМ СООБЩЕНИЯМИ"))
    entries.append(.action(1, "Чат", state.targetTitle, 1))
    entries.append(.action(2, "Текст", state.text.isEmpty ? "не задан" : gfpramShort(state.text), 2))
    entries.append(.action(3, "Количество", String(state.count), 3))
    entries.append(.action(4, "Пауза, сек", String(state.interval), 4))
    entries.append(.footer(5, "Чат: @username или ссылка t.me; пусто = «Избранное». Максимум 50 сообщений, пауза от 1 секунды: при более частой отправке Telegram включает ограничение. Окно должно оставаться открытым, пока идёт отправка. Используйте только в своих чатах и с согласия участников."))
    entries.append(.header(100, "ЗАПУСК"))
    if state.running {
        entries.append(.action(101, "Остановить", "\(state.sent) из \(state.count)", 6))
    } else {
        entries.append(.action(101, "Запустить", state.sent > 0 ? "отправлено \(state.sent)" : "", 5))
    }
    return entries
}

public func gfpramSpamController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?
    let state = GfpramSpamState()

    let showMessage: (String) -> Void = { text in
        presentImpl?(gfpramAlert(context: context, title: nil, text: text))
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            switch kind {
            case 1:
                presentImpl?(promptController(context: context, text: "@username или ссылка t.me. Пусто = Избранное", value: nil, placeholder: "@username", apply: { value in
                    guard let value = value else {
                        return
                    }
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        state.targetPeerId = nil
                        state.targetTitle = "Избранное"
                        refresh.set(true)
                        return
                    }
                    gfpramResolve(context: context, name: value, completion: { peer in
                        if let peer = peer {
                            state.targetPeerId = peer.id
                            state.targetTitle = peer.compactDisplayTitle
                            refresh.set(true)
                        } else {
                            showMessage("Не найдено")
                        }
                    })
                }))
            case 2:
                presentImpl?(promptController(context: context, text: "Текст сообщения", value: state.text, placeholder: "", apply: { value in
                    guard let value = value else {
                        return
                    }
                    state.text = value
                    refresh.set(true)
                }))
            case 3:
                presentImpl?(promptController(context: context, text: "Сколько сообщений (1–50)", value: String(state.count), placeholder: "5", apply: { value in
                    guard let value = value, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        return
                    }
                    state.count = max(1, min(50, number))
                    refresh.set(true)
                }))
            case 4:
                presentImpl?(promptController(context: context, text: "Пауза между сообщениями, сек (1–60)", value: String(state.interval), placeholder: "2", apply: { value in
                    guard let value = value, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        return
                    }
                    state.interval = max(1, min(60, number))
                    refresh.set(true)
                }))
            case 5:
                if !AyuPremium.isActive {
                    showMessage("Нужен GFPGRAM Premium")
                    return
                }
                if state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showMessage("Сначала задайте текст")
                    return
                }
                state.running = true
                state.sent = 0
                state.generation += 1
                refresh.set(true)
                gfpramSpamStep(context: context, state: state, generation: state.generation, refresh: refresh)
            case 6:
                state.running = false
                state.generation += 1
                refresh.set(true)
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Спам сообщениями"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramSpamEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.willDisappear = { _ in
        state.running = false
        state.generation += 1
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Окно «Бэкапы аккаунтов»

private func gfpramBackupEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "БЭКАПЫ АККАУНТОВ"))
    entries.append(.action(1, "Сохранить этот аккаунт сейчас", "", 1))
    var index: Int32 = 2
    var listIndex: Int32 = 0
    for entry in AyuBackup.entries() {
        entries.append(.action(index, entry.name, entry.username.map { "@" + $0 } ?? String(entry.id), 1000 + listIndex))
        index += 1
        listIndex += 1
    }
    entries.append(.footer(index, "Нажмите на запись, чтобы посмотреть данные, скопировать или удалить. Данные лежат в связке ключей iOS и остаются после удаления приложения (если при переустановке не менялись Apple ID и bundle id)."))
    entries.append(.header(500, "ДАННЫЕ"))
    entries.append(.action(501, "Удалить все бэкапы", "", 2))
    return entries
}

public func gfpramBackupController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            if kind >= 1000 {
                let list = AyuBackup.entries()
                let index = Int(kind - 1000)
                if index >= 0 && index < list.count {
                    let entry = list[index]
                    presentImpl?(gfpramAlert(context: context, title: entry.name, text: AyuBackup.text(for: entry), actions: [
                        TextAlertAction(type: .genericAction, title: "Копировать", action: {
                            UIPasteboard.general.string = AyuBackup.text(for: entry)
                        }),
                        TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                            AyuBackup.remove(id: entry.id)
                            refresh.set(true)
                        }),
                        TextAlertAction(type: .defaultAction, title: "Закрыть", action: {})
                    ]))
                }
                return
            }
            switch kind {
            case 1:
                AyuPremiumService.snapshot(account: context.account, force: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: {
                    refresh.set(true)
                })
            case 2:
                AyuBackup.removeAll()
                refresh.set(true)
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Бэкапы аккаунтов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramBackupEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Админ: выдача Premium (вызывается из админ-панели)

/// Админ вводит получателя и срок, приложение создаёт ключ активации. Свой аккаунт активируется сразу.
public func gfpramAdminIssuePremium(context: AccountContext, selfOnly: Bool, present: @escaping (ViewController) -> Void, done: @escaping () -> Void) {
    let askDuration: (String, Int64, @escaping (TimeInterval) -> Void) -> Void = { name, userId, completion in
        present(promptController(context: context, text: "Срок для \(name): «30» = 30 дней, «12ч» = часы, «90м» = минуты", value: "30", placeholder: "30", apply: { value in
            guard let value = value else {
                return
            }
            if let seconds = AyuPremium.parseDuration(value) {
                completion(seconds)
            } else {
                present(gfpramAlert(context: context, title: nil, text: "Не понял срок. Примеры: 30, 7д, 12ч, 90м"))
            }
        }))
    }

    let finish: (EnginePeer?, Int64, String, TimeInterval) -> Void = { peer, userId, name, seconds in
        let issued = AyuPremium.issue(userId: userId, name: name, duration: seconds)
        if userId == context.account.peerId.id._internalGetInt64Value() {
            let _ = AyuPremium.activate(key: issued.key, ownId: userId)
            present(gfpramAlert(context: context, title: "Premium включён", text: "Действует до " + AyuPremium.format(issued.until)))
            done()
            return
        }
        UIPasteboard.general.string = issued.key
        var actions: [TextAlertAction] = []
        if let peer = peer {
            actions.append(TextAlertAction(type: .genericAction, title: "Отправить в чат", action: {
                let message = "Ваш ключ GFPGRAM Premium (до \(AyuPremium.format(issued.until))):\n\(issued.key)\n\nАктивация: Настройки → GFPGRAM → GFPGRAM Premium → Активировать ключ"
                let _ = context.engine.messages.enqueueOutgoingMessage(to: peer.id, replyTo: nil, content: .text(message)).start()
            }))
        }
        actions.append(TextAlertAction(type: .defaultAction, title: "Готово", action: {}))
        present(gfpramAlert(context: context, title: "Ключ для \(name)", text: "\(issued.key)\n\nДо " + AyuPremium.format(issued.until) + ". Ключ уже скопирован.", actions: actions))
        done()
    }

    if selfOnly {
        askDuration("себя", context.account.peerId.id._internalGetInt64Value(), { seconds in
            finish(nil, context.account.peerId.id._internalGetInt64Value(), "Я", seconds)
        })
        return
    }

    present(promptController(context: context, text: "Кому выдать: @username, ссылка t.me или числовой ID", value: nil, placeholder: "@username", apply: { value in
        guard let value = value else {
            return
        }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Int64(clean), numeric > 0 {
            askDuration("ID \(numeric)", numeric, { seconds in
                finish(nil, numeric, "ID \(numeric)", seconds)
            })
            return
        }
        gfpramResolve(context: context, name: clean, completion: { peer in
            guard let peer = peer else {
                present(gfpramAlert(context: context, title: nil, text: "Не найдено"))
                return
            }
            let userId = peer.id.id._internalGetInt64Value()
            askDuration(peer.compactDisplayTitle, userId, { seconds in
                finish(peer, userId, peer.compactDisplayTitle, seconds)
            })
        })
    }))
}
