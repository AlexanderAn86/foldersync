# foldersync — двусторонняя синхронизация выбранных папок с Google Диском

Выбранные папки — **в любом месте** на компьютере — связаны с папками на личном Google Диске. Изменения с любой стороны (macOS, Windows или веб-версия Диска) расходятся автоматически каждые 15 минут. Весь остальной Диск на компьютер не скачивается.

Основа — бесплатная программа [rclone](https://rclone.org) (`rclone bisync`). foldersync добавляет к ней список пар папок, автозапуск, резервные копии и защиту от потерь.

## Что умеет

- Пары «локальная папка ⇄ папка на Google Диске» в одном файле `pairs.conf`; на разных компьютерах локальные пути могут отличаться
- Автозапуск каждые 15 минут и при входе в систему (macOS — launchd, Windows — Планировщик заданий)
- **Конфликт** (файл изменён с двух сторон): более новая версия остаётся под своим именем, другая сохраняется рядом как `имя.conflict1.pdf`
- **Резервные копии** перезаписанного и удалённого: на компьютере — `~/.foldersync/backup/`, на Диске — `_foldersync_backup/`
- **Защита от массового удаления**: если удаляется больше половины файлов, синхронизация останавливается
- Служебные файлы (`.DS_Store`, `Thumbs.db`, временные файлы Office) не синхронизируются
- Журнал `~/.foldersync/logs/ГГГГ-ММ.log`; при ошибке — системное уведомление

## Структура репозитория

```
mac/                 foldersync.sh, install.sh, uninstall.sh, pairs.conf
windows/             foldersync.ps1, install.ps1, uninstall.ps1, pairs.conf
docs/oauth-pages/    index.html, privacy.html — страницы для экрана согласия Google (шаг 2)
```

---

## Шаг 1. Установить rclone (на каждом компьютере)

- **macOS:** `brew install rclone` (или скачать с rclone.org/downloads и положить `rclone` в `/usr/local/bin`)
- **Windows:** `winget install Rclone.Rclone`, затем открыть PowerShell заново

## Шаг 2. Свой ключ доступа к Google Диску (один раз)

Общий ключ rclone **перестаёт работать в 2026 году** ([rclone docs](https://rclone.org/drive/#making-your-own-client-id)), поэтому нужен свой. Бесплатно, ≈ 15 минут, делается **один раз** — тот же ключ вводится на всех компьютерах.

### 2.1. Проект и Drive API

1. [console.cloud.google.com](https://console.cloud.google.com) под личным Google-аккаунтом → выбор проекта → **New project** → имя `foldersync`
2. **APIs & Services** → **Enable APIs and services** → **Google Drive API** → **Enable**

### 2.2. Страницы для экрана согласия (GitHub Pages)

Для публикации приложения Google требует домашнюю страницу и политику конфиденциальности. Бесплатно — через GitHub Pages:

1. На GitHub создать **публичный** репозиторий с именем **`ЛОГИН.github.io`** (ровно так)
2. Загрузить в него `docs/oauth-pages/index.html` и `docs/oauth-pages/privacy.html` → **Commit changes**
3. Через 1–2 минуты проверить в браузере `https://логин.github.io/` и `https://логин.github.io/privacy.html` (адрес — строчными буквами)

### 2.3. Экран согласия (Google Auth Platform)

| Раздел | Что сделать |
| --- | --- |
| **Branding** | App name `foldersync`; support email; **Application home page** `https://логин.github.io/` (обязательно с `https://`); **Privacy policy** `https://логин.github.io/privacy.html`; Terms of service — можно пусто; **Authorized domains → Add domain** `логин.github.io` (без `https://`); developer contact email → **Save** |
| **Audience** | User type **External** (сообщение «you can only make your app available to external users» — нормально для обычного Gmail); **+ Add users** → свой email |
| **Data Access** | **Add or remove scopes** → вручную `https://www.googleapis.com/auth/drive` → Add → **Save** |
| **Clients** | **Create OAuth client** → тип **Desktop app** → сохранить **Client ID** и **Client secret** |
| **Audience** | **Publish app** → Confirm → статус **In production** |

> **Публикация обязательна.** В режиме Testing доступ сбрасывается каждые 7 дней, и автосинхронизация будет падать. Проверка Google для личного приложения не нужна. Если **Publish app** неактивна — не заполнены поля Branding (домашняя страница, политика, домен).

## Шаг 3. Подключить Google Диск к rclone (на каждом компьютере)

```
rclone config
```

| Вопрос | Ответ |
| --- | --- |
| `n/s/q>` | `n` |
| `name>` | `gdrive` |
| `Storage>` | `drive` (словом — номера в списке меняются) |
| `client_id>` | Client ID из шага 2 |
| `client_secret>` | Client secret из шага 2 |
| `scope>` | `1` |
| `service_account_file>` | Enter |
| `Edit advanced config?` | `n` |
| `Use web browser to automatically authenticate…?` | `y` → войти **личным** аккаунтом. Экран «Приложение не проверено» — это ваше приложение: **«Дополнительно» → «Перейти на сайт foldersync»** → разрешить |
| `Configure this as a Shared Drive (Team Drive)?` | `n` |
| `Keep this "gdrive" remote?` | `y` |
| меню | `q` |

Проверка: `rclone lsd gdrive:` — список папок Диска.

> ⚠️ **Безопасность.** В конце `rclone config` печатает `client_secret` и `token` — **никому их не пересылайте** и не публикуйте (в чат, тикет, скриншот). Если это случилось: Google Cloud → Clients → ваш клиент → **Add secret**, старый → **Disable** → **Delete**; затем `rclone config` → `gdrive` → `e` → новый secret → обновить токен (`y`, войти заново). Файл `rclone.conf` с токенами в репозиторий не коммитится (`.gitignore`).

## Шаг 4. Установить foldersync

**macOS:**

```
cd путь/к/foldersync/mac
bash install.sh
```

**Windows (PowerShell):**

```
cd путь\к\foldersync\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## Шаг 5. Указать папки

Файл настроек — macOS: `~/.foldersync/pairs.conf`, Windows: `%USERPROFILE%\.foldersync\pairs.conf`.

```
# ЛОКАЛЬНАЯ_ПАПКА => gdrive:ПАПКА_НА_ДИСКЕ
~/Документы-архив => gdrive:Документы-архив
~/Семья => gdrive:Семья
```

- Слева — папка на этом компьютере (где угодно), справа — на Google Диске. Правая часть **одинаковая** на всех компьютерах
- Несуществующие папки создаются при первой синхронизации
- **macOS:** если папка в «Документах», «Рабочем столе» или «Загрузках», фоновой синхронизации может понадобиться **Полный доступ к диску** для `/bin/bash` (Системные настройки → Конфиденциальность и безопасность). Проще держать папки прямо в домашней

## Шаг 6. Первая синхронизация

**Сначала на компьютере, где папки уже с файлами:**

```
bash ~/.foldersync/foldersync.sh --init
```

**Затем на втором компьютере:**

```
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\.foldersync\foldersync.ps1 -Init
```

Дальше всё работает само. Добавили новую пару — снова `--init` / `-Init` (затронет только новые пары).

---

## Правила

- Не править один и тот же файл одновременно на двух компьютерах — будет конфликт (обе версии сохранятся)
- Удалённое на одном компьютере удаляется и на другом; копии — в `_foldersync_backup` на Диске, в `~/.foldersync/backup` и в корзине Google Диска (30 дней)
- Уведомление об ошибке → журнал `~/.foldersync/logs/`. Если rclone просит `--resync` — **не делать вслепую**, сначала проверить, не пропали ли файлы
- Ошибка авторизации (`invalid_grant`, `token expired`) → проверить, что приложение **опубликовано** (шаг 2.3), затем `rclone config reconnect gdrive:`
- Включить двухэтапную проверку в Google-аккаунте

## Отключить

macOS: `bash mac/uninstall.sh` · Windows: `powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1`. Файлы, настройки и резервные копии остаются.

## Статус

- macOS-скрипт протестирован: первая синхронизация, правки с обеих сторон, удаление с резервной копией, конфликт, кириллица и пробелы в именах
- Windows-скрипт написан по той же логике, на Windows пока не проверялся

## Лицензия

MIT
