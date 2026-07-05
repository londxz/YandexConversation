# AGENTS.md

## Product Direction

This is a production accessibility application for people with hearing and speech impairments. Treat it as a long-lived product, not a hackathon prototype.

The product must help a user communicate in everyday and high-stress situations:

- read other people's speech as text;
- type a response and show it in large readable form;
- speak typed text with text-to-speech;
- use quick saved phrases;
- keep conversation history when the user explicitly wants that;
- work usefully without a network connection.

The design priority is trust, clarity, speed, and accessibility. Avoid decorative UI that slows repeated use. Every interaction should make sense for users who may be stressed, in a noisy place, at a doctor's appointment, in transport, or talking to a stranger.

## Production Principles

- Offline-first: the iOS app must remain useful without the backend.
- Privacy-first: do not store raw audio by default. Do not log raw speech text or audio in production.
- Accessibility-first: Dynamic Type, large tap targets, contrast, VoiceOver labels, reduced motion, and predictable navigation are required.
- No demo-only shortcuts: no hardcoded `127.0.0.1`, no console-only success paths, no fake screens pretending to be implemented.
- Versioned contracts: backend APIs live under `/v1`, and breaking changes require a new version.
- Explicit state: recording, recognition, playback, sync, and error states must be visible in code and UI.
- Graceful failure: network/STT failure must not break typing, TTS, quick phrases, or local history.

## iOS Architecture

Use **UIKit + MVP + Coordinators + Use Cases + Repositories**.

Do not use MVVM for this project. Do not introduce TCA into the current UIKit codebase. TCA is a good fit for SwiftUI/reducer-driven apps, but here it would add architectural weight without matching the existing UIKit flow. If the product later migrates major surfaces to SwiftUI, reassess TCA then.

### Layering

Recommended project structure:

```text
HackatonYandex
├── App
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── AppContainer.swift
│   └── AppConfig.swift
├── Core
│   ├── DesignSystem
│   ├── Accessibility
│   ├── Logging
│   ├── ErrorHandling
│   └── Extensions
├── Navigation
│   ├── AppCoordinator.swift
│   ├── OnboardingCoordinator.swift
│   ├── ConversationCoordinator.swift
│   ├── PhrasesCoordinator.swift
│   ├── HistoryCoordinator.swift
│   └── SettingsCoordinator.swift
├── Domain
│   ├── Entities
│   ├── UseCases
│   └── RepositoryProtocols
├── Data
│   ├── LocalStorage
│   ├── Network
│   ├── Speech
│   ├── Audio
│   └── Repositories
├── Presentation
│   ├── Onboarding
│   ├── Conversation
│   ├── Phrases
│   ├── History
│   └── Settings
└── Resources
```

### MVP Module Shape

Each user-facing screen should follow this shape:

```text
FeatureViewController: FeatureView
FeaturePresenter
FeatureInteractor or UseCases
FeatureRouter/Coordinator
Repositories
```

View controllers:

- own UIKit views and layout;
- forward user events to the presenter;
- render view models from the presenter;
- do not contain business logic, persistence, networking, speech recognition, or audio recording decisions.

Presenters:

- transform domain state into screen state;
- coordinate use cases;
- decide what the view should show next;
- expose deterministic inputs such as `viewDidLoad`, `didTapSend`, `didSwitchMode`, `didTapRetry`, `didTapPlay`.

Use cases:

- hold business rules;
- operate on domain entities;
- depend on repository protocols, not concrete storage/network implementations.

Repositories:

- hide local/remote data details;
- resolve offline-first behavior;
- implement sync conflict rules.

### Core iOS Domain Entities

Use stable IDs. Prefer UUID strings generated client-side so local data can sync later.

