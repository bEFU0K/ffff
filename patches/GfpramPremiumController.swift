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

private func gfpramAlert(context: AccountContext, title: String?, text: String, actions: [TextAlertAction]? = nil) -> ViewController {
    return textAlertController(context: context, title: title, text: text, actions: actions ?? [TextAlertAction(type: .defaultAction, title: "OK", action: {})])
}

private func gfpramShort(_ text: String, _ limit: Int = 22) -> String {
    let single = text.replacingOccurrences(of: "\n", with: " ")
    return single.count > limit ? String(single.prefix(limit)) + "…" : single
}

// MARK: - Окно GFPGRAM Premium

private func gfpramPremiumEntries() -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "GFPGRAM PREMIUM"))
    entries.append(.action(1, "Статус", AyuPremium.statusText, 0))
    entries.append(.action(2, "Цена", AyuPremium.price + " / месяц", 0))
    entries.append(.action(3, "Купить премиум", "", 1))
    entries.append(.action(4, "Активировать ключ", "", 2))
    entries.append(.footer(5, "Кнопка «Купить премиум» отправит в @\(AyuPremium.supportUsername) сообщение «\(AyuPremium.buyText)». После оплаты вам пришлют ключ — введите его через «Активировать ключ». Ключ привязан к вашему аккаунту и действует до даты, которую поставил администратор."))

    entries.append(.header(100, "ФУНКЦИИ PREMIUM"))
    entries.append(.action(101, "Спам сообщениями", "", 10))
    entries.append(.toggle(102, "Заглушка, когда тегают в группе", "premiumStub", AyuSettings.value("premiumStub")))
    entries.append(.action(103, "Текст заглушки", gfpramShort(AyuPremiumService.stubText), 11))
    entries.append(.toggle(104, "Бэкап данных аккаунта", "premiumBackup", AyuSettings.value("premiumBackup")))
    entries.append(.action(105, "Бэкапы аккаунтов", String(AyuBackup.entries().count), 12))
    entries.append(.toggle(106, "⭐ рядом с моим именем", "premiumStar", AyuSettings.value("premiumStar")))
    entries.append(.footer(107, "Заглушка отвечает один раз в 2 минуты на каждую группу и только пока приложение запущено. Бэкап сохраняет имя, ID, юзернейм и номер в связку ключей iOS, поэтому данные остаются после удаления приложения. Сам вход (сессию) бэкап не хранит: чтобы вернуться в аккаунт, нужен код из Telegram."))

    entries.append(.header(200, "ПОДДЕРЖКА"))
    entries.append(.action(201, "Тех-поддержка", "@" + AyuPremium.supportUsername, 20))
    return entries
}

public func gfpramPremiumController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let needPremium: () -> Void = {
        presentImpl?(gfpramAlert(context: context, title: "Нужен GFPGRAM Premium", text: "Функция доступна по подписке: \(AyuPremium.price) в месяц. Нажмите «Купить премиум» вверху этого окна."))
    }

    let arguments = GfpramArguments(
        toggle: { key, newValue in
            if !AyuPremium.isActive {
                needPremium()
                refresh.set(true)
                return
            }
            AyuSettings.set(key, newValue)
            if key == "premiumBackup" && newValue {
                AyuPremiumService.snapshot(account: context.account)
            }
            refresh.set(true)
        },
        perform: { kind in
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
                if !AyuPremium.isActive {
                    needPremium()
                    return
                }
                presentImpl?(promptController(context: context, text: "Текст заглушки", value: AyuPremiumService.stubText, placeholder: "", apply: { value in
                    guard let value = value else {
                        return
                    }
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    AyuPremiumService.stubText = clean
                    refresh.set(true)
                }))
            case 12:
                if AyuPremium.isActive {
                    pushImpl?(gfpramBackupController(context: context))
                } else {
                    needPremium()
                }
            case 20:
                gfpramOpenSupport(context: context)
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("GFPGRAM Premium"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramPremiumEntries(), style: .blocks, animateChanges: false)
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
