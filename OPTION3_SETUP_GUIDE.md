# Option 3 (Role-Based) Implementation - Setup Guide

**Status**: ✅ Complete | **Date**: January 9, 2026

## What Was Implemented

Your dispatcher system now has **Option 3: Role-Based Authentication** with:

✅ **Device-Level Auth (POS)** - Two POS devices with unique credentials  
✅ **Conductor-Level Identification** - NFC taps identify conductor locally (unchanged)  
✅ **Firestore Role-Based Rules** - Dispatcher vs POS roles with different access levels  
✅ **Secure Sync** - POS can only update dispatch fields, dispatcher controls schedules  
✅ **Offline-Ready** - Device token cached, syncs work offline → online  

---

## 📁 Files Created/Modified

### New Files
- **[lib/services/pos_device_auth_service.dart](lib/services/pos_device_auth_service.dart)** - Device authentication service
- **[firestore.rules](firestore.rules)** - Option 3 rules with role-based access

### Modified Files
- **[lib/main.dart](lib/main.dart)** - Added device sign-in on startup
- **[lib/services/firebase_dispatch_service.dart](lib/services/firebase_dispatch_service.dart)** - Added auth verification
- **[lib/services/arrival_report_sync_service.dart](lib/services/arrival_report_sync_service.dart)** - Added auth check

### Dispatcher Dashboard
- **[firestore.rules](../dispatcher_dashboard/firestore.rules)** - Updated to match POS rules

---

## 🔧 Setup Steps (Do These In Order)

### Step 1: Create Two Firebase Users (in Firebase Console)

**Device 1:**
- Email: `posdevice001@example.com`
- Password: `Test1234.`

**Device 2:**
- Email: `posdevice002@example.com`
- Password: `Test1234.`

**How:**
1. Go to Firebase Console → Authentication → Users
2. Click "Add user"
3. Enter email and password for Device 1
4. Repeat for Device 2

---

### Step 2: Create User Documents in Firestore with Roles

Create two documents in the `users` collection:

**Document 1: `users/posdevice001@example.com`**
```json
{
  "uid": "posdevice001@example.com",
  "email": "posdevice001@example.com",
  "role": "pos",
  "deviceName": "BUS-001",
  "androidId": "e48d8154b4dc3378",
  "createdAt": "2026-01-09T00:00:00Z"
}
```

**Document 2: `users/posdevice002@example.com`**
```json
{
  "uid": "posdevice002@example.com",
  "email": "posdevice002@example.com",
  "role": "pos",
  "deviceName": "BUS-002",
  "androidId": "ca04c9993ebc9f65",
  "createdAt": "2026-01-09T00:00:00Z"
}
```

**Document 3: `users/dispatcher@example.com`** (the dispatcher dashboard user)
```json
{
  "uid": "dispatcher@example.com",
  "email": "dispatcher@example.com",
  "role": "dispatcher",
  "createdAt": "2026-01-09T00:00:00Z"
}
```

**How:**
1. Go to Firebase Console → Firestore → Create collection `users`
2. Add a document with ID = email address
3. Add the fields above

---

### Step 3: Deploy Firestore Rules

1. Go to Firebase Console → Firestore Database → Rules tab
2. Replace rules with content from [firestore.rules](firestore.rules)
3. Click **Publish**

**Important:** Deploy the same rules for BOTH projects:
- POS project: [untitled/firestore.rules](firestore.rules)
- Dispatcher project: [dispatcher_dashboard/firestore.rules](../dispatcher_dashboard/firestore.rules)

---

### Step 4: Deploy POS App to Devices

Deploy the updated POS app to both devices.

**On app startup:**
1. POS detects Android ID
2. Matches it to device credentials (BUS-001 or BUS-002)
3. Signs in automatically to Firebase
4. NFC login still works locally (unchanged)

**Logs to check:**
```
✅ Device signed in successfully: posdevice001@example.com
✅ POS device authenticated to Firebase
```

---

## 🔄 How It Works

### **Dispatcher Dashboard**
```
1. Dispatcher logs in (email: dispatcher@example.com)
   → Verified: role = 'dispatcher' ✅
2. Can create schedules (write to schedules collection)
3. Listens to schedules in real-time
4. Can update any field
5. Can read arrival reports
```

### **POS Device 1 (BUS-001)**
```
1. App starts → Auto-signs in as posdevice001@example.com
   → Verified: role = 'pos' ✅
2. Conductor taps NFC → reads conductorName locally
3. Trip finalized → updates ONLY dispatch fields:
   - driverName
   - conductorName
   - dispatchTime
   - status
   → Cannot create schedules ✅
   → Cannot modify other fields ✅
4. Can read schedules
5. Can create arrival reports
```