```text
Conversation
- id
- title
- mode: talk | listen
- createdAt
- updatedAt
- isPinned
- syncState

ConversationMessage
- id
- conversationId
- text
- source: userTyped | userVoice | externalSpeech | quickPhrase | system
- speakerId
- speakerLabel
- isFinal
- createdAt
- audioDurationMs
- syncState

Speaker
- id
- conversationId
- label
- colorToken

Phrase
- id
- folderId
- text
- category
- isFavorite
- sortOrder
- usageCount
- createdAt
- updatedAt
- syncState

PhraseFolder
- id
- title
- sortOrder

AppSettings
- recognitionLanguage
- ttsLanguage
- ttsVoiceIdentifier
- speechRate
- transcriptFontScale
- autoStartMicrophone
- saveConversationsByDefault
- syncEnabled
- privacyMode
```

### Local Storage

Production iOS storage should use SQLite through a thin repository layer. Core Data is acceptable only if the team commits to it consistently, but SQLite is simpler to reason about with explicit migrations and sync metadata.

Store locally:

- conversations;
- messages;
- phrases and folders;
- settings;
- sync queue;
- lightweight recognition metadata.

Do not store raw audio unless the user explicitly enables it for diagnostics or export.

### iOS Networking

Use one `APIClient` with:

- environment-based base URL;
- request timeout policy;
- retry policy only for idempotent requests;
- auth/session injection;
- typed API errors;
- request IDs;
- no raw text/audio logs in production.

Local debug can use a configurable LAN backend URL. Never hardcode localhost as the only endpoint.

### iOS Audio and Speech

Separate audio capture from UI:

```text
AudioRecorderService
SpeechRecognitionService
TextToSpeechService
RealtimeSpeechClient
```

The app should support:

- typed response without network;
- TTS through `AVSpeechSynthesizer`;
- batch upload for recorded audio;
- realtime streaming over WebSocket when backend recognition is enabled;
- clear permission flow for microphone and speech features.

## Screens and Capabilities

### 1. Splash / Launch

Production launch screen matching the Yandex-style visual direction. Keep it static and fast.

### 2. Onboarding

Required screens:

- "Разговаривайте с помощью текста";
- "Читайте речь вокруг вас";
- "Быстрые фразы под рукой";
- microphone/privacy permission explanation before first recording.

Must be shown once, then controlled by persisted onboarding state.

### 3. Conversation Root

Main tab: "Разговор и слушание".

Contains:

- top actions: history, microphone status, new conversation;
- segmented mode control: "Разговаривать" and "Слушать";
- current conversation area;
- bottom input only when mode supports typing;
- quick phrase drawer entry.

### 4. Talk Mode

Required:

- auto-start microphone if enabled and permission exists;
- show microphone status;
- display recognized external speech as incoming messages;
- type outgoing text;
- send outgoing text to conversation;
- show outgoing text in large display mode;
- TTS playback for outgoing text;
- rotate/flip display for the person across the table;
- save messages to local history;
- continue to work if recognition backend is unavailable.

### 5. Listen Mode

Required:

- no outgoing text field by default;
- large continuous transcript;
- speaker labels: "Говорящий 1", "Говорящий 2";
- partial and final recognition states;
- pause/resume listening;
- save transcript as conversation;
- readable layout for lecture, doctor visit, meeting, or presentation.

### 6. Large Text Display

Required:

- full-screen text;
- TTS playback;
- rotate/flip action;
- dismiss action;
- font scaling and safe layout for long phrases;
- no overlapping controls.

### 7. Quick Phrases

Required:

- list phrases;
- add/edit/delete phrase;
- favorite/unfavorite;
- folders/categories;
- search;
- show phrase full-screen;
- speak phrase;
- share/copy phrase;
- use phrase inside current conversation.

### 8. History

Required:

- list conversations;
- open conversation;
- search;
- pin/unpin;
- rename;
- delete;
- export/share transcript;
- optional foldering later.

### 9. Settings

Required:

- recognition language;
- TTS voice and speed;
- text size;
- auto-start microphone;
- save conversations by default;
- sync on/off;
- privacy mode;
- backend environment in debug builds only;
- legal/privacy information.

## Backend Architecture: Go Production Service

