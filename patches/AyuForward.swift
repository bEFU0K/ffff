import Foundation
import Postbox

/// Пересылка из закрытых чатов: сервер отклоняет forwardMessages, поэтому отправляем копию обычным сообщением.
public enum AyuForward {
    public static func isProtected(_ peer: Peer?) -> Bool {
        if let channel = peer as? TelegramChannel {
            return channel.flags.contains(.copyProtectionEnabled)
        }
        if let group = peer as? TelegramGroup {
            return group.flags.contains(.copyProtectionEnabled)
        }
        return false
    }

    public static func transform(transaction: Transaction, messages: [(Bool, EnqueueMessage)]) -> [(Bool, EnqueueMessage)] {
        if !AyuSettings.forwardCopy || !AyuSettings.allowCopy {
            return messages
        }
        var result: [(Bool, EnqueueMessage)] = []
        var groupKeys: [Int64: Int64] = [:]
        for (flag, message) in messages {
            if case let .forward(source, threadId, _, _, correlationId) = message,
               let sourceMessage = transaction.getMessage(source),
               isProtected(sourceMessage.peers[sourceMessage.id.peerId]) {
                var attributes: [MessageAttribute] = []
                for attribute in sourceMessage.attributes {
                    if attribute is TextEntitiesMessageAttribute {
                        attributes.append(attribute)
                    }
                }
                var mediaReference: AnyMediaReference?
                for media in sourceMessage.media {
                    if media is TelegramMediaWebpage {
                        continue
                    }
                    mediaReference = .standalone(media: media)
                    break
                }
                // Альбом остаётся альбомом: сообщения одной группы получают общий новый ключ
                var localGroupingKey: Int64?
                if let sourceGroup = sourceMessage.groupingKey, mediaReference != nil {
                    if let existing = groupKeys[sourceGroup] {
                        localGroupingKey = existing
                    } else {
                        let created = Int64.random(in: Int64.min ... Int64.max)
                        groupKeys[sourceGroup] = created
                        localGroupingKey = created
                    }
                }
                result.append((flag, .message(text: sourceMessage.text, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])))
            } else {
                result.append((flag, message))
            }
        }
        return result
    }
}