### **POS Device 2 (BUS-002)**
```
Same as Device 1, but with different credentials
```

---

## 📊 Firestore Rules Summary

| Collection | Creator | Reader | Updater |
|------------|---------|--------|---------|
| **arrivalReports** | POS only | Both | POS only |
| **schedules** | Dispatcher | Both | Dispatcher (all) + POS (dispatch fields only) |
| **users** | Self | Self | Self |
| **bookings** | User | User | User |

---

## 🔒 Security Features

✅ **Role-Based Access**  
- Dispatcher can do everything  
- POS limited to specific fields  

✅ **Device Traceability**  
- Each POS device has unique email  
- Can revoke one device without affecting others  

✅ **Offline Support**  
- Auth token cached on device  
- Syncs work offline → online  
- Token auto-refreshes on reconnect  

✅ **Audit Trail**  
- `request.auth.uid` in documents shows which device wrote  
- Combined with `driverName`, `conductorName` in payload  

---

## 🧪 Testing Checklist

- [ ] Created 2 Firebase users (pos device001 & device002)
- [ ] Created 3 user documents in Firestore with roles
- [ ] Deployed Option 3 Firestore rules
- [ ] POS app deployed to Device 1 (BUS-001)
- [ ] POS app deployed to Device 2 (BUS-002)
- [ ] Check console logs: `✅ Device signed in successfully`
- [ ] Dispatcher can create schedule
- [ ] POS can read schedule
- [ ] POS can update dispatch fields (finalize trip)
- [ ] Dispatcher can see updated schedule in real-time
- [ ] POS cannot create schedules (permission denied)
- [ ] POS cannot modify schedule fields other than dispatch

---

## 📝 Device Credential Summary

| Device | Android ID | Email | Password | Role |
|--------|-----------|-------|----------|------|
| BUS-001 | e48d8154b4dc3378 | posdevice001@example.com | Test1234. | pos |
| BUS-002 | ca04c9993ebc9f65 | posdevice002@example.com | Test1234. | pos |
| Dashboard | — | dispatcher@example.com | Test1234. | dispatcher |

---

## 🚀 How to Monitor

**Console logs on POS startup:**
```
🔍 Detected Android ID: e48d8154b4dc3378
🔄 Signing in POS device: BUS-001
✅ Device signed in successfully: posdevice001@example.com
✅ POS device authenticated to Firebase
```

**If auth fails:**
```
❌ Firebase Auth Error [user-not-found]: ...
⚠️ POS device authentication failed - check credentials in Firebase Console
```

**Firestore writes:**
- ✅ POS updates dispatch fields → Success
- ❌ POS tries to create schedule → Permission denied
- ✅ Dispatcher updates any field → Success

---

## ⚡ Key Differences from Option 2

| Aspect | Option 2 | Option 3 |
|--------|----------|---------|
| **Any authenticated user** | Can access schedules | ❌ No |
| **POS device** | Can create/update schedules | ❌ No (only update dispatch fields) |
| **Dispatcher** | Can do everything | ✅ Yes |
| **Role checking** | No rules checking | ✅ Yes, via `hasRole()` function |
| **Security** | Medium | High |

---

## 🆘 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Device not authenticated" | Firebase users not created | Create users in Firebase Console |
| "Device ID not registered" | Android ID not in mapping | Check correct Android ID, update service |
| "Permission denied" on schedule write | User doesn't have role | Check user document has correct role |
| "schedules/tripId" missing | Rules refer to non-existent document | Ensure document exists before update |

---

## 📚 File References

- **POS Device Auth**: [lib/services/pos_device_auth_service.dart](lib/services/pos_device_auth_service.dart)
- **POS Main App**: [lib/main.dart](lib/main.dart)
- **Dispatch Sync**: [lib/services/firebase_dispatch_service.dart](lib/services/firebase_dispatch_service.dart)
- **Arrival Sync**: [lib/services/arrival_report_sync_service.dart](lib/services/arrival_report_sync_service.dart)
- **Firestore Rules (POS)**: [firestore.rules](firestore.rules)
- **Firestore Rules (Dashboard)**: [../dispatcher_dashboard/firestore.rules](../dispatcher_dashboard/firestore.rules)

---

✅ **Ready to deploy!** Follow the setup steps above.