Use Go for the backend API and realtime gateway.

Recommended structure:

```text
backend
├── cmd/api/main.go
├── internal/config
├── internal/domain
├── internal/usecase
├── internal/transport/http
│   ├── handlers
│   ├── middleware
│   └── dto
├── internal/transport/ws
├── internal/repository/postgres
├── internal/repository/redis
├── internal/speech
│   ├── provider.go
│   ├── yandex
│   └── whisper
├── internal/sync
├── internal/auth
├── internal/observability
├── migrations
├── openapi
└── deploy
```

### Backend Components

- HTTP API: REST JSON over HTTPS.
- Realtime API: WebSocket over TLS.
- Database: PostgreSQL for server-side data.
- Cache/session state: Redis only where needed for realtime/session coordination.
- Object storage: optional encrypted audio storage only if the product explicitly supports saving audio.
- Speech provider abstraction: Go service calls provider adapters. Do not bind the domain to one STT implementation.
- Observability: structured logs, metrics, tracing, request IDs.

### TCP Decision

Do not implement custom raw TCP for the mobile app.

Use:

- HTTPS REST for CRUD and sync;
- WebSocket over TLS for realtime speech events;
- optional gRPC streaming later if WebSocket becomes limiting.

Raw TCP adds avoidable production risk on iOS: TLS handling, proxies, NAT traversal, reconnect semantics, background behavior, monitoring, and custom framing. WebSocket gives bidirectional streaming while staying mobile- and infrastructure-friendly.

## API Conventions

- Base path: `/v1`.
- JSON fields: `snake_case`.
- IDs: UUID strings.
- Time: RFC 3339 UTC.
- Pagination: cursor-based for lists.
- Idempotent writes: support `Idempotency-Key`.
- Every response includes or propagates `X-Request-ID`.
- Errors use stable machine-readable codes.

### Error Shape

```json
{
  "error": {
    "code": "speech_unavailable",
    "message": "Speech recognition is temporarily unavailable.",
    "request_id": "req_123"
  }
}
```

## Go Contracts

### Health

```http
GET /v1/health
```

Response:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "time": "2026-07-05T11:00:00Z"
}
```

### Device Session

Production can start without full accounts, but each installation needs an anonymous device session for sync and abuse control.

```http
POST /v1/devices/register
```

Request:

```json
{
  "platform": "ios",
  "app_version": "1.0.0",
  "locale": "ru-RU"
}
```

Response:

```json
{
  "device_id": "uuid",
  "access_token": "token",
  "refresh_token": "token"
}
```

### Conversations

```http
GET /v1/conversations?cursor=&limit=50
POST /v1/conversations
GET /v1/conversations/{conversation_id}
PATCH /v1/conversations/{conversation_id}
DELETE /v1/conversations/{conversation_id}
```

Create request:

```json
{
  "id": "uuid",
  "mode": "talk",
  "title": "Прием у врача",
  "created_at": "2026-07-05T11:00:00Z"
}
```

### Messages

```http
GET /v1/conversations/{conversation_id}/messages?cursor=&limit=100
POST /v1/conversations/{conversation_id}/messages
PATCH /v1/conversations/{conversation_id}/messages/{message_id}
DELETE /v1/conversations/{conversation_id}/messages/{message_id}
```

Create request:

```json
{
  "id": "uuid",
  "text": "Я не слышу. Повторите, пожалуйста.",
  "source": "quick_phrase",
  "speaker_id": "uuid",
  "speaker_label": "Я",
  "is_final": true,
  "created_at": "2026-07-05T11:01:00Z"
}
```

### Phrases

```http
GET /v1/phrase-folders
POST /v1/phrase-folders
PATCH /v1/phrase-folders/{folder_id}
DELETE /v1/phrase-folders/{folder_id}

