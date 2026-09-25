# Сборка проекта в Xcode

## 1. Создать проект

Xcode → File → New → Project → **App**
- Interface: **Storyboard**
- Language: **Swift**

Отдельного пункта "Life Cycle" в текущих версиях Xcode нет (его убрали ещё в
Xcode 13) — просто выбор **Storyboard** в Interface уже сам по себе даёт вам
`AppDelegate.swift`, `SceneDelegate.swift` и `Main.storyboard`. Их нужно будет
заменить/удалить, но так вы сразу получаете правильную структуру таргета, без
ручной настройки Info.plist с нуля.

## 2. Убрать Storyboard

1. Удалить `Main.storyboard` из проекта (Move to Trash)
2. Target → **Build Settings** → в поиске набрать `storyboard` → найти ключ
   **"UIKit Main Storyboard File Base Name"** (`UIMainStoryboardFile`) →
   очистить значение.
   (В General эта настройка раньше называлась "Main Interface", но её убрали
   оттуда ещё в Xcode 14 — если у вас Xcode её там нет, это нормально, ищите
   через Build Settings, как выше.)
3. Если после этого останется ссылка на storyboard в Info-манифесте: Target →
   **Info** → раскрыть **Application Scene Manifest** → **Scene Configuration**
   → **Application Session Role** → **Item 0** → удалить ключ **Storyboard Name**.

Если что-то из этого в вашей версии Xcode называется или расположено иначе —
скажите точно, на каком шаге и что видите вместо описанного, поправлю сразу.

## 3. Deployment target

Target → General → Minimum Deployments → **iOS 17.0**

Причина: `SwiftData` (`@Model`, `@Query`, `ModelContainer`) требует iOS 17+.
Без этого проект просто не соберётся.

## 4. Добавить зависимости (Swift Package Manager)

File → Add Package Dependencies:
```
https://github.com/weichsel/ZIPFoundation.git
https://github.com/scinfu/SwiftSoup.git
```

## 5. Добавить все файлы в проект

Перетащить в Xcode все `.swift`-файлы, которые мы написали (кроме `backend/` —
это отдельный Cloudflare Workers проект, деплоится независимо, см. его README).

Порядок значения не имеет, но для навигации по проекту имеет смысл разложить по группам:

```
EPUB/          EPUBModels, EPUBParser, WordTokenizer
Reader/        ReaderViewController, ReaderPageViewController, ChapterPaginator,
               ChapterRenderer, ReaderLayoutMetrics, SentenceExtractor,
               ReadingProgressBar, ReadingProgressStore, TableOfContentsView,
               ReaderCoordinator
Translation/   TranslationService, APITranslationService,
               CachingTranslationService, LRUCache, TranslationPopupViewController
Dictionary/    SavedWord, DictionaryStore, DictionaryListView,
               DictionaryScreenFactory
Library/       LibraryBook, BookImporter, EPUBFilePicker, LibraryListView,
               LibraryScreenFactory, LibraryFileReconciler
Settings/      ReaderSettings, ReaderSettingsStore, SettingsView,
               SettingsScreenFactory
App/           AppDelegate, SceneDelegate, AppDependencies, RootTabBarController,
               Assets.xcassets (содержит готовую иконку приложения)
```

## 6. Заменить заготовки

Xcode уже создал свои `AppDelegate.swift`, `SceneDelegate.swift` и
`Assets.xcassets` (с пустой заготовкой AppIcon) — при добавлении наших файлов
на конфликте имён выбрать **Replace** (наши версии, а не пустые заготовки
Xcode). Для `Assets.xcassets` это тоже верно: наш `App/Assets.xcassets` уже
содержит готовую иконку (1024×1024, без альфа-канала) в правильной структуре
`AppIcon.appiconset` — просто замените весь файл целиком, вручную вставлять
картинку в слоты не нужно.

## 7. Настроить URL бэкенда

В `AppDependencies.swift` заменить:
```swift
let backendURL = URL(string: "https://reader-translate-proxy.example.workers.dev")!
```
на реальный URL после деплоя (см. `backend/README.md`).

## 8. Разрешения в Info.plist

Импорт файлов через `UIDocumentPickerViewController` не требует специальных
разрешений в Info.plist — в отличие от доступа к фото/микрофону, работа с
Files app использует security-scoped bookmarks, а не системные permission-запросы.

## 9. Запуск

Cmd+R. Первый экран — пустая библиотека с кнопкой "+" для импорта `.epub`.

## 10. Запуск на реальном устройстве (iPhone/iPad)

Ничего платного для этого не нужно — обычного Apple ID достаточно, чтобы
запускать свои приложения на своих устройствах через Xcode. Платный Apple
Developer Program ($99/год) нужен только для публикации в App Store или если
хотите, чтобы собранное приложение не "протухало" через 7 дней (см. ниже).

### 10.1. Настроить подпись

1. Target → **Signing & Capabilities**
2. Включить **Automatically manage signing**
3. В поле **Team** выбрать свой Apple ID. Если его нет в списке — Xcode →
   **Settings** (или **Preferences**) → **Accounts** → **+** → войти с Apple ID
4. **Bundle Identifier** — поменять на что-то уникальное, например
   `com.вашеимя.readerapp` (значение по умолчанию вида `com.example.ReaderApp`
   может конфликтовать с чужими сборками на серверах Apple)

### 10.2. Подключить устройство

1. Подключить iPhone/iPad к Mac кабелем (для первого раза — обязательно
   кабелем, дальше можно будет по Wi-Fi)
2. На устройстве появится запрос **"Trust This Computer?"** — подтвердить,
   ввести код-пароль устройства

### 10.3. Developer Mode

Начиная с iOS 16, на устройстве нужно отдельно включить Developer Mode —
без этого установленное через Xcode приложение просто откажется запускаться.

1. Если в **Settings → Privacy & Security** на устройстве пункта
   **Developer Mode** ещё нет — откройте в Xcode **Window → Devices and
   Simulators**, дождитесь, пока устройство определится (это и "приучит"
   систему показать нужный пункт в настройках)
2. На устройстве: **Settings → Privacy & Security → Developer Mode** → включить
3. Устройство попросит перезагрузиться — перезагрузить, после разблокировки
   подтвердить **Turn On** во всплывающем окне

### 10.4. Собрать и запустить

1. В Xcode рядом со схемой сборки (там, где обычно выбран симулятор) выбрать
   своё физическое устройство
2. Cmd+R — соберётся, установится и запустится на телефоне/планшете напрямую

Если при первом запуске система покажет **"Untrusted Developer"** и
приложение не откроется — на устройстве: **Settings → General → VPN & Device
Management** → выбрать свой профиль разработчика → **Trust**.

### 10.5. Ограничение бесплатной подписи

Приложение, подписанное через бесплатный Apple ID, работает **7 дней**, потом
iOS перестаёт его запускать — нужно просто ещё раз собрать (Cmd+R) через Xcode,
пока телефон рядом. Для постоянной установки без периодической пересборки —
нужен платный Apple Developer Program.



- Нет обработки ошибки "backend недоступен" красивее, чем алерт из
  `errorMessage(for:)` в `ReaderCoordinator`.
- Launch screen и локализация Info.plist (`CFBundleDisplayName` и т.п.) — не
  входили в объём этой сессии.

Полный и актуальный список технического долга и уже исправленных вещей — в
`REVIEW.md`.
