# Dental App - Mobile Client (Patient Flutter App)

This is the patient-facing mobile application for the Dental Clinic queue management system.

## Features (Step 11)
- Authentication and session restoration with secure token storage.
- FCM device registration and push notifications.
- Multilingual localization: Uzbek (default), Russian, English.
- Catalog exploration: Specializations and Doctors with today's queue status.
- Queue participation: Join Queue, My Queue screen, people ahead count.
- In-person clinic QR check-in scanning.
- Patient self-cancellation.
- Local appointment reminders.
- Manual pull-to-refresh fallback on My Queue.

## Implementation Status

- **Step 11 implementation**: COMPLETE
- **Known deferred issue**: FCM notifications reach the physical device, but automatic My Queue state refresh from real-device FCM events is not yet reliably verified/working; manual refresh remains available. Realtime auto-refresh should NOT be described as fully working until further investigation.

