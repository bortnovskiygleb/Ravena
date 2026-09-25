# Building Ravena in Xcode

## 1. Create the Project

Xcode → File → New → Project → **App**
- Interface: **Storyboard**
- Language: **Swift**

The "Life Cycle" option was removed in Xcode 13. Selecting **Storyboard** gives you `AppDelegate.swift`, `SceneDelegate.swift`, and `Main.storyboard`. We will replace/delete them, but this sets up the correct target structure without manually configuring `Info.plist`.

## 2. Remove the Storyboard

1. Delete `Main.storyboard` from the project (Move to Trash).
2. Target → **Build Settings** → search for `storyboard` → find **"UIKit Main Storyboard File Base Name"** (`UIMainStoryboardFile`) → clear the value.
3. Target → **Info** → expand **Application Scene Manifest** → **Scene Configuration** → **Application Session Role** → **Item 0** → delete the **Storyboard Name** key.

## 3. Deployment Target

Target → General → Minimum Deployments → **iOS 17.0**

Reason: `SwiftData` (`@Model`, `@Query`, `ModelContainer`) requires iOS 17+. The project will not build otherwise.

## 4. Add Dependencies (Swift Package Manager)

File → Add Package Dependencies:
```text
https://github.com/weichsel/ZIPFoundation.git
https://github.com/scinfu/SwiftSoup.git
```

## 5. Add Files to Project

Drag and drop all `.swift` files into Xcode (except `backend/` — this is a separate Cloudflare Workers project, see its README).

Suggested grouping for navigation:
```text
EPUB/          EPUBModels, EPUBParser, WordTokenizer
Reader/        ReaderViewController, ReaderPageViewController, ChapterPaginator, ChapterRenderer, ReaderLayoutMetrics, SentenceExtractor, ReadingProgressBar, ReadingProgressStore, TableOfContentsView, ReaderCoordinator
Translation/   TranslationService, APITranslationService, CachingTranslationService, LRUCache, TranslationPopupViewController
Dictionary/    SavedWord, DictionaryStore, DictionaryListView, DictionaryScreenFactory
Library/       LibraryBook, BookImporter, EPUBFilePicker, LibraryListView, LibraryScreenFactory, LibraryFileReconciler
Settings/      ReaderSettings, ReaderSettingsStore, SettingsView, SettingsScreenFactory
Root:          AppDelegate, SceneDelegate, AppDependencies, RootTabBarController, Assets.xcassets (contains app icon)
```

## 6. Replace Templates

When adding `AppDelegate.swift`, `SceneDelegate.swift`, and `Assets.xcassets`, select **Replace** to overwrite Xcode's empty templates. Our `Assets.xcassets` already contains a formatted App Icon (1024×1024).

## 7. Configure Backend URL

In `AppDependencies.swift`, replace:
```swift
let backendURL = URL(string: "https://reader-translate-proxy.example.workers.dev")!
```
with your deployed URL (see `backend/README.md`).

## 8. Info.plist Permissions

Importing files via `UIDocumentPickerViewController` does not require special `Info.plist` permissions since it uses security-scoped bookmarks rather than system-wide permission prompts.

## 9. Run

Cmd+R. The first screen will be an empty library with a "+" button to import a `.epub`.

## 10. Running on a Real Device (iPhone/iPad)

A standard free Apple ID is sufficient to run your app on your device via Xcode. The Apple Developer Program ($99/year) is only required for App Store publishing or avoiding the 7-day expiration.

### 10.1. Configure Signing

1. Target → **Signing & Capabilities**
2. Enable **Automatically manage signing**
3. Under **Team**, select your Apple ID (add it via Xcode **Settings → Accounts** if missing).
4. **Bundle Identifier** — change to something unique (e.g., `com.yourname.readerapp`).

### 10.2. Connect Device

Connect your device via cable. Confirm **"Trust This Computer?"** and enter your passcode.

### 10.3. Developer Mode (iOS 16+)

1. If **Developer Mode** is missing in **Settings → Privacy & Security**, open Xcode **Window → Devices and Simulators** while connected to prompt its appearance.
2. On device: **Settings → Privacy & Security → Developer Mode** → enable.
3. Reboot and confirm **Turn On**.

### 10.4. Build and Run

Select your physical device in Xcode and press Cmd+R.
If you see **"Untrusted Developer"**, go to **Settings → General → VPN & Device Management**, select your profile, and tap **Trust**.

### 10.5. Free Signing Limitation

Apps signed with a free Apple ID expire after **7 days**. Rebuild (Cmd+R) via Xcode to refresh the expiration.
