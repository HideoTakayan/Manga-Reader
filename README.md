# Manga & Novel Reader

A native Android comic and novel reader built with Flutter. Designed with an **offline-first** mindset and a **serverless** architecture, it uses Google Drive as the primary storage and Firebase for community features and syncing.

The goal was to build a reader that doesn't crash on huge files, doesn't eat up all your RAM, and works seamlessly even when the internet drops.

## Highlights & Engineering

This isn't just a basic UI wrapper. A lot of effort went into making the app stable under heavy loads:

### 1. Zero OOM (Out of Memory) Architecture
Most reader apps crash when trying to extract a 200MB `.cbz` or `.zip` file because they load the binary data straight into RAM. 
- **Direct-to-Disk Extraction**: We use Dart `Isolate`s to unpack archives in the background and write chunks directly to local storage. 
- **Strict Image Caching**: Flutter's `PaintingBinding.instance.imageCache` is hard-capped at ~80MB. No matter how fast you scroll through a 100-page webtoon, memory usage stays flat.

### 2. Bulletproof Authentication Flow
Dealing with Firebase Auth and navigation can be tricky, especially with initialization race conditions that leave users stuck on a splash or login screen.
- **Synchronous GoRouter Redirects**: We completely stripped out `StreamBuilder` widget wrappers. Authentication routing is handled directly inside `GoRouter` using `refreshListenable` and `redirect`. It checks the Firebase token synchronously before drawing a single frame.

### 3. Fault-Tolerant Binary Parsing
Corrupted `.zip` or `.epub` files shouldn't crash the entire app.
- **Null-Safe Decoders**: Our custom `ArchiveImageExtractor` and EPUB parser are strictly type-checked. If a binary blob has missing bytes, the app swallows the `TypeError`, skips the broken page, and continues rendering the rest of the book without throwing a white screen.

### 4. True Offline-First & Background Sync
- **SQLite First**: Reading progress, downloaded chapters, and library organization are saved instantly to a local SQLite database.
- **Decoupled Syncing**: When the user's connection or auth state restores, a background `SyncService` quietly batches the pending local changes and pushes them to Firestore. We even keep local files (like sideloaded EPUBs) strictly local so they don't pollute the cloud database.

### 5. Smart UX & Navigation
- **Pixel-Perfect Scroll Tracking**: Instead of using flawed scroll percentages (`pixels / maxExtent`) which break on webtoons with varying image heights, we use `GlobalKey` and `RenderBox.localToGlobal`. By tracking only the 3-5 mounted widgets on screen, the progress slider is always 100% accurate at 120 FPS.
- **Hold-to-Load**: Gestures replace buttons. Scroll to the bottom of a chapter, hold for 1.5 seconds, and it automatically transitions to the next one.
- **Debounced Operations**: Global search and heavy queries use a 500ms debounce to prevent UI stuttering and save Firestore read costs.

## Features

- **Multi-Format**: `.cbz`, `.zip`, `.pdf`, and `.epub` (with Text-to-Speech support).
- **Background Downloads**: Queue system safely downloads large files even when the app is minimized (using `flutter_background_service` and `wakelock_plus`).
- **Community Forum**: Real-time discussions and post threads. Optimized using a single parent Firebase Stream to dramatically reduce document reads.
- **Admin Panel**: Built-in dashboard to manage manga metadata, user reports, and banners. Admins are whitelisted via email.

## Tech Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod 2.x
- **Routing**: GoRouter 14.x
- **Backend / BaaS**: Firebase (Auth, Firestore) + Google Drive API v3
- **Local DB**: SQLite (`sqflite`)

## Download & Install

> 📥 **Download the latest Android APK:**
> [**CLICK HERE TO DOWNLOAD FROM GOOGLE DRIVE**](https://drive.google.com/file/d/1zEuL_1zcbUC4g73L8ICsOHQolpZZH6s4/view?usp=sharing)

*(Note: The source code is provided for portfolio and educational purposes. Local build instructions are omitted because sensitive configuration files like `google-services.json`, keystores, and Google Drive API credentials have been excluded from version control for security reasons.)*

## Roadmap

- [ ] CBR (Comic Book RAR) support
- [ ] iOS/Cross-platform adaptation
- [ ] Collaborative reading / Co-reading mode
