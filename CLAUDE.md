# WinClean - Инструкции для Claude

> Последнее обновление: 2026-07-20
> Текущая версия скрипта: 2.17 (🔴 НЕ ВЫПУЩЕНА - накапливаем исправления; последний релиз v2.16)

---

## 1. О проекте

**WinClean** - комплексный PowerShell скрипт для автоматического обслуживания Windows 11.

| Параметр | Значение |
|----------|----------|
| **Версия** | 2.17 |
| **Язык** | PowerShell 7.1+ |
| **Платформа** | Windows 11 (23H2/24H2/25H2) |
| **Лицензия** | MIT |
| **Автор** | bivlked |
| **Репозиторий** | https://github.com/bivlked/WinClean |
| **PSGallery** | https://www.powershellgallery.com/packages/WinClean |

### Статус публикации

- **GitHub**: ✅ Опубликован, активно развивается
- **PSGallery**: ✅ Опубликован (v2.13, 18.01.2026; v2.15 и v2.16 не публиковались - решение за пользователем)
- **CI/CD**: ✅ GitHub Actions (PSScriptAnalyzer + Pester)

---

## 2. Структура проекта

```
CleanScript/
├── WinClean.ps1              # Основной скрипт (единственный файл кода)
├── README.md                 # Документация (English)
├── README_RU.md              # Документация (Русский)
├── CHANGELOG.md              # История изменений (Keep a Changelog)
├── LICENSE                   # MIT лицензия
├── CONTRIBUTING.md           # Гайд для контрибьюторов
├── SECURITY.md               # Политика безопасности
├── CLAUDE.md                 # Этот файл - инструкции для Claude
├── assets/
│   └── logo.svg              # Логотип проекта
├── get.ps1                   # Bootstrap: разовый запуск одной командой (irm | iex)
├── install.ps1               # Bootstrap: установка/обновление + ярлык (RunAs admin)
├── tests/                    # Pester тесты (204 всего)
│   ├── Helpers.Tests.ps1     # Unit-тесты helper-функций (65 тестов)
│   ├── Fixes.Tests.ps1       # Валидационные тесты исправлений (111 тестов)
│   └── Integration.Tests.ps1 # Интеграционные тесты в песочнице ФС (28 тестов)
├── tools/                    # Тестовая инфраструктура (не публикуется в PSGallery)
│   ├── Invoke-ReleaseCheck.ps1 # 🔴 Единая проверка перед релизом (fail-closed)
│   ├── Invoke-SmokeTest.ps1  # Смоук: ReportOnly + JSON + геометрия рамок
│   ├── BoxGeometry.ps1       # Автопроверка геометрии консольных рамок
│   └── proxmox/              # Стенд на Proxmox (config/results в .gitignore)
│       ├── New-StandVM.ps1       # Разовая подготовка VM (клон + PS7 + опц. локаль + снапшот)
│       ├── Invoke-StandTest.ps1  # Цикл: rollback -> boot -> run -> assert
│       ├── Invoke-NightlyStand.ps1 # Ночная матрица (cron на proxmos) + Telegram-отчёт
│       ├── Deploy-StandRunner.ps1  # Деплой runner на Proxmox-хост (pwsh, cron, creds)
│       └── StandCommon.ps1       # SSH/guest-agent helpers (+ local-режим на хосте)
├── docs/                     # Черновики документации (НЕ в git!)
│   ├── habr-article.md       # Статья для Хабра
│   ├── habr-article-info.md  # Документация по статье
│   └── Screenshots/          # Скриншоты для статьи
├── .gitignore
└── .github/
    ├── workflows/ci.yml      # GitHub Actions CI (lint + syntax + Pester)
    ├── PULL_REQUEST_TEMPLATE.md
    └── ISSUE_TEMPLATE/       # bug_report.md, feature_request.md, success_story.md, config.yml
```

---

## 3. Архитектура скрипта

WinClean.ps1 - монолитный скрипт (3185 строк) с модульной структурой на `#region`.

### Основные секции

