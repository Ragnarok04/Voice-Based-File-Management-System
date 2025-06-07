##System Architecture

> Developed by [Ragnarok04](https://github.com/Ragnarok04), [KingCrimson711](https://github.com/KingCrimson711), and Pranjal Agrawal.

The Voice-Based File Management System follows a modular client-server architecture. It integrates audio capture, transcription, natural language processing, and secure command execution to support hands-free file and Git operations.

### 1. Flutter Frontend (Client)

- **Technology:** Flutter (Dart)
- **Responsibilities:**
  - Captures audio via microphone using `flutter_sound` or `audio_recorder`.
  - Sends audio (WAV/PCM) to the backend via HTTP POST.
  - Displays:
    - Transcription from Whisper
    - Generated shell/Git command from Ollama
    - Execution status (success or error)
  - Manual recording toggle for user privacy and control.

### 2. Flask Backend (Server)

- **Technology:** Python with Flask
- **Responsibilities:**
  - REST API Endpoints:
    - `/transcribe`: Converts audio to text using Whisper.
    - `/generate`: Translates text to CLI command using LLM.
    - `/execute`: Validates and executes the command securely.
  - Modular pipeline coordination.
  - Scalable with Gunicorn and WSGI workers.

### 3. Speech-to-Text (STT) Layer

- **Technology:** OpenAI Whisper (local or API via `whisper.cpp`)
- **Responsibilities:**
  - Converts user speech into clean, punctuated text.
  - Low-latency transcription optimized for macOS/Linux.

### 4. Command Generation (LLM Layer)

- **Technology:** Ollama-hosted LLM
- **Responsibilities:**
  - Converts user intent (in plain English) into valid shell or Git commands.
  - Supports natural phrasing, e.g., “move report.txt to archive”.

### 5. Local Execution Layer

- **Technology:** Python `os`, `shutil`, and `subprocess`
- **Responsibilities:**
  - Executes filesystem and Git operations:
    - Create, delete, rename, move files/folders
    - Git add, commit, push
  - Handles SSH authentication for secure Git pushes.
  - Logs all commands for auditing/debugging.

---

## 📊 System Flow (End-to-End)

The following diagram summarizes the complete flow of control and data through the system:

```mermaid
flowchart TD
    A[User Voice Input] --> B[Flutter App: Audio Capture]
    B --> C[Flask Backend: /transcribe]
    C --> D[Whisper STT: Audio to Text]
    D --> E[Flask Backend: /generate]
    E --> F[Ollama LLM: Text to Command]
    F --> G[Flask Backend: /execute]
    G --> H[Local Executor: File/Git Operation]
    H --> I[Result Sent to Flutter UI]