GET /v1/phrases?folder_id=&query=&favorite_only=false&cursor=&limit=50
POST /v1/phrases
GET /v1/phrases/{phrase_id}
PATCH /v1/phrases/{phrase_id}
DELETE /v1/phrases/{phrase_id}
POST /v1/phrases/{phrase_id}/use
```

Phrase shape:

```json
{
  "id": "uuid",
  "folder_id": "uuid",
  "text": "Я не слышу. Повторите, пожалуйста.",
  "is_favorite": true,
  "sort_order": 10,
  "usage_count": 12,
  "created_at": "2026-07-05T11:00:00Z",
  "updated_at": "2026-07-05T11:00:00Z"
}
```

### Batch Speech Recognition

```http
POST /v1/speech/transcribe
Content-Type: multipart/form-data
```

Form fields:

```text
file: audio file
language: ru-RU
conversation_id: optional uuid
```

Response:

```json
{
  "text": "Здравствуйте, чем я могу помочь?",
  "language": "ru-RU",
  "duration_ms": 2300,
  "confidence": 0.91
}
```

### Realtime Speech Recognition

```http
WS /v1/speech/stream
```

Client start:

```json
{
  "type": "start",
  "conversation_id": "uuid",
  "mode": "talk",
  "language": "ru-RU",
  "audio": {
    "format": "pcm16",
    "sample_rate": 16000,
    "channels": 1
  }
}
```

Client audio chunk:

```json
{
  "type": "audio_chunk",
  "sequence": 1,
  "data": "base64_pcm_chunk"
}
```

Client stop:

```json
{
  "type": "stop"
}
```

Server partial:

```json
{
  "type": "partial",
  "sequence": 12,
  "text": "По идее если приложение",
  "speaker": {
    "id": "speaker_1",
    "label": "Говорящий 1"
  }
}
```

Server final:

```json
{
  "type": "final",
  "message_id": "uuid",
  "sequence": 13,
  "text": "По идее если приложение может различать голоса.",
  "speaker": {
    "id": "speaker_1",
    "label": "Говорящий 1"
  },
  "confidence": 0.89,
  "started_at": "2026-07-05T11:01:00Z",
  "ended_at": "2026-07-05T11:01:04Z"
}
```

Server error:

```json
{
  "type": "error",
  "code": "speech_unavailable",
  "message": "Speech recognition is temporarily unavailable.",
  "request_id": "req_123"
}
```

### Settings

```http
GET /v1/settings
PUT /v1/settings
```

### Sync

```http
POST /v1/sync/push
POST /v1/sync/pull
```

Use sync only when enabled by the user. Local data remains the app's first source of truth for immediate UX.

## Functional Requirements

### Conversation

- User can start a talk conversation.
- User can start a listen-only conversation.
- User can pause/resume microphone.
- User can type text and send it into the conversation.
- User can show typed text in large display mode.
- User can play typed text through TTS.
- User can flip display orientation for the other person.
- User can save, rename, delete, and reopen conversations.

### Speech Recognition

- App can transcribe speech in realtime when backend is available.
- App can upload an audio file for batch transcription.
- App handles partial and final recognition separately.
- App shows speaker labels in listen mode.
- App recovers from network loss without losing already-finalized text.

### Quick Phrases

- User can create, edit, delete, favorite, search, and organize phrases.
- User can speak a phrase.
- User can show a phrase in large text mode.
- User can insert a phrase into current conversation.

### History

- User can view all saved conversations.
- User can search by text and title.
- User can pin important conversations.
- User can export/share a transcript.
- User can delete local history.

### Settings and Privacy

- User can control microphone auto-start.
- User can control text size and TTS voice/speed.
- User can enable/disable sync.
- User can see whether speech is processed locally or through backend.
- User can delete local data.

## Non-Functional Requirements

### Performance

- Cold launch to usable main screen: target under 2 seconds on supported devices.
- Talk mode input latency: immediate local render under 100 ms.
- TTS start after tap: target under 300 ms.
- Realtime partial transcript latency: target 500-800 ms after speech chunk reaches backend.
- Final transcript latency: target under 2 seconds after phrase end.
- Conversation lists must remain smooth with thousands of messages through pagination or incremental loading.

### Reliability

- Local typing, TTS, phrases, and history must work offline.
- Realtime recognition must reconnect with backoff.
- Duplicate writes must be prevented with idempotency keys.
- Sync must be retryable and conflict-aware.
- App must survive force quit without corrupting local conversation state.

### Privacy and Security

- HTTPS/WSS only outside local debug.
- No raw audio persisted by default.
- No raw audio or transcript in production logs.
- Encrypt sensitive local data where appropriate.
- Store tokens in Keychain.
- Backend secrets only through environment/secret manager.
- Support user data deletion.

### Accessibility

- Dynamic Type support for all readable text.
- Minimum tap target: 44x44 pt.
- High contrast for core controls.
- VoiceOver labels for icon-only buttons.
- Reduced Motion support for nonessential animations.
- Large Text Display must avoid clipping and overlapping controls.

### Observability

- Backend: structured JSON logs, metrics, traces, health checks.
- iOS: non-sensitive diagnostics and crash reporting.
- Request IDs must connect client errors to backend logs.
- Monitor STT latency, error rate, reconnect count, and sync failures.

## Implementation Roadmap

### Phase 1: Production Foundation

- Replace prototype startup flow with `AppCoordinator`.
- Restore persisted onboarding state.
- Introduce `AppContainer` dependency injection.
- Add `AppConfig` with dev/staging/prod environments.
- Create domain entities and repository protocols.
- Move audio/networking out of views.
- Remove unused prototype screens and debug print-only success paths.

### Phase 2: Offline-First iOS

- Add SQLite local storage with migrations.
- Implement conversations, messages, phrases, settings repositories.
- Implement talk mode without backend dependency: typing, large display, TTS, local history.
- Implement quick phrases fully.
- Implement history fully.

### Phase 3: Go Backend Core

- Create Go service skeleton.
- Add config, logging, request IDs, health checks.
- Add PostgreSQL migrations.
- Implement device session.
- Implement conversations/messages/phrases/settings APIs.
- Generate or maintain OpenAPI documentation.

### Phase 4: Speech Integration

- Implement batch `/v1/speech/transcribe`.
- Implement WebSocket `/v1/speech/stream`.
- Add speech provider interface.
- Add reconnect and partial/final handling on iOS.
- Implement listen mode with speaker labels.

### Phase 5: Sync and Production Hardening

- Implement sync queue on iOS.
- Implement `/v1/sync/push` and `/v1/sync/pull`.
- Add conflict resolution.
- Add metrics, tracing, rate limits, and abuse protection.
- Add privacy controls and user data deletion.

### Phase 6: Accessibility and Release Quality

- Full accessibility pass.
- Dynamic Type and small-device layout QA.
- Error-state polish.
- Load testing backend speech and sync paths.
- App Store privacy text and production configuration review.

## Testing Requirements

iOS:

- Unit tests for presenters and use cases.
- Repository tests with temporary SQLite database.
- Contract tests for API DTO decoding.
- UI smoke tests for core flows.
- Manual accessibility QA with VoiceOver and Dynamic Type.

Go:

- Unit tests for use cases.
- Handler tests for every endpoint.
- Repository tests against test Postgres.
- WebSocket protocol tests.
- Migration tests.
- Load tests for realtime speech gateway.

## Current Codebase Notes

Known prototype areas to fix before building production features:

- `SceneDelegate` currently forces onboarding every launch.
- Talk and Listen screens are visually present but functionally empty.
- Recognized text is printed to console instead of entering the conversation model.
- Quick phrases and settings tabs are placeholders.
- Networking is hardcoded to `127.0.0.1:8000`.
- Audio recording, networking, and UI are mixed inside `ChatComponent`.
- Some files are unused prototype remnants and should be removed or integrated deliberately.

Do not build new production functionality on top of these prototype shortcuts. Stabilize architecture first.