⚠️ Границы ниже соответствуют реальным `#region` (сверено 20.07.2026). При правках проверять командой, а не доверять таблице: `grep -n "^#region" WinClean.ps1`.

| Строки | Секция (`#region`) | Что внутри |
|--------|--------------------|------------|
| 1-251 | PSScriptInfo + Help + param() | Метаданные PSGallery, comment-based help, блок параметров |
| 253-307 | INITIALIZATION | Константы, `$script:Stats`, `$script:Version` (293), `$script:ProtectedPaths` |
| 309-447 | LOGGING FUNCTIONS | `Write-Log`, `Update-Progress`, `Clear-AllProgress` |
| 449-1173 | HELPER FUNCTIONS | `Test-*`, `Format-FileSize`, `Remove-FolderContent`, `New-SystemRestorePoint`, self-update |
| 1175-1573 | UPDATE FUNCTIONS | `Update-WindowsSystem`, `Update-Applications` |
| 1575-2352 | CLEANUP FUNCTIONS | temp, браузеры, кэш WU, корзина, системные кэши, журналы, DNS, privacy, телеметрия, Windows.old |
| 2354-2492 | DEVELOPER CLEANUP | `Clear-DeveloperCaches` |
| 2494-2653 | DOCKER/WSL CLEANUP | `Clear-DockerWSL`, компактирование VHDX |
| 2655-2742 | VISUAL STUDIO CLEANUP | `Clear-VisualStudio` |
| 2744-3222 | SYSTEM CLEANUP | `Clear-KernelDumps`, `Show-DiskSpaceReport`, `Clear-DriverStore`, `Invoke-DISMCleanup`, `Invoke-StorageSense` |
| 3224-конец | MAIN EXECUTION | `Show-Banner`, `Show-FinalStatistics`, `Write-ResultJson`, `Start-WinClean` |

### Ключевые переменные

```powershell
$script:Version = "2.17"           # Единый источник версии
$script:Stats = [hashtable]::Synchronized(@{...})  # Thread-safe статистика
$script:LogPath = "..."            # Путь к лог-файлу
$script:ProtectedPaths = @(...)    # Защищённые пути (никогда не удаляются)
```

### Параллельное выполнение

Используется `ForEach-Object -Parallel` для:
- Очистки кэшей браузеров (6 браузеров параллельно)
- Очистки кэшей разработчика
- Компактирования WSL VHDX файлов

---

## 4. Ключевые функции (добавлены в v2.10)

### Авто-проверка обновлений

При запуске скрипт проверяет PSGallery на наличие новой версии:

```powershell
# Test-ScriptUpdate - проверяет версию на PSGallery
# Invoke-ScriptUpdate - показывает UI и выполняет обновление
```

Особенности:
- Работает только если PSGallery доступен
- Учитывает режим ReportOnly
- Показывает инструкции для ручной установки, если скрипт скачан не через PSGallery

---

## 5. Правила разработки

### Версионирование

При выпуске новой версии обновить (номера строк сверены 20.07.2026 после выпуска v2.16; проверять `grep -n 'VERSION\|script:Version' WinClean.ps1`):
1. `$script:Version` в WinClean.ps1 (строка 293)
2. `.VERSION` в PSScriptInfo (строка 2)
3. `.RELEASENOTES` в PSScriptInfo (строки 14-21)
4. `SYNOPSIS` (строка 28)
5. `NOTES` секция (строки 42, 44) - `Version:` и "Changes in X.X"
6. Badges в README.md и README_RU.md (строка 9 в обоих)
7. Диаграмму "Execution Flow" в README (версия в заголовке, строка 339 в обоих)
8. CHANGELOG.md - новая запись в начале
9. `CONTRIBUTING.md` - счётчик тестов, если он менялся (строки 131 и 239)

⚠️ **Счётчик тестов считать только прогоном Pester**, не грепом `It`: 7 блоков размножаются через `-ForEach`, поэтому наивный подсчёт занижает результат.

