import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../local_storage.dart';
import 'pos_device_auth_service.dart';

class EmployeeAccountService {
  static final EmployeeAccountService _instance =
      EmployeeAccountService._internal();

  factory EmployeeAccountService() => _instance;

  EmployeeAccountService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> resolveCrewCard(String rawUid) async {
    final normalizedUid = normalizeUid(rawUid);
    final employeeUidLower = employeeUidLowerFromRaw(rawUid);
    if (normalizedUid.isEmpty || employeeUidLower.isEmpty) {
      return null;
    }

    final signedIn = await POSDeviceAuthService().ensureSignedInWithPosRole();
    if (!signedIn) {
      debugPrint(
          '[EmployeeAccount] POS auth unavailable for $employeeUidLower');
      return null;
    }

    try {
      final snapshot = await _firestore
          .collection('user_accounts')
          .doc(employeeUidLower)
          .get();
      if (!snapshot.exists) {
        debugPrint('[EmployeeAccount] No employee doc for $employeeUidLower');
        return null;
      }

      final data = snapshot.data();
      if (data == null) return null;

      final role = data['role']?.toString().toLowerCase() ?? '';
      final enabled = data['enabled'] == true;
      final fieldUidLower = normalizeUid(data['employeeUidLower']);
      final fieldUid = normalizeUid(data['employeeUid']);
      final docUid = normalizeUid(snapshot.id);
      final uidMatches = normalizedUid == fieldUidLower ||
          normalizedUid == fieldUid ||
          normalizedUid == docUid;

      if (!enabled ||
          (role != 'conductor' && role != 'driver') ||
          !uidMatches) {
        debugPrint(
            '[EmployeeAccount] Rejected $employeeUidLower enabled=$enabled role=$role uidMatches=$uidMatches');
        return null;
      }

      final employee = _mapEmployee(snapshot.id, data, normalizedUid, role);
      await LocalStorage.upsertEmployee(employee);
      return employee;
    } catch (e) {
      debugPrint('[EmployeeAccount] Lookup failed for $employeeUidLower: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> resolveCard(String rawUid) async {
    final localEmployee = LocalStorage.getEmployee(rawUid);
    final localRole = localEmployee?['role']?.toString().toLowerCase() ?? '';
    if (localEmployee != null &&
        localRole != 'conductor' &&
        localRole != 'driver') {
      return {
        ...localEmployee,
        'recognized': true,
        'resolvedFromFirebase': false,
      };
    }

    final remoteEmployee = await resolveCrewCard(rawUid);
    if (remoteEmployee != null) {
      return {
        ...remoteEmployee,
        'recognized': true,
        'resolvedFromFirebase': true,
      };
    }

    if (localEmployee == null) return null;

    return {
      ...localEmployee,
      'recognized': true,
      'resolvedFromFirebase': false,
    };
  }

  Map<String, dynamic> unknownCardPayload(String rawUid) {
    return {
      'uid': normalizeUid(rawUid),
      'employeeUidLower': employeeUidLowerFromRaw(rawUid),
      'role': 'unknown',
      'name': '',
      'recognized': false,
      'resolvedFromFirebase': false,
    };
  }

  Map<String, dynamic> _mapEmployee(
    String docId,
    Map<String, dynamic> data,
    String normalizedUid,
    String role,
  ) {
    final firstName = data['firstName']?.toString() ?? '';
    final lastName = data['lastName']?.toString() ?? '';
    final fallbackName = '$firstName $lastName'.trim();
    final name = (data['name']?.toString().trim().isNotEmpty ?? false)
        ? data['name'].toString().trim()
        : fallbackName;

    return {
      'uid': normalizedUid,
      'name': name.isEmpty ? 'Unnamed Employee' : name,
      'role': role,
      'authUid': data['authUid']?.toString() ?? '',
      'employeeUid': data['employeeUid']?.toString() ?? '',
      'employeeUidLower': data['employeeUidLower']?.toString() ?? docId,
      'firstName': firstName,
      'lastName': lastName,
      'enabled': data['enabled'] == true,
      'firebaseDocId': docId,
      'firebaseSynced': true,
      'synced': true,
      'createdAt': _safeValue(data['createdAt']),
      'updatedAt': _safeValue(data['updatedAt']),
    };
  }

  dynamic _safeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is num || value is String || value is bool) return value;
    return value.toString();
  }

  static String normalizeUid(dynamic rawUid) {
    return rawUid
            ?.toString()
            .replaceAll(RegExp(r'[^A-Fa-f0-9]'), '')
            .toUpperCase() ??
        '';
  }

  static String employeeUidLowerFromRaw(dynamic rawUid) {
    final hex = normalizeUid(rawUid).toLowerCase();
    if (hex.isEmpty) return '';

    final pairs = <String>[];
    for (var index = 0; index < hex.length; index += 2) {
      final end = index + 2 <= hex.length ? index + 2 : hex.length;
      pairs.add(hex.substring(index, end));
    }
    return pairs.join(':');
  }
}
