import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// BluetoothMessageQueueService
/// Manages offline message queuing for Bluetooth communication with ESP32.
/// When Bluetooth is unavailable, messages are persisted locally and can be
/// retried when connection is restored.
class BluetoothMessageQueueService {
  static const _queueBoxName = 'bluetooth_queue';
  static const _keyPrefix = 'message_';
  static int _messageCounter = 0;

  /// Open queue box if not open
  static Future<Box> _openBox() async {
    if (!Hive.isBoxOpen(_queueBoxName)) {
      return await Hive.openBox(_queueBoxName);
    }
    return Hive.box(_queueBoxName);
  }

  /// Queue a message for later sending to ESP32
  static Future<String> queueMessage(Map<String, dynamic> message) async {
    try {
      final box = await _openBox();
      
      // Generate unique message ID
      final messageId = '${DateTime.now().millisecondsSinceEpoch}_${_messageCounter++}';
      
      // Create message envelope with metadata
      final envelope = {
        'id': messageId,
        'action': message['action'],
        'bookingId': message['bookingId'],
        'queuedAt': DateTime.now().toIso8601String(),
        'retryCount': 0,
        'data': message,
      };
      
      // Store in Hive
      await box.put('$_keyPrefix$messageId', envelope);
      
      debugPrint('[BT Queue] Message queued: $messageId');
      return messageId;
    } catch (e) {
      debugPrint('[BT Queue] Error queuing message: $e');
      rethrow;
    }
  }

  /// Get all queued messages
  static Future<List<Map<String, dynamic>>> getQueuedMessages() async {
    try {
      final box = await _openBox();
      final messages = <Map<String, dynamic>>[];
      
      for (final key in box.keys) {
        if (key is String && key.startsWith(_keyPrefix)) {
          final value = box.get(key);
          if (value is Map) {
            messages.add(Map<String, dynamic>.from(value));
          }
        }
      }
      
      debugPrint('[BT Queue] Retrieved ${messages.length} queued messages');
      return messages;
    } catch (e) {
      debugPrint('[BT Queue] Error retrieving messages: $e');
      return [];
    }
  }

  /// Remove a message from the queue by message ID
  static Future<void> removeMessageFromQueue(String messageId) async {
    try {
      final box = await _openBox();
      await box.delete('$_keyPrefix$messageId');
      debugPrint('[BT Queue] Message removed: $messageId');
    } catch (e) {
      debugPrint('[BT Queue] Error removing message: $e');
    }
  }

  /// Remove a queued message by booking ID (first match)
  static Future<void> removeByBookingId(String bookingId) async {
    try {
      final box = await _openBox();
      String? keyToDelete;
      
      for (final key in box.keys) {
        if (key is String && key.startsWith(_keyPrefix)) {
          final value = box.get(key);
          if (value is Map && value['bookingId'] == bookingId) {
            keyToDelete = key;
            break;
          }
        }
      }
      
      if (keyToDelete != null) {
        await box.delete(keyToDelete);
        debugPrint('[BT Queue] Message for booking $bookingId removed');
      }
    } catch (e) {
      debugPrint('[BT Queue] Error removing message by booking ID: $e');
    }
  }

  /// Get count of queued messages
  static Future<int> getQueueCount() async {
    try {
      final box = await _openBox();
      int count = 0;
      
      for (final key in box.keys) {
        if (key is String && key.startsWith(_keyPrefix)) {
          count++;
        }
      }
      
      return count;
    } catch (e) {
      debugPrint('[BT Queue] Error getting queue count: $e');
      return 0;
    }
  }

  /// Clear all queued messages
  static Future<void> clearQueue() async {
    try {
      final box = await _openBox();
      final keysToDelete = <String>[];
      
      for (final key in box.keys) {
        if (key is String && key.startsWith(_keyPrefix)) {
          keysToDelete.add(key);
        }
      }
      
      for (final key in keysToDelete) {
        await box.delete(key);
      }
      
      debugPrint('[BT Queue] Queue cleared (${keysToDelete.length} messages removed)');
    } catch (e) {
      debugPrint('[BT Queue] Error clearing queue: $e');
    }
  }

  /// Increment retry count for a message
  static Future<void> incrementRetryCount(String messageId) async {
    try {
      final box = await _openBox();
      final key = '$_keyPrefix$messageId';
      final envelope = box.get(key);
      
      if (envelope is Map) {
        final updated = Map<String, dynamic>.from(envelope);
        updated['retryCount'] = (updated['retryCount'] as int? ?? 0) + 1;
        await box.put(key, updated);
        debugPrint('[BT Queue] Retry count incremented for $messageId');
      }
    } catch (e) {
      debugPrint('[BT Queue] Error incrementing retry count: $e');
    }
  }

  /// Initialize the queue box on app startup
  static Future<void> initializeQueue() async {
    try {
      await _openBox();
      final count = await getQueueCount();
      debugPrint('[BT Queue] Initialized with $count messages in queue');
    } catch (e) {
      debugPrint('[BT Queue] Error initializing queue: $e');
    }
  }
}
