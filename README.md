# SilverGuard

An AI-powered Android SMS scam detection app that protects users — especially senior citizens — from fraudulent text messages using on-device machine learning.

![Flutter](https://img.shields.io/badge/Flutter-3.11-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.11-0175C2?logo=dart&logoColor=white)
![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-On_Device-7B68EE)
![Android](https://img.shields.io/badge/Android-Native-3DDC84?logo=android&logoColor=white)
![ML](https://img.shields.io/badge/ML-MobileBERT-FF6F00?logo=tensorflow&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)
![Storage](https://img.shields.io/badge/Storage-SQLite-003B57?logo=sqlite&logoColor=white)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Architecture Overview](#architecture-overview)
- [UI / UX Design](#ui--ux-design)
- [Data Models](#data-models)
- [Service Layer](#service-layer)
- [AI / ML Pipeline](#ai--ml-pipeline)
- [Scam Processing Architecture](#scam-processing-architecture)
- [Threat Classification](#threat-classification)
- [Notification System](#notification-system)
- [Permissions](#permissions)
- [Model Hosting](#model-hosting)
- [Database Schema](#database-schema)
- [Database Migrations](#database-migrations)
- [Performance Optimizations](#performance-optimizations)
- [Privacy & Security](#privacy--security)
- [Build Configuration](#build-configuration)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

SilverGuard is a Flutter-based Android application that reads, monitors, and classifies SMS messages in real time using an on-device ONNX machine learning model (MobileBERT). It runs entirely offline — no data is sent to any server — ensuring complete privacy.

The app is designed with elderly users in mind: when a scam or suspicious SMS is detected, it can alert trusted "guardian" contacts via SMS and show actionable notifications with **Dismiss** and **Report** buttons.

### Why SilverGuard?

SMS scam attacks disproportionately target senior citizens who may not recognize phishing patterns, fake bank alerts, or social engineering tactics. SilverGuard bridges this gap by:

- **Automating detection** — No technical knowledge required from the user
- **Alerting guardians** — Family members or caretakers are notified instantly
- **Running offline** — No internet dependency, no data leaves the device
- **Using real AI** — Not keyword matching, but a fine-tuned transformer model that understands context

### Key Design Principles

1. **Privacy First**: All processing happens on-device. Zero telemetry, zero cloud calls.
2. **Offline by Default**: The app works without any internet connection after initial setup.
3. **Senior-Friendly**: Large touch targets, high-contrast dark theme, minimal navigation.
4. **Non-Intrusive**: Runs silently in the background; only interrupts when threats are found.
5. **Actionable Alerts**: Notifications include one-tap Dismiss and Report actions.

---

## Features

### Real-Time SMS Monitoring

- Listens for incoming SMS in both foreground and background using Android's `SMS_RECEIVED` broadcast
- Automatically classifies new messages using the on-device AI model with highest priority
- Displays live protection status with scanning progress indicator
- Shows real-time badge counts for pending scam checks
- Background SMS handler registered via `another_telephony` for persistent monitoring
- SnackBar notifications for each new SMS received in the foreground

### AI-Powered Scam Detection

- **MobileBERT** model fine-tuned on SMS scam datasets and exported to ONNX
- Full **WordPiece tokenizer** implementation matching `google/mobilebert-uncased` tokenization
- Dual-input format: sender header (DLT ID / phone number) as `text_a`, message body as `text_b`
- Produces a continuous threat score from `0.0` (safe) to `1.0` (definite scam)
- Four-tier verdict system: SAFE → BORDERLINE → LIKELY SCAM → HIGH RISK SCAM
- Input tensors created as `Int64List` with shape `[1, 128]` for both `input_ids` and `attention_mask`
- Automatic tensor cleanup after inference to prevent memory leaks

### SMS Management

- **Fetch All SMS**: Bulk-load all SMS from the device into a local SQLite database
- **Categorized Views**: Three-tab interface for Unread, Read, and Sent messages
- **Contact Name Resolution**: Resolves phone numbers to contact names with flexible matching across ISD codes, leading zeros, and suffix matching
- **Database Statistics**: Comprehensive stats card showing:
  - Total SMS count
  - Received (unread + read) count
  - AI analyzed vs pending count
  - Threat breakdown (safe, uncertain, suspicious, scam)
  - Progress bar for analysis completion
- **Color-Coded Threat Badges**: Each SMS displays its threat level with color-coded indicators:
  - Green for safe (< 0.30)
  - Grey for unchecked (null)
  - Orange for uncertain (0.30–0.49)
  - Red-orange for suspicious (0.50–0.69)
  - Red for scam (≥ 0.70)
- **Expandable SMS Cards**: Tap to reveal full message body with threat score details

### Notification System

- **Immediate Alerts**: High-priority notifications for scam/suspicious SMS with threat percentage
- **Periodic Re-checks**: Configurable interval (5 min to 1 hour) to re-check pending alerts
- **Actionable Notifications**: Dismiss or Report directly from the notification shade
- **Background Support**: Notification actions work even when the app is killed, using a top-level `@pragma('vm:entry-point')` handler
- **Smart Guardian Detection**: Report button only appears if guardian contacts are configured
- **No-Guardian Fallback**: If Report is tapped with no guardians set, shows an info notification prompting setup

### Guardian Contacts

- Add trusted contacts from the phonebook or by manual entry
- When a scam SMS is reported, an alert is automatically sent via SMS to all guardians
- Duplicate guardian prevention (phone number uniqueness enforced)
- Alert message includes a truncated preview (100-char limit) of the scam SMS
- Silent SMS sending — no SMS compose window opens
- Multi-part SMS support for messages exceeding 160 characters
- Guardian cards show name, phone number, and date added

### Settings Page

- **Guardian Management**:
  - Add from device contacts (with multi-number picker if contact has multiple numbers)
  - Add manually via dialog (name + phone number fields)
  - Delete guardians with confirmation dialog
  - Empty state illustration when no guardians are configured
- **Notification Check Interval**:
  - Slider control with snap points at 5, 10, 15, 30, and 60 minutes
  - Live label showing current interval
  - Persisted to `SharedPreferences` across app restarts
  - Timer restarts automatically when interval changes

### Home Page Dashboard

- **Protection Status Card**: Large hero card showing active/inactive state with animated glow
- **SMS Monitoring Indicator**: Green dot when listener is active, grey when inactive
- **AI Protection Indicator**: Green dot when model is loaded, shows queue count during scanning
- **Permission Card**: Tap-to-enable card for SMS permissions
- **Fetch All SMS Button**: One-tap bulk import with loading spinner
- **Statistics Card**: Received / Analyzed / Threats breakdown with progress indicator
- **SMS Tabs**: Three-tab view (Unread / Read / Sent) with individual scroll controllers

---

## Tech Stack

| Layer             | Technologies                              |
| ----------------- | ----------------------------------------- |
| **Framework**     | Flutter 3.11, Dart 3.11                   |
| **Platform**      | Android (native, Kotlin)                  |
| **ML Runtime**    | ONNX Runtime (`flutter_onnxruntime`)      |
| **ML Model**      | MobileBERT (fine-tuned, exported to ONNX) |
| **Database**      | SQLite (`sqflite`)                        |
| **SMS Reading**   | `flutter_sms_inbox`                       |
| **SMS Listening** | `another_telephony`                       |
| **SMS Sending**   | `another_telephony` (silent send)         |
| **Contacts**      | `flutter_contacts`                        |
| **Notifications** | `flutter_local_notifications`             |
| **Permissions**   | `permission_handler`                      |
| **Preferences**   | `shared_preferences`                      |
| **Path Utils**    | `path` (for database path joining)        |
| **Design**        | Material 3, dark theme, custom gradients  |

### Dependencies (pubspec.yaml)

```yaml
dependencies:
  another_telephony: ^0.4.1 # SMS listening + sending
  flutter_contacts: ^1.1.9+2 # Contact picker and lookup
  flutter_local_notifications: ^20.1.0 # Local notification system
  flutter_onnxruntime: ^1.6.3 # ONNX model inference
  flutter_sms_inbox: ^1.0.4 # Read SMS inbox
  path: ^1.9.1 # Path utilities
  permission_handler: ^12.0.1 # Runtime permissions
  shared_preferences: ^2.5.4 # Persistent key-value storage
  sqflite: ^2.4.2 # SQLite database
```

---

## Getting Started

### Prerequisites

- Flutter SDK 3.11+
- Android SDK (API 21+)
- Java 17+ (required by the Android Gradle plugin)
- A physical Android device (SMS APIs don't work on emulators)
- ~200MB free storage (for the ONNX model + app)

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/tanishqmudaliar/silverguard.git
   cd silverguard
   ```

2. **Download the ML model**

   The ONNX model is hosted on Hugging Face (too large for GitHub):

   👉 https://huggingface.co/tanishqmudaliar/SilverGuard

   Download and place the files in `assets/ml/`:

   ```
   assets/ml/
   ├── silver_guard.onnx
   ├── vocab.txt
   └── model_config.json
   ```

3. **Install dependencies**

   ```bash
   flutter pub get
   ```

4. **Run on a physical device**

   ```bash
   flutter run
   ```

5. **Build a release APK** (optional)

   ```bash
   flutter build apk --release
   ```

   The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

### First Run

1. **Grant Permissions**: The app requests SMS, Phone, Contacts, and Notification permissions on first launch. Tap "Grant Permissions" or the permission card.
2. **Wait for AI Model**: The status message will show "Loading AI model..." — wait for it to complete.
3. **Fetch All SMS**: Tap the "Fetch All SMS" card to bulk-import existing messages into the database.
4. **Background Scanning**: The AI begins scanning all unchecked messages automatically. Progress is shown in the app bar.
5. **Add Guardians**: Navigate to Settings (gear icon) to add trusted contacts who will be alerted about scams.

### Useful Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run in debug mode on connected device
flutter run --release    # Run in release mode
flutter build apk        # Build release APK
flutter clean            # Clean build artifacts
flutter analyze          # Run Dart analyzer
flutter test             # Run unit tests
```

---

## Project Structure

```
silverguard/
├── lib/
│   ├── main.dart                        App entry point, HomePage, service init, SMS tabs
│   ├── models/
│   │   ├── sms_message.dart             SmsMessage, UnreadSms, ReadSms, SentSms models
│   │   └── guardian.dart                Guardian contact model
│   ├── pages/
│   │   └── settings_page.dart           Guardian CRUD, notification interval slider
│   └── services/
│       ├── scam_detector_service.dart   ONNX inference + WordPiece tokenizer
│       ├── scam_processor_service.dart  LIFO background processing queue
│       ├── sms_service.dart             SMS fetching, listening, storage
│       ├── contacts_service.dart        Phone number → contact name lookup
│       ├── database_helper.dart         SQLite CRUD for all 5 tables
│       ├── notification_service.dart    Scam alert notifications + actions
│       ├── permission_service.dart      Runtime permission management
│       └── sms_sender_service.dart      Silent SMS sending (guardian alerts)
├── assets/
│   ├── ml/
│   │   ├── silver_guard.onnx            Trained ONNX model (hosted externally)
│   │   ├── vocab.txt                    WordPiece vocabulary (30,522 tokens)
│   │   └── model_config.json            Model config (labels, I/O names)
│   └── MODEL_HOSTING.md                 Model download instructions
├── android/
│   ├── app/
│   │   ├── build.gradle.kts             App-level Gradle config (Java 17, desugaring)
│   │   └── src/main/AndroidManifest.xml Permissions, SMS broadcast receiver
│   ├── build.gradle.kts                 Project-level Gradle config
│   └── settings.gradle.kts              Gradle settings
├── pubspec.yaml                         Flutter dependencies & asset declarations
├── analysis_options.yaml                Dart linting rules
└── README.md
```

---

## Architecture Overview

SilverGuard follows a **service-oriented singleton architecture** where each service is a lazily-initialized singleton accessed via `ServiceName.instance`. Services communicate through callbacks and direct method calls.

### Service Initialization Sequence

```
App Start (main.dart)
  │
  ├─► PermissionService.areAllPermissionsGranted()
  │     └─ If denied → Show permission card, wait for user
  │
  ├─► NotificationService.initialize()
  │     └─ Creates Android notification channels
  │     └─ Loads saved check interval from SharedPreferences
  │
  ├─► ScamProcessorService.initialize()
  │     └─► ScamDetectorService.initialize()
  │           └─ Load vocab.txt → Build tokenizer
  │           └─ Load silver_guard.onnx → Create OrtSession
  │
  ├─► SmsService.startListeningForIncomingSms()
  │     └─ Register telephony broadcast receiver
  │     └─ Set onNewSmsReceived callback → UI refresh
  │
  ├─► ScamProcessorService.startProcessing()
  │     └─ Load unchecked messages from DB → Stack
  │     └─ Start _processLoop() (runs indefinitely)
  │     └─ Set onItemProcessed callback → UI refresh
  │
  └─► NotificationService.startPeriodicCheck()
        └─ Run _checkPendingAlerts() immediately
        └─ Start periodic Timer at configured interval
```

### Service Dependency Graph

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  SmsService │────►│ ScamProcessor    │────►│ ScamDetector    │
│             │     │ Service          │     │ Service         │
│ • fetch     │     │                  │     │                 │
│ • listen    │     │ • LIFO stack     │     │ • tokenize      │
│ • store     │     │ • rate limiting  │     │ • ONNX infer    │
└──────┬──────┘     └────────┬─────────┘     └─────────────────┘
       │                     │
       ▼                     ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Contacts   │     │ Database         │     │ Notification    │
│  Service    │     │ Helper           │     │ Service         │
│             │     │                  │     │                 │
│ • lookup    │     │ • SQLite CRUD    │     │ • alerts        │
│ • normalize │     │ • batch ops      │     │ • periodic      │
│ • variants  │     │ • statistics     │     │ • actions       │
└─────────────┘     └──────────────────┘     └────────┬────────┘
                                                      │
                                                      ▼
                                             ┌─────────────────┐
                                             │ SmsSender       │
                                             │ Service         │
                                             │                 │
                                             │ • silent send   │
                                             │ • multipart     │
                                             └─────────────────┘
```

### Data Flow: Incoming SMS

```
Android SMS_RECEIVED Broadcast
  │
  ├─► another_telephony (foreground handler)
  │     └─► SmsService._onNewSmsReceived()
  │           ├─ ContactsService.getContactName()
  │           ├─ DatabaseHelper.insertSms()        → sms table
  │           ├─ DatabaseHelper.insertUnread()      → unread table
  │           ├─ ScamProcessorService.pushIncoming() → top of stack
  │           └─ onNewSmsReceived callback → UI SnackBar
  │
  └─► another_telephony (background handler)
        └─► backgroundMessageHandler() (top-level function)
              └─ Logs only; foreground picks up on resume
```

### Data Flow: Scam Detection

```
ScamProcessorService._processLoop()
  │
  ├─ Pop _ProcessingItem from stack (LIFO)
  ├─► ScamDetectorService.detectScam(address, body)
  │     ├─ _WordPieceTokenizer.encode(address, body)
  │     ├─ Create OrtValue tensors [1, 128]
  │     ├─ session.run(inputs)
  │     ├─ Extract threat_score from output
  │     └─ Return ScamDetectionResult
  │
  ├─ DatabaseHelper.updateUnreadThreatScore() or updateReadThreatScore()
  │
  ├─ If threat_score < 0.50 AND table == 'unread':
  │     └─ DatabaseHelper.updateUnreadDecision(id, 'safe')
  │
  ├─ If threat_score ≥ 0.50 AND table == 'unread':
  │     └─ NotificationService.showScamAlert()
  │
  ├─ onItemProcessed callback → UI refresh
  │
  └─ Future.delayed(rate limit based on priority)
```

---

## UI / UX Design

### Theme

SilverGuard uses a **Material 3 dark theme** with a cyan/red accent palette designed for readability:

```dart
ColorScheme.dark(
  primary: Color(0xFF00D4FF),      // Cyan — primary actions, links, active states
  secondary: Color(0xFFFF3366),    // Red-pink — danger, scam indicators, delete
  surface: Color(0xFF121212),      // Dark grey — card backgrounds
)
scaffoldBackgroundColor: Color(0xFF0A0A0A)  // Near-black — page background
```

### Color System

| Color Code | Name         | Usage                                         |
| ---------- | ------------ | --------------------------------------------- |
| `#00D4FF`  | Cyan         | Primary brand, active states, safe indicators |
| `#0099CC`  | Dark Cyan    | Gradient endpoint, secondary brand            |
| `#FF3366`  | Red-Pink     | Scam alerts, delete buttons, danger states    |
| `#CC0033`  | Dark Red     | Gradient endpoint for danger                  |
| `#4CAF50`  | Green        | Success states, "safe" badge                  |
| `#00FF88`  | Bright Green | Active indicator dots                         |
| `#FF9800`  | Orange       | Suspicious/warning states                     |
| `#F44336`  | Red          | Scam badge, high-threat notification color    |
| `#9E9E9E`  | Grey         | Unchecked/pending states                      |
| `#1E1E1E`  | Dark Card    | Card backgrounds                              |
| `#1A1A1A`  | App Bar      | AppBar background                             |
| `#333333`  | Border       | Card borders, dividers                        |

---

## Data Models

### SmsMessage

The base model for raw SMS storage in the `sms` table:

```dart
{
  id: int?,
  address: String,          // Sender phone number or DLT header (e.g., "JD-SBIINB")
  body: String,             // Full message text
  date: int,                // Timestamp (milliseconds since epoch)
  type: int,                // 1 = received, 2 = sent
  read: int,                // 0 = unread, 1 = read
  serviceCenter: String?,   // SMSC address (nullable)
  createdAt: int,           // When inserted into local DB
}
```

### UnreadSms

Received messages that haven't been read, with AI classification fields:

```dart
{
  id: int?,
  address: String,
  contactName: String?,     // Resolved from device contacts (null if unknown sender)
  body: String,
  date: int,
  serviceCenter: String?,
  createdAt: int,
  updatedAt: int,           // Last modification timestamp
  threatScore: double?,     // null = not yet classified, 0.0–1.0 = AI threat level
  decision: String?,        // null = pending user action
                            // 'safe' = auto-marked (score < 0.50)
                            // 'dismissed' = user tapped Dismiss on notification
                            // 'reported' = user tapped Report, guardians alerted
}
```

The `displayName` getter returns `contactName ?? address` for UI display.

### ReadSms

Received messages that have been read. Same as `UnreadSms` but without the `decision` field — read messages don't trigger actionable notifications:

```dart
{
  id: int?,
  address: String,
  contactName: String?,
  body: String,
  date: int,
  serviceCenter: String?,
  createdAt: int,
  updatedAt: int,
  threatScore: double?,     // null = pending, 0.0–1.0 = AI threat level
}
```

### SentSms

Messages sent by the user. No AI fields — sent messages are never scanned:

```dart
{
  id: int?,
  address: String,
  contactName: String?,
  body: String,
  date: int,
  serviceCenter: String?,
  createdAt: int,
  updatedAt: int,
}
```

### Guardian

Trusted contact who receives scam alert SMS messages:

```dart
{
  id: int?,
  name: String,             // Display name
  phone: String,            // Phone number (unique, spaces stripped)
  createdAt: int,           // When added as guardian
}
```

All models include `toMap()` for database insertion and `factory fromMap()` for database reads.

---

## Service Layer

### ScamDetectorService

**File**: `lib/services/scam_detector_service.dart`

The core AI inference service. Singleton accessed via `ScamDetectorService.instance`.

**Responsibilities**:

- Load the ONNX model from Flutter assets
- Load and parse the WordPiece vocabulary (30,522 tokens)
- Tokenize SMS (header + body) into BERT-compatible input tensors
- Run ONNX inference and extract the threat score
- Map the score to a human-readable verdict

**Key Methods**:

| Method                      | Description                                             |
| --------------------------- | ------------------------------------------------------- |
| `initialize()`              | Load vocab.txt and silver_guard.onnx, create OrtSession |
| `detectScam(address, body)` | Tokenize, infer, return `ScamDetectionResult`           |
| `dispose()`                 | Close OrtSession and free resources                     |

**Internal `_WordPieceTokenizer`**:

| Method                 | Description                                                         |
| ---------------------- | ------------------------------------------------------------------- |
| `loadVocab(content)`   | Parse vocab.txt into `Map<String, int>`                             |
| `encode(textA, textB)` | Full BERT tokenization pipeline → `{input_ids, attention_mask}`     |
| `_basicTokenize(text)` | Clean, lowercase, split on whitespace/punctuation                   |
| `_wordPiece(word)`     | Sub-word splitting with `##` prefix; returns `[UNK]` if > 200 chars |

### ScamProcessorService

**File**: `lib/services/scam_processor_service.dart`

Background processing queue that manages the order and rate of AI inference.

**Responsibilities**:

- Maintain a LIFO stack of messages awaiting classification
- Process stack items with rate limiting per priority tier
- Push incoming SMS to the top of the stack for immediate classification
- Notify UI via callbacks when items are processed

**Key Methods**:

| Method                      | Description                                       |
| --------------------------- | ------------------------------------------------- |
| `initialize()`              | Initialize the underlying `ScamDetectorService`   |
| `startProcessing()`         | Load unchecked messages, start `_processLoop()`   |
| `pushIncoming(sms)`         | Push a new SMS to top of stack (highest priority) |
| `reloadUncheckedMessages()` | Re-query DB and rebuild the stack                 |
| `stopProcessing()`          | Stop the background loop                          |

**Callbacks**:

- `onItemProcessed(id, table, threatScore)` — Called after each item is classified
- `onProcessingComplete` — Called when the processing loop exits

### SmsService

**File**: `lib/services/sms_service.dart`

Coordinates SMS reading from the device, real-time listening, and database storage.

**Responsibilities**:

- Fetch all SMS from the device inbox using `flutter_sms_inbox`
- Distribute messages into `sms`, `unread`, `read`, and `sent` tables
- Listen for incoming SMS using `another_telephony`
- Resolve contact names and push new messages to the scam processor

**Key Methods**:

| Method                                             | Description                                          |
| -------------------------------------------------- | ---------------------------------------------------- |
| `fetchAndStoreAllSms()`                            | Bulk-read all device SMS, categorize, insert into DB |
| `startListeningForIncomingSms()`                   | Register foreground + background SMS handlers        |
| `getUnreadSms()` / `getReadSms()` / `getSentSms()` | Read from database                                   |
| `getStats()`                                       | Aggregate statistics from all tables                 |

**Background Handler**: The `backgroundMessageHandler()` function is a top-level `@pragma('vm:entry-point')` function required by `another_telephony` for SMS received while the app is in the background. It logs the message; the foreground handler processes it when the app resumes.

### ContactsService

**File**: `lib/services/contacts_service.dart`

Provides fast phone number → contact name lookups by pre-loading all device contacts into memory.

**Responsibilities**:

- Load all contacts with phone numbers into a `Map<String, String>`
- Generate multiple normalized phone variants for flexible matching
- Handle ISD codes (+91, +1, +44), leading zeros, and suffix matching

**Phone Variant Generation**:

For a phone number like `+91 98765 43210`, the service generates:

```
+919876543210    (full with +)
919876543210     (full digits)
9876543210       (without leading zeros)
9876543210       (last 10 digits)
19876543210      (last 11 digits) — if applicable
9876543210       (without country code 91)
```

**Matching Strategy**:

1. Generate variants of the incoming phone number
2. Try exact match against all stored variants
3. Fallback: try suffix matching from 10 digits down to 7 digits
4. Return `null` if no match found

### DatabaseHelper

**File**: `lib/services/database_helper.dart`

SQLite database manager for all five tables. Singleton with lazy initialization.

**Database**: `silverguard.db` (current schema version: 3)

**Key Features**:

- CRUD operations for all tables (sms, unread, read, sent, guardians)
- Batch insert operations for bulk SMS import performance
- Indexed columns for fast queries (`address`, `date`)
- `UNIQUE` constraints to prevent duplicate entries
- Aggregate statistics query combining counts from multiple tables
- Schema migrations (v1 → v2 → v3)

### NotificationService

**File**: `lib/services/notification_service.dart`

Manages Android local notifications with actionable buttons.

**Notification Channel**: `scam_alerts` — "Scam Alerts"

**Key Features**:

- `BigTextStyleInformation` for expandable notification content
- Two action buttons: Dismiss and Report (Report only shown if guardians exist)
- Foreground response handler (`_onNotificationResponse`)
- Background response handler (`_onBackgroundNotificationResponse`, top-level)
- Configurable periodic timer that re-checks for pending alerts
- Interval persisted to `SharedPreferences`

### PermissionService

**File**: `lib/services/permission_service.dart`

Static utility class for managing runtime permissions.

**Required Permissions**:

1. `Permission.sms` — Read and receive SMS
2. `Permission.phone` — Phone state (required by `another_telephony`)
3. `Permission.contacts` — Contact name lookup
4. `Permission.notification` — Show notifications (Android 13+)

### SmsSenderService

**File**: `lib/services/sms_sender_service.dart`

Sends SMS messages silently using the `Telephony` API without opening the compose window.

**Key Features**:

- Silent background sending (no UI)
- Automatic multipart splitting for messages > 160 characters
- Validation of empty number/body before sending

---

## AI / ML Pipeline

### Model Architecture

- **Base Model**: `google/mobilebert-uncased` (24.7M parameters, optimized for mobile)
- **Fine-Tuning**: Trained on SMS scam classification datasets
- **Export Format**: ONNX (Open Neural Network Exchange) for cross-platform inference
- **Input Schema**: Two input tensors:
  - `input_ids`: Int64 tensor of shape `[1, 128]` — tokenized text
  - `attention_mask`: Int64 tensor of shape `[1, 128]` — 1 for real tokens, 0 for padding
- **Output**: Single float `threat_score` — softmax probability for the scam class
- **Max Sequence Length**: 128 tokens

### Model Configuration (`model_config.json`)

```json
{
  "max_length": 128,
  "do_lower_case": true,
  "model_type": "mobilebert",
  "vocab_file": "vocab.txt",
  "model_file": "silver_guard.onnx",
  "labels": {
    "0": "ham",
    "1": "scam"
  },
  "input_names": ["input_ids", "attention_mask"],
  "output_name": "threat_score",
  "input_format": "HEADER [SEP] message_text"
}
```

### WordPiece Tokenizer

The app includes a **complete WordPiece tokenizer** implementation in Dart that mirrors the `google/mobilebert-uncased` tokenization pipeline. This avoids any dependency on Python or external tokenizer libraries.

#### Vocabulary

- **File**: `vocab.txt` — One token per line, 30,522 tokens total
- **Special Tokens**:
  - `[PAD]` = 0 — Padding token
  - `[UNK]` = 100 — Unknown token (for out-of-vocabulary words)
  - `[CLS]` = 101 — Classification token (start of sequence)
  - `[SEP]` = 102 — Separator token (between segments / end of sequence)

#### Tokenization Pipeline

```
Input: address = "JD-SBIINB", body = "Dear customer, your account..."

Step 1 — Text Cleaning:
  • Remove null bytes, replacement characters, control chars
  • Normalize tabs/newlines/carriage returns to spaces
  • Keep printable characters

Step 2 — Lowercasing:
  address → "jd-sbiinb"
  body → "dear customer, your account..."

Step 3 — Basic Tokenization:
  Split on whitespace and punctuation (punctuation becomes its own token)
  "jd-sbiinb" → ["jd", "-", "sbi", "##in", "##b"]
  "dear customer, your account..." → ["dear", "customer", ",", "your", "account", ".", ".", "."]

Step 4 — WordPiece Sub-word Splitting:
  For each basic token, find the longest matching prefix in vocab:
  "customer"  → ["customer"]        (in vocab)
  "sbiinb"    → ["sb", "##iin", "##b"] (sub-word split)
  Words > 200 chars → [UNK]

Step 5 — Encoding with Special Tokens:
  [CLS] jd - sb ##iin ##b [SEP] dear customer , your account . . . [SEP] [PAD] [PAD] ...

Step 6 — Create Tensors:
  input_ids:      [101, 29421, 118, 24829, ...tokens..., 102, 0, 0, ...]  (length 128)
  attention_mask: [1,   1,     1,   1,     ...1s...,     1,   0, 0, ...]  (length 128)
```

#### Truncation Strategy

When `text_a + text_b` exceeds the 128-token budget (minus 3 special tokens = 125 usable tokens):

1. Compare lengths of tokenized `text_a` and `text_b`
2. Remove one token at a time from the **longer** sequence
3. Alternate until total fits within budget
4. This ensures both inputs are preserved as much as possible

### Inference Flow

```
SMS Received
  │
  ├─ Tokenize:
  │   address (text_a) + body (text_b) → {input_ids, attention_mask}
  │
  ├─ Create Tensors:
  │   Int64List → OrtValue.fromList(data, [1, 128])
  │
  ├─ Run Inference:
  │   session.run({'input_ids': tensor, 'attention_mask': tensor})
  │
  ├─ Extract Score:
  │   results['threat_score'] → double (0.0 to 1.0)
  │
  ├─ Create Verdict:
  │   ≥ 0.80 → HIGH RISK SCAM
  │   ≥ 0.55 → LIKELY SCAM
  │   ≥ 0.40 → BORDERLINE
  │   < 0.40 → SAFE
  │
  ├─ Clean Up:
  │   Dispose input tensors and output tensors
  │
  └─ Return ScamDetectionResult {threatScore, verdict, note, isScam}
```

### Empty Message Handling

If the message body is empty or whitespace-only, the detector immediately returns:

```dart
ScamDetectionResult(
  threatScore: 0.0,
  verdict: 'EMPTY',
  note: 'Empty message body',
  isScam: false,
)
```

---

## Scam Processing Architecture

The `ScamProcessorService` uses a **LIFO (Last-In-First-Out) stack** with three priority levels to ensure new incoming messages are classified first while still processing the backlog.

### Priority Levels

| Priority   | Source              | Delay Between Items | Position in Stack     | Use Case                         |
| ---------- | ------------------- | ------------------- | --------------------- | -------------------------------- |
| `incoming` | New SMS (real-time) | 50ms                | Top (processed first) | User just received a message     |
| `unread`   | Existing unread SMS | 150ms               | Middle                | Pre-existing unread messages     |
| `read`     | Existing read SMS   | 400ms               | Bottom                | Historical messages, low urgency |

### Stack Loading Order

When `startProcessing()` is called:

1. Query `read` table for `threat_score IS NULL`, ordered by `date ASC` (oldest first)
2. Push all read messages onto the stack → they form the **bottom**
3. Query `unread` table for `threat_score IS NULL`, ordered by `date ASC`
4. Push all unread messages onto the stack → they form the **top**

Since it's LIFO, unread messages (on top) are processed before read messages (on bottom).

### Processing Loop

```dart
while (_isRunning) {
  if (_stack.isEmpty) {
    // Create a Completer and await it
    // Fulfilled when pushIncoming() or reloadUncheckedMessages() is called
    _itemAvailable = Completer<void>();
    await _itemAvailable!.future;
    continue;
  }

  final item = _stack.removeLast();  // LIFO pop

  // Run AI inference
  final result = await _detector.detectScam(item.address, item.body);

  // Update database
  if (item.table == 'unread') {
    await _dbHelper.updateUnreadThreatScore(item.id, result.threatScore);
    if (result.threatScore < 0.50) {
      await _dbHelper.updateUnreadDecision(item.id, 'safe');
    } else {
      await _notificationService.showScamAlert(...);
    }
  } else {
    await _dbHelper.updateReadThreatScore(item.id, result.threatScore);
  }

  // Rate limiting
  await Future.delayed(Duration(milliseconds: delay));
}
```

### Wake-Up Mechanism

When the stack is empty, the loop awaits a `Completer`. It is woken up when:

- `pushIncoming()` is called (new SMS arrives)
- `reloadUncheckedMessages()` is called (user taps Fetch All SMS)

The Completer is completed and set to `null`, allowing the loop to continue.

---

## Threat Classification

| Threat Score  | Verdict        | isScam | Auto Decision (Unread) | Notification |
| ------------- | -------------- | ------ | ---------------------- | ------------ |
| `< 0.30`      | SAFE           | false  | `safe` (auto-mark)     | No           |
| `0.30 – 0.39` | SAFE           | false  | `safe` (auto-mark)     | No           |
| `0.40 – 0.49` | BORDERLINE     | false  | `safe` (auto-mark)     | No           |
| `0.50 – 0.54` | LIKELY SCAM    | true   | —                      | Yes          |
| `0.55 – 0.69` | LIKELY SCAM    | true   | —                      | Yes          |
| `0.70 – 0.79` | LIKELY SCAM    | true   | —                      | Yes          |
| `≥ 0.80`      | HIGH RISK SCAM | true   | —                      | Yes          |

### Decision States (Unread Only)

| Decision    | How It's Set                        | Meaning                                 |
| ----------- | ----------------------------------- | --------------------------------------- |
| `null`      | Default                             | Not yet reviewed by user or auto-system |
| `safe`      | Auto-set when `threat_score < 0.50` | AI determined the message is safe       |
| `dismissed` | User taps "Dismiss" on notification | User acknowledged and dismissed         |
| `reported`  | User taps "Report" on notification  | Guardians were alerted via SMS          |

### Notification Trigger Logic

A notification is shown when ALL of the following are true:

1. The message is from the `unread` table
2. `threat_score ≥ 0.50`
3. `NotificationService` is initialized

Periodic re-checks additionally require: 4. `decision IS NULL` (user hasn't acted on it yet)

---

## Notification System

### Scam Alert Notifications

When the AI detects a suspicious or scam SMS (threat_score ≥ 0.50), a notification is shown:

**Channel**: `scam_alerts` — "Scam Alerts"

**Visual Appearance**:

- **Color**: Red (`#F44336`) for scam (≥ 0.70), Orange (`#FF9800`) for suspicious (0.50–0.69)
- **Title**: `SCAM DETECTED` or `SUSPICIOUS SMS`
- **Body**: `From <address>: <truncated body (80 chars)>`
- **Expanded**: `BigTextStyleInformation` showing full sender and body
- **Summary**: `Tap to open app`

**Action Buttons**:

| Action    | Behavior                                                                             |
| --------- | ------------------------------------------------------------------------------------ |
| `Dismiss` | Sets `decision = 'dismissed'` in unread table; cancels the notification              |
| `Report`  | Sets `decision = 'reported'`; sends SMS alert to all guardians; cancels notification |

The `Report` button is only included if at least one guardian contact exists. If the user taps Report but no guardians are configured (edge case: guardians deleted between notification show and tap), an informational notification is shown instead:

```
Title: "No Guardian Contact Set"
Body: "Please add a guardian contact in Settings to enable scam reporting."
```

### Notification Payload

Each notification carries a JSON payload for action handling:

```json
{
  "id": 42,
  "table": "unread",
  "address": "+919876543210",
  "body": "Dear customer, your account has been...",
  "threatScore": 0.87
}
```

### Background Action Handler

Notification actions must work even when the app is killed. This is achieved with a top-level `@pragma('vm:entry-point')` function:

```dart
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) async {
  // Parse payload JSON
  // Cancel notification
  // Update database decision
  // If Report: send SMS to all guardians
}
```

This function runs in a separate isolate. It directly accesses `DatabaseHelper` and `SmsSenderService` without going through the main app lifecycle.

### Periodic Checks

The `NotificationService` runs a periodic timer to catch pending alerts:

```
Timer.periodic(Duration(minutes: interval), (_) => _checkPendingAlerts())
```

**Query**: `SELECT * FROM unread WHERE decision IS NULL AND threat_score IS NOT NULL AND threat_score >= 0.50 ORDER BY date DESC`

Each result triggers a `showScamAlert()` call, re-firing the notification if the user hasn't acted on it.

**Default Interval**: 30 minutes

**Configurable Values**: 5, 10, 15, 30, or 60 minutes (stored in `SharedPreferences` under key `notification_check_interval_minutes`)

---

## Permissions

| Permission             | Android Manifest                        | Purpose                                                 |
| ---------------------- | --------------------------------------- | ------------------------------------------------------- |
| **READ_SMS**           | `android.permission.READ_SMS`           | Read existing SMS from device inbox (bulk import)       |
| **SEND_SMS**           | `android.permission.SEND_SMS`           | Send guardian alert SMS silently in background          |
| **RECEIVE_SMS**        | `android.permission.RECEIVE_SMS`        | Listen for incoming SMS via broadcast receiver          |
| **READ_PHONE_STATE**   | `android.permission.READ_PHONE_STATE`   | Required by `another_telephony` for SMS functions       |
| **READ_CONTACTS**      | `android.permission.READ_CONTACTS`      | Load device contacts for phone number resolution        |
| **POST_NOTIFICATIONS** | `android.permission.POST_NOTIFICATIONS` | Show scam alert notifications (required on Android 13+) |

### Permission Request Flow

```
App Launch
  │
  ├─ PermissionService.areAllPermissionsGranted()
  │   └─ Check all 4 permissions
  │
  ├─ If all granted:
  │   └─ Proceed to _initializeServices()
  │
  └─ If any denied:
      └─ Show permission card with "TAP TO ENABLE"
          │
          ├─ User taps card
          │   └─ PermissionService.requestAllPermissions()
          │       ├─ If all granted → _initializeServices()
          │       └─ If any denied:
          │           ├─ Check isAnyPermissionPermanentlyDenied()
          │           └─ If permanently denied → Show dialog:
          │               "Please enable in app settings"
          │               [CANCEL] [OPEN SETTINGS]
          │
          └─ PermissionService.openSettings()
              └─ Opens Android app settings page
```

### Permanently Denied Handling

If a permission is permanently denied (user selected "Don't ask again"), the app shows an `AlertDialog` with two options:

1. **CANCEL**: Dismiss the dialog; app continues with limited functionality
2. **OPEN SETTINGS**: Opens Android's app-specific settings page where the user can manually toggle permissions

---

## Model Hosting

The trained ONNX model (`silver_guard.onnx`) exceeds GitHub's 100MB file size limit and is hosted externally on Hugging Face:

👉 **https://huggingface.co/tanishqmudaliar/SilverGuard**

### Available Files

| File                | Size    | Description                                         |
| ------------------- | ------- | --------------------------------------------------- |
| `silver_guard.onnx` | ~100MB+ | Fine-tuned MobileBERT ONNX model for scam detection |
| `vocab.txt`         | ~227KB  | WordPiece vocabulary — 30,522 tokens, one per line  |
| `model_config.json` | <1KB    | Model configuration (labels, I/O tensor names)      |

### Setup Instructions

1. Visit https://huggingface.co/tanishqmudaliar/SilverGuard
2. Download all three files
3. Place them in the `assets/ml/` directory:

```
assets/ml/
├── silver_guard.onnx
├── vocab.txt
└── model_config.json
```

4. Ensure `pubspec.yaml` includes the asset declaration:

```yaml
flutter:
  assets:
    - assets/ml/
```

5. Run `flutter clean && flutter pub get` before building

### Why External Hosting?

- GitHub enforces a strict **100MB** file size limit per file
- Git LFS is an option but adds complexity and bandwidth costs
- Hugging Face provides free, versioned model hosting optimized for ML artifacts
- Separating code from model weights follows ML best practices

---

## Database Schema

SilverGuard uses SQLite (`silverguard.db`, schema version 3) with five tables:

### `sms` — Raw SMS Storage

Stores every SMS fetched from the device, exactly as received. This is the source-of-truth table.

| Column           | Type    | Constraint  | Description                |
| ---------------- | ------- | ----------- | -------------------------- |
| `id`             | INTEGER | PRIMARY KEY | Auto-increment             |
| `address`        | TEXT    | NOT NULL    | Sender address             |
| `body`           | TEXT    | NOT NULL    | Message body               |
| `date`           | INTEGER | NOT NULL    | Timestamp (ms since epoch) |
| `type`           | INTEGER | NOT NULL    | 1 = received, 2 = sent     |
| `read`           | INTEGER | NOT NULL    | 0 = unread, 1 = read       |
| `service_center` | TEXT    | —           | Service center (nullable)  |
| `created_at`     | INTEGER | NOT NULL    | When inserted into app DB  |

**Unique Constraint**: `UNIQUE(address, date, body)` — Prevents duplicate entries on re-fetch.

**Indexes**: `idx_sms_address` on `address`, `idx_sms_date` on `date`

### `unread` — Received + Unread (with AI scoring)

Received messages that haven't been read by the user. These are the primary targets for scam detection.

| Column           | Type    | Constraint  | Description                                         |
| ---------------- | ------- | ----------- | --------------------------------------------------- |
| `id`             | INTEGER | PRIMARY KEY | Auto-increment                                      |
| `address`        | TEXT    | NOT NULL    | Sender address                                      |
| `contact_name`   | TEXT    | —           | Resolved contact name (nullable)                    |
| `body`           | TEXT    | NOT NULL    | Message body                                        |
| `date`           | INTEGER | NOT NULL    | Timestamp                                           |
| `service_center` | TEXT    | —           | Service center (nullable)                           |
| `created_at`     | INTEGER | NOT NULL    | When inserted                                       |
| `updated_at`     | INTEGER | NOT NULL    | Last modification                                   |
| `threat_score`   | REAL    | —           | AI threat score 0.0–1.0 (NULL = not yet classified) |
| `decision`       | TEXT    | —           | `safe` / `dismissed` / `reported` (NULL = pending)  |

**Unique Constraint**: `UNIQUE(address, date, body)`

**Indexes**: `idx_unread_address` on `address`, `idx_unread_date` on `date`

### `read` — Received + Read (with AI scoring)

Same schema as `unread` but **without** the `decision` column. Read messages are scored by AI for statistics but don't trigger actionable notifications.

| Column           | Type    | Constraint  | Description                                         |
| ---------------- | ------- | ----------- | --------------------------------------------------- |
| `id`             | INTEGER | PRIMARY KEY | Auto-increment                                      |
| `address`        | TEXT    | NOT NULL    | Sender address                                      |
| `contact_name`   | TEXT    | —           | Resolved contact name                               |
| `body`           | TEXT    | NOT NULL    | Message body                                        |
| `date`           | INTEGER | NOT NULL    | Timestamp                                           |
| `service_center` | TEXT    | —           | Service center                                      |
| `created_at`     | INTEGER | NOT NULL    | When inserted                                       |
| `updated_at`     | INTEGER | NOT NULL    | Last modification                                   |
| `threat_score`   | REAL    | —           | AI threat score 0.0–1.0 (NULL = not yet classified) |

**Indexes**: `idx_read_address`, `idx_read_date`

### `sent` — Sent Messages

Messages sent by the user. No AI fields — sent messages are never scanned.

| Column           | Type    | Constraint  | Description           |
| ---------------- | ------- | ----------- | --------------------- |
| `id`             | INTEGER | PRIMARY KEY | Auto-increment        |
| `address`        | TEXT    | NOT NULL    | Recipient address     |
| `contact_name`   | TEXT    | —           | Resolved contact name |
| `body`           | TEXT    | NOT NULL    | Message body          |
| `date`           | INTEGER | NOT NULL    | Timestamp             |
| `service_center` | TEXT    | —           | Service center        |
| `created_at`     | INTEGER | NOT NULL    | When inserted         |
| `updated_at`     | INTEGER | NOT NULL    | Last modification     |

**Indexes**: `idx_sent_address`, `idx_sent_date`

### `guardians` — Trusted Contacts

| Column       | Type    | Constraint       | Description            |
| ------------ | ------- | ---------------- | ---------------------- |
| `id`         | INTEGER | PRIMARY KEY      | Auto-increment         |
| `name`       | TEXT    | NOT NULL         | Guardian display name  |
| `phone`      | TEXT    | NOT NULL, UNIQUE | Phone number (unique)  |
| `created_at` | INTEGER | NOT NULL         | When added as guardian |

### Statistics Query

The `getStats()` method runs multiple aggregate queries to produce:

```dart
{
  'total': <sms table count>,
  'unread': <unread table count>,
  'read': <read table count>,
  'sent': <sent table count>,
  'unchecked': <unread + read WHERE threat_score IS NULL>,
  'safe': <unread + read WHERE threat_score < 0.30>,
  'uncertain': <unread + read WHERE threat_score >= 0.30 AND < 0.50>,
  'suspicious': <unread + read WHERE threat_score >= 0.50 AND < 0.70>,
  'scam': <unread + read WHERE threat_score >= 0.70>,
}
```

---

## Database Migrations

The database uses versioned migrations to evolve the schema:

### Version 1 → Version 2

**Change**: Added the `guardians` table.

```sql
CREATE TABLE guardians (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)
```

### Version 2 → Version 3

**Change**: Added the `decision` column to the `unread` table.

```sql
ALTER TABLE unread ADD COLUMN decision TEXT
```

This column enables tracking user actions on notifications (safe / dismissed / reported).

---

## Performance Optimizations

### Batch Database Inserts

When fetching all SMS from the device, messages are inserted using `db.batch()`:

```dart
final batch = db.batch();
for (final sms in smsList) {
  batch.insert('sms', sms.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
}
await batch.commit(noResult: true);
```

This is significantly faster than individual inserts, especially for devices with thousands of SMS messages.

### Debounced UI Refresh

The home page uses a throttled refresh mechanism to avoid excessive database queries during rapid processing:

```dart
void _debouncedRefreshData() {
  const cooldown = Duration(seconds: 2);

  // If enough time has passed, fire immediately
  if (_lastRefreshTime == null || now.difference(_lastRefreshTime!) >= cooldown) {
    _lastRefreshTime = now;
    _refreshData();
    return;
  }

  // Otherwise, schedule one trailing refresh
  if (!_refreshScheduled) {
    _refreshScheduled = true;
    _refreshDebounceTimer = Timer(remaining, () {
      _refreshScheduled = false;
      _lastRefreshTime = DateTime.now();
      _refreshData();
    });
  }
}
```

This ensures:

- The first callback triggers an immediate refresh
- Subsequent callbacks within 2 seconds are batched
- A trailing refresh fires at the end of the cooldown

### In-Memory Contact Lookup

Instead of querying contacts on every SMS, the `ContactsService` loads all contacts into a `Map<String, String>` on startup. Lookups are O(1) hash-map checks with O(n) variant generation per query (n ≈ 5-7 variants).

### LIFO Processing with Rate Limiting

The LIFO stack ensures recently arrived messages are processed first (most relevant to the user), while rate limiting prevents CPU saturation:

- 50ms between incoming messages (near real-time)
- 150ms between unread messages (moderate pace)
- 400ms between read messages (background scanning)

### Tensor Cleanup

After each ONNX inference, both input and output tensors are explicitly disposed:

```dart
await inputIdsTensor.dispose();
await attentionMaskTensor.dispose();
for (final tensor in results.values) {
  await tensor.dispose();
}
```

This prevents memory leaks during long scanning sessions.

---

## Privacy & Security

### On-Device Processing

- All AI inference runs locally using ONNX Runtime
- No SMS data is sent to any server or cloud service
- No analytics, telemetry, or crash reporting
- No internet permission is requested or required

### Data Storage

- All data stored in a local SQLite database on the device
- Database file: `silverguard.db` in the app's private data directory
- Only accessible by SilverGuard (Android's sandboxed storage)
- Cleared when the app is uninstalled

### SMS Permissions

- `READ_SMS`: Read-only access to device SMS inbox
- `RECEIVE_SMS`: Passive listener; does not modify or delete any SMS
- `SEND_SMS`: Only used to send guardian alerts; never sends unsolicited messages
- SMS content is only stored locally and never transmitted

### Contact Access

- `READ_CONTACTS`: Read-only access, no modifications
- Contact data is cached in memory only (not persisted to disk)
- Only phone numbers and display names are loaded (no photos, emails, etc.)

### Guardian Alerts

- SMS alerts are sent silently using the system's `Telephony` API
- Alert content is limited to a 100-character preview of the scam message
- No personal information about the user is included in alerts

---

## Build Configuration

### Android App Build (`android/app/build.gradle.kts`)

```kotlin
android {
    namespace = "com.example.silverguard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.silverguard"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**Key Points**:

- **Java 17** required for modern Android Gradle plugins
- **Core Library Desugaring** enabled for using Java 8+ APIs on older Android versions
- **Application ID**: `com.example.silverguard` (change this for production releases)
- Lint errors set to non-fatal (`abortOnError = false`)

### Asset Declaration (`pubspec.yaml`)

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/ml/
```

All files in `assets/ml/` are bundled into the APK. This includes the ONNX model, vocabulary, and config.

---

## Known Limitations

| Limitation               | Description                                                                     |
| ------------------------ | ------------------------------------------------------------------------------- |
| **Android Only**         | iOS does not allow third-party apps to read or intercept SMS                    |
| **Physical Device**      | SMS APIs require a real device; emulators cannot receive real SMS               |
| **Model Size**           | ONNX model is ~100MB+, significantly increases APK size                         |
| **No Cloud Sync**        | All data stays on the device; no backup or sync mechanism                       |
| **Single Device**        | No cross-device data sharing or migration                                       |
| **Background Limits**    | Android may kill background SMS listener on battery-optimized devices           |
| **No OTA Model Updates** | Model cannot be updated without rebuilding and reinstalling the app             |
| **English Bias**         | MobileBERT is trained on English SMS; accuracy may be lower for other languages |
| **Large Inbox Latency**  | Devices with 10,000+ SMS may experience slow initial import                     |
| **No Whitelisting**      | Cannot manually mark senders as safe to skip AI scanning                        |
| **Application ID**       | Uses `com.example.silverguard` — must be changed for Play Store publishing      |

---

## Troubleshooting

### "AI Model failed to load"

- **Cause**: The ONNX model or vocabulary file is missing from `assets/ml/`
- **Fix**:
  1. Download all files from [Hugging Face](https://huggingface.co/tanishqmudaliar/SilverGuard)
  2. Place them in `assets/ml/`
  3. Run `flutter clean && flutter pub get`
  4. Rebuild the app

### "Permissions denied"

- **Cause**: One or more required permissions were not granted
- **Fix**:
  1. Go to Android Settings → Apps → SilverGuard → Permissions
  2. Enable SMS, Phone, Contacts, and Notifications
  3. Restart the app

### "SMS not being detected in background"

- **Cause**: Android battery optimization is killing the background listener
- **Fix**:
  1. Go to Android Settings → Battery → SilverGuard
  2. Set battery optimization to "Unrestricted" or "Don't optimize"
  3. Ensure the app is not force-stopped
  4. On some manufacturers (Xiaomi, Huawei, Samsung), add SilverGuard to the "Auto-start" whitelist

### "No notifications appearing"

- **Cause**: Notification permission not granted or channel muted
- **Fix**:
  1. On Android 13+, ensure `POST_NOTIFICATIONS` permission is granted
  2. Go to Android Settings → Apps → SilverGuard → Notifications
  3. Ensure the "Scam Alerts" channel is enabled and not set to silent
  4. Check that Do Not Disturb mode is not blocking alerts

### "Guardian alert not sent"

- **Cause**: No guardians configured, SEND_SMS permission denied, or invalid phone number
- **Fix**:
  1. Open Settings in the app and verify at least one guardian is added
  2. Ensure SEND_SMS permission is granted
  3. Check that the guardian phone number is valid and reachable
  4. On dual-SIM devices, ensure the active SIM can send SMS

### "Fetch All SMS takes too long"

- **Cause**: Device has a very large SMS inbox (10,000+ messages)
- **Fix**:
  1. Wait for the import to complete (progress is shown)
  2. Subsequent fetches only insert new messages (duplicates are ignored)
  3. Consider clearing old SMS from the device's native SMS app

### "App crashes on startup"

- **Possible Causes**: Corrupted database, missing assets, or permission issues
- **Fix**:
  1. Clear app data: Android Settings → Apps → SilverGuard → Storage → Clear Data
  2. Reinstall the app
  3. Ensure all assets are present in `assets/ml/`
  4. Check `flutter doctor` for SDK issues

### "Contact names not showing"

- **Cause**: `READ_CONTACTS` permission denied or contacts not loaded
- **Fix**:
  1. Grant contacts permission
  2. Restart the app (contacts are loaded on initialization)
  3. Tap "Fetch All SMS" to reimport with contact names

---

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

### Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Dart style guide and `flutter_lints` rules
- Run `flutter analyze` before submitting PRs
- Test on a physical device (SMS APIs don't work on emulators)
- Do not commit the ONNX model file to the repository
- Keep services as singletons with the `ServiceName.instance` pattern

### Areas for Contribution

- Multi-language SMS support (Hindi, Spanish, etc.)
- Sender whitelisting / blacklisting
- SMS history export (CSV/JSON)
- Statistics dashboard with charts
- Automated testing suite
- App icon and splash screen design
- Play Store listing preparation

---

## License

This project is open source and available under the [MIT License](LICENSE).

---

Made with ❤️ by Tanishq Mudaliar

**Protecting seniors from SMS scams — one message at a time. 🛡️**