🔴 **Перед выпуском гонять `pwsh tools/Invoke-ReleaseCheck.ps1`** - он проверяет пункты 1-9 этого списка машинно. Ручная сверка стабильно расходится с реальностью: так разъехались счётчики тестов (94 / 139 / 141 в трёх файлах) и номера строк в самом чек-листе.

🔴 **9. GitHub Release с ассетами - ОБЯЗАТЕЛЕН, иначе one-liner'ы отдают СТАРУЮ версию.**
`get.ps1` и `install.ps1` берут скрипт из **последнего GitHub Release** (fail-closed, без отката на main) и сверяют SHA256 с ассетом `WinClean.ps1.sha256`. Просто `git push` новую версию НЕ публикует - пользователи продолжат получать предыдущий релиз.
```powershell
$hash = (Get-FileHash .\WinClean.ps1 -Algorithm SHA256).Hash
"$hash  WinClean.ps1" | Out-File "$env:TEMP\WinClean.ps1.sha256" -Encoding ascii -NoNewline
gh release create vX.Y ".\WinClean.ps1#WinClean.ps1" "$env:TEMP\WinClean.ps1.sha256#WinClean.ps1.sha256" --title "WinClean vX.Y" --notes "..."
# при правке скрипта внутри уже выпущенного релиза: gh release upload vX.Y ... --clobber (хеш пересчитать!)
```

### Публикация в PSGallery

```powershell
# API ключ хранится в переменной окружения PSGALLERY_API_KEY (User scope)
Publish-PSResource -Path .\WinClean.ps1 -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY
```

**Где хранится ключ:** переменная окружения `PSGALLERY_API_KEY` (User scope)

### Стиль кода

- Функции: `Verb-Noun` (PowerShell conventions)
- Переменные: `$camelCase` для локальных, `$script:PascalCase` для глобальных
- Комментарии: на английском
- Отступы: 4 пробела
- Write-Host: допускается (это CLI утилита, не модуль)

### Безопасность

- Никогда не удалять пути из `$script:ProtectedPaths`
- Всегда `-ErrorAction SilentlyContinue` для необязательных операций
- Проверять `$ReportOnly` перед любыми изменениями
- Использовать `try/finally` для восстановления служб
- Создавать Restore Point перед изменениями

---

## 6. CI/CD

### GitHub Actions

Файл: `.github/workflows/ci.yml`

