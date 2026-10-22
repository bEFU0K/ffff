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

// Подарки: вводишь @username -> видишь все подарки, которые этот человек подарил тебе ->
// «Выбрать папку» -> все они сразу добавляются в выбранную папку (коллекцию) профиля.
// ШАБЛОН: apply_patches.py проверяет, что нужное API есть в Telegram-iOS; иначе ставится GfpramGiftsStub.swift.

private final class GfpramGiftsState {
    var peer: EnginePeer?
    var label: String = ""
    var loading = false
    var total = 0
    var matched: [ProfileGiftsContext.State.StarGift] = []
    var context: ProfileGiftsContext?
    var lastRequested = -1
    let disposable = MetaDisposable()
}

private func gfpramGiftsEntries(state: GfpramGiftsState) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ОТ КОГО ПОДАРКИ"))
    entries.append(.action(1, "Пользователь", state.peer == nil ? "Указать" : state.label, 1))
    if state.peer != nil {
        entries.append(.header(100, "НАЙДЕНО"))
        entries.append(.action(101, state.loading ? "Загружаю подарки…" : "Подарков от этого пользователя", String(state.matched.count), 0))
        entries.append(.action(102, "Выбрать папку и добавить все", "", 2))
        entries.append(.footer(103, "Просмотрено подарков в профиле: \(state.total). Подарки, отправленные анонимно, Telegram не показывает с именем отправителя, поэтому они сюда не попадают."))
    } else {
        entries.append(.footer(103, "Введите @username, ссылку t.me или числовой ID. Приложение найдёт в вашем профиле все подарки от этого человека."))
    }
    return entries
}