**Проверки (3 job'а):**
1. **lint** - PSScriptAnalyzer (Warning, Error)
2. **syntax** - Проверка синтаксиса PowerShell
3. **test** - Pester тесты (204, запускается после lint и syntax; интеграционные требуют admin - на GitHub runners это выполняется)

**Исключения PSScriptAnalyzer** (допустимые для CLI):
- PSAvoidUsingWriteHost - это интерактивная утилита
- PSAvoidUsingEmptyCatchBlock - намеренное подавление ошибок
- PSUseShouldProcessForStateChangingFunctions - не применимо

### Pester тесты (v2.13+)

- `tests/Helpers.Tests.ps1` - 65 unit-тестов, `tests/Fixes.Tests.ps1` - 111 тестов, `tests/Integration.Tests.ps1` - 28 интеграционных (песочница ФС, требуют admin)
- Особенности: функции в BeforeAll (не AST), regex для locale-независимости, отдельные It блоки

---

## 7. Текущие задачи

### В работе
- [ ] **Публикация v2.15 / v2.16 в PSGallery** (решение за пользователем; GitHub Release выпускается всегда, one-liner'ы работают от него). Команда - в разделе "Публикация в PSGallery" ниже
- [ ] Публикация статьи на Хабре (`docs/habr-article.md` - текст готов, ждёт скриншоты). ⚠️ Текст писался под старую версию - сверить с v2.16 (появились get.ps1/install.ps1, стенд, ночные прогоны, очистка Driver Store)

### v2.17 - В РАБОТЕ, релиз НЕ выпускать без команды пользователя

Решение 20.07.2026: исправления накапливаются в `main`, тег не ставится. Это безопасно -
`get.ps1` и `install.ps1` берут скрипт из **последнего релиза** (v2.16), а не из `main`,
поэтому незарелиженный код до пользователей не доходит.

Содержимое 2.17: устранение тихих отказов (17 мест, найдено агентом `silent-failure-hunter`).
Суть класса дефектов: операция молча не срабатывает, а лог рапортует успех. Подробности в
CHANGELOG, незакрытые находки - в `MyAI-g7rc`.

### v2.16 - ВЫПУЩЕНА 20.07.2026

Эпик **`MyAI-y8j4`**. Полный список отклонённого с обоснованием - в описании эпика, **не переоткрывать** (winget-драйверы, вендорские SDK, автоустановка драйверов, sfc/ScanHealth, defrag-анализ, `Get-ComputerInfo`).

| Задача | Что | Статус |
|--------|-----|--------|
| `.1` | Очистка Driver Store | ✅ сделано, замер 451.8 МБ / 31 пакет |
| `.5` | Отчёт "куда ушло место" + чистка дампов ядра | ✅ сделано, дампы 8.78 ГБ |
| `.7` | Гигиена документации | ✅ сделано |
| `MyAI-kwvt` + `MyAI-g7rc` | 10 дефектов аудита | ✅ сделано (кроме п.1, см. ниже) |
| `.2` | Показ обновлений драйверов из WU | отложено на следующий релиз |
| `.3` | Инвентарь драйверов + проблемные устройства | отложено |
| `.4` | Быстрая секция здоровья (SMART, целостность образа, WinRE) | отложено |
| `.6` | Дельта между прогонами + сбор событий + HTML | отложено |

🔴 **`MyAI-g7rc` п.1 НЕ исправлен намеренно - требует живой проверки на стенде.** Статический анализ и эксперимент противоречат друг другу: в `PSWindowsUpdate.dll` зашита строка `" and IsHidden = 0"` (по ней скрытые исключаются сами), но прогон 19.07 дал `-UpdateType Driver` -> 0 против `-Category "Drivers"` -> 1, и это был именно скрытый драйвер. **Не чинить вслепую**: сначала воспроизвести на VM 190/191.

🔴 **Durable-факты разведки** (проверено, не теория): драйверов в winget НЕТ; exit code DISM и sfc НЕ отражает здоровье (оба вернули 0 при найденном повреждении); `pnputil` меняет язык вывода от кодовой страницы консоли - парсить только `/format xml`; WU способен предлагать драйвер СТАРШЕ установленного. Подробности: память `windows-driver-and-health-facts`.

### Сделано (19.07.2026, чтобы не переоткрывать)
- ✅ Интеграционное тестирование в VM - закрыто **стендом на Proxmox** (VM 190 RU + VM 191 EN), Hyper-V не понадобился
- ✅ Установка одной командой - `get.ps1` / `install.ps1` (см. раздел 2 и README)
- ✅ Ночные автопрогоны стенда с Telegram-отчётом (cron 03:30 на proxmos)

### Планы
- [ ] Профили очистки (aggressive / moderate / minimal)
- [ ] Поддержка WSL дистрибутивов (apt/snap кэши)
- [ ] Scoop bucket для установки
- [ ] Продвижение: Reddit (r/PowerShell), Dev.to
- [ ] Опционально: еженедельный прогон стенда в режиме `FullWithUpdates` (сейчас ночью только `Full` без обновлений)

---

## 8. Частые задачи

### Добавление нового типа кэша

1. Найти функцию `Clear-*Caches` (DevCaches, SystemCaches, и т.д.)
2. Добавить путь в массив `$cachePaths`
3. Добавить в README описание (обе версии)
4. Обновить CHANGELOG

### Добавление нового параметра

1. Добавить в `param()` блок
2. Добавить в README таблицу параметров (обе версии)
3. Обновить `$script:TotalSteps` если влияет на прогресс
4. Добавить проверку в соответствующую функцию
5. Обновить CHANGELOG

### Исправление бага

1. Создать ветку `fix/description`
2. Внести исправление
3. Обновить CHANGELOG (секция Fixed)
4. Увеличить patch-версию
5. PR → merge → publish to PSGallery

---

## 9. Тестирование

```powershell
# 🔴 ПЕРЕД РЕЛИЗОМ - одна команда вместо ручного чек-листа (exit 1 при провале):
pwsh tools/Invoke-ReleaseCheck.ps1                  # версия во всех 9 местах, тире, счётчики
                                                    # тестов в доках, CHANGELOG, синтаксис,
                                                    # линтер, Pester, смоук, чистота git
pwsh tools/Invoke-ReleaseCheck.ps1 -IncludeStand    # + боевой прогон на VM (минуты)
pwsh tools/Invoke-ReleaseCheck.ps1 -VerifyPublished # ПОСЛЕ выпуска: ассеты релиза и SHA256

Invoke-Pester ./tests -Output Detailed              # 204 Pester теста (65+111+28)
pwsh tools/Invoke-SmokeTest.ps1                     # Смоук: ReportOnly + геометрия UI
pwsh tools/proxmox/Invoke-StandTest.ps1 -Mode Report # Стенд на Proxmox (RU=VM 190, EN: -ConfigPath ...en.json = VM 191)
# Ночная матрица: cron 03:30 на proxmos (/opt/winclean-stand, /etc/cron.d/winclean-stand), отчёт в Telegram
Invoke-ScriptAnalyzer -Path .\WinClean.ps1 -Severity Warning,Error
.\WinClean.ps1 -ReportOnly                          # Предпросмотр без изменений
```

---

## 10. Важное для Claude

- **WinClean.ps1** - единственный файл кода, всегда читать перед изменениями
- **Синхронизировать README** EN и RU при любых изменениях
- **Обновлять CHANGELOG** при каждом изменении
- **Версия в нескольких местах** - см. раздел "Версионирование"
- **docs/ не в git** - черновики (статья для Хабра, ждёт скриншоты)
- **Pester тесты**: функции в BeforeAll (не AST), regex для locale-независимости, отдельные It блоки
- 🔴 **Боевые прогоны скрипта - ТОЛЬКО на стенде, не на рабочей станции.** 18.07.2026 e2e-проверка «безопасного» dry-run отработала по-боевому (сплаттинг массива в `get.ps1` биндил `-ReportOnly` позиционно в `LogPath`). Отсюда два durable-правила: у любого «безопасного» прогона сначала ВЕРИФИЦИРОВАТЬ режим (маркер `REPORT MODE` в выводе / `ReportOnly:true` в result JSON), а деструктивное гонять на VM 190/191. Разбор: память `ps-array-splat-positional-trap`
- **Стенд и отчёты**: конфиги стендов `tools/proxmox/stand.config*.json` в git НЕ хранятся (только `.example`); runner на proxmos в `/opt/winclean-stand` (редеплой - `pwsh tools/proxmox/Deploy-StandRunner.ps1`); ночные отчёты шлёт бот **@bivalerter_bot** в личный чат, доставка ТОЛЬКО через SOCKS-шлюз .210 (direct режется DPI). Механика транспорта в гостя: память `proxmox-guest-exec-transport`
- Ссылки: [Issues](https://github.com/bivlked/WinClean/issues) | [PSGallery](https://www.powershellgallery.com/packages/WinClean)

---

## Навигация по коду (Serena + ast-grep)

- **Serena MCP** подключён в этой папке (символьная навигация через LSP). Для понимания и рефакторинга кода предпочитай его инструменты обычным Read/Grep: `get_symbols_overview` (оглавление файла), `find_symbol` (определение по имени), `find_referencing_symbols` (кто вызывает), `replace_symbol_body` / `rename_symbol` (точечная правка). Проверка: `/mcp` -> serena connected.
- **ast-grep** (`ast-grep` / `sg`, в PATH) - структурный поиск/замена по AST, когда нужна синтаксис-осведомлённость (точнее regex-Grep).
- Обычный Grep - для первичного текстового поиска.