public func gfpramGiftsController(context: AccountContext) -> ViewController {
    let state = GfpramGiftsState()
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?

    let load: (EnginePeer, String) -> Void = { peer, label in
        state.peer = peer
        state.label = label
        state.loading = true
        state.total = 0
        state.matched = []
        state.lastRequested = -1
        let giftsContext = ProfileGiftsContext(account: context.account, peerId: context.account.peerId)
        state.context = giftsContext
        state.disposable.set((giftsContext.state
        |> deliverOnMainQueue).start(next: { value in
            state.total = value.gifts.count
            state.matched = value.gifts.filter { $0.fromPeer?.id == peer.id }
            if case let .ready(canLoadMore, _) = value.dataState {
                if canLoadMore && state.lastRequested != value.gifts.count {
                    state.lastRequested = value.gifts.count
                    giftsContext.loadMore()
                } else {
                    state.loading = false
                }
            }
            refresh.set(true)
        }))
        refresh.set(true)
    }

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            switch kind {
            case 1:
                presentImpl?(promptController(context: context, text: "@username, ссылка t.me или числовой ID человека, который дарил вам подарки", value: nil, placeholder: "@username", apply: { value in
                    guard let value = value, !value.isEmpty else {
                        return
                    }
                    gfpramResolve(context: context, name: value, completion: { peer in
                        guard let peer = peer else {
                            presentImpl?(gfpramAlert(context: context, title: nil, text: "Пользователь не найден."))
                            return
                        }
                        var label = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !label.hasPrefix("@") && !label.contains("/") && Int64(label) == nil {
                            label = "@" + label
                        }
                        load(peer, label)
                    })
                }))
            case 2:
                if state.loading {
                    presentImpl?(gfpramAlert(context: context, title: nil, text: "Подарки ещё загружаются, подождите несколько секунд."))
                } else if state.matched.isEmpty {
                    presentImpl?(gfpramAlert(context: context, title: nil, text: "Подарков от этого пользователя не найдено."))
                } else {
                    pushImpl?(gfpramGiftsFoldersController(context: context, gifts: state.matched, label: state.label))
                }
            default:
                break
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Подарки"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramGiftsEntries(state: state), style: .blocks, animateChanges: false)
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

// MARK: - Выбор папки

private final class GfpramFoldersState {
    var collections: [StarGiftCollection] = []
    var loaded = false
    var progress: String?
    var busy = false
    let disposable = MetaDisposable()
}

private func gfpramFoldersEntries(state: GfpramFoldersState, count: Int, label: String) -> [GfpramEntry] {
    var entries: [GfpramEntry] = []
    entries.append(.header(0, "ПАПКИ ПОДАРКОВ В ПРОФИЛЕ"))
    var index: Int32 = 1
    var listIndex: Int32 = 0
    for collection in state.collections {
        entries.append(.action(index, collection.title, "", 1000 + listIndex))
        index += 1
        listIndex += 1
    }
    if state.collections.isEmpty {
        entries.append(.footer(index, state.loaded ? "Папок пока нет. Создайте папку в своём профиле: Подарки → «+» рядом с вкладками." : "Загружаю папки…"))
    } else {
        entries.append(.footer(index, state.progress ?? "Нажмите на папку: все \(count) подарков от \(label) будут добавлены в неё."))
    }
    return entries
}

private func gfpramAddChunks(context: ProfileGiftsCollectionsContext, collectionId: Int32, gifts: [ProfileGiftsContext.State.StarGift], offset: Int, failed: Bool, progress: @escaping (Int) -> Void, done: @escaping (Bool) -> Void) {
    if offset >= gifts.count {
        done(failed)
        return
    }
    let end = min(offset + 50, gifts.count)
    let chunk = Array(gifts[offset ..< end])
    var finished = false
    let next: (Bool) -> Void = { hasError in
        if finished {
            return
        }
        finished = true
        progress(end)
        gfpramAddChunks(context: context, collectionId: collectionId, gifts: gifts, offset: end, failed: failed || hasError, progress: progress, done: done)
    }
    let _ = (context.addGifts(collectionId: collectionId, gifts: chunk)
    |> deliverOnMainQueue).start(error: { _ in
        next(true)
    }, completed: {
        next(false)
    })
}

private func gfpramGiftsFoldersController(context: AccountContext, gifts: [ProfileGiftsContext.State.StarGift], label: String) -> ViewController {
    let state = GfpramFoldersState()
    let refresh = ValuePromise<Bool>(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?

    let collectionsContext = ProfileGiftsCollectionsContext(account: context.account, peerId: context.account.peerId)
    state.disposable.set((collectionsContext.state
    |> deliverOnMainQueue).start(next: { value in
        state.collections = value.collections
        state.loaded = true
        refresh.set(true)
    }))

    let arguments = GfpramArguments(
        toggle: { _, _ in
        },
        perform: { kind in
            let index = Int(kind - 1000)
            if kind < 1000 || index >= state.collections.count || state.busy {
                return
            }
            let collection = state.collections[index]
            presentImpl?(gfpramAlert(context: context, title: "Папка «\(collection.title)»", text: "Добавить все подарки от \(label) (\(gifts.count) шт.) в эту папку?", actions: [
                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                TextAlertAction(type: .defaultAction, title: "Добавить", action: {
                    state.busy = true
                    state.progress = "Добавляю… 0 из \(gifts.count)"
                    refresh.set(true)
                    gfpramAddChunks(context: collectionsContext, collectionId: collection.id, gifts: gifts, offset: 0, failed: false, progress: { added in
                        state.progress = "Добавляю… \(added) из \(gifts.count)"
                        refresh.set(true)
                    }, done: { failed in
                        state.busy = false
                        state.progress = failed ? "Часть подарков добавить не удалось (в папке не больше 1000 подарков)." : "Готово: подарков в папке «\(collection.title)» — добавлено \(gifts.count)."
                        refresh.set(true)
                        presentImpl?(gfpramAlert(context: context, title: nil, text: failed ? "Не все подарки удалось добавить. Проверьте папку в профиле: у папки есть лимит подарков." : "Все подарки добавлены в папку «\(collection.title)»."))
                    })
                })
            ]))
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Выбрать папку"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: gfpramFoldersEntries(state: state, count: gifts.count, label: label), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
