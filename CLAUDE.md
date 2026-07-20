# WinClean - Инструкции для Claude

> Последнее обновление: 2026-07-20
> Текущая версия скрипта: 2.17 (ВЫПУЩЕНА 20.07.2026, GitHub Release с ассетами)

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
├── tests/                    # Pester тесты (309 всего)
│   ├── Helpers.Tests.ps1     # Unit-тесты helper-функций (105 тестов, дот-сорсят продукт - нужны права админа)
│   ├── Fixes.Tests.ps1       # Валидационные тесты исправлений (138 тестов)
│   └── Integration.Tests.ps1 # Интеграционные тесты в песочнице ФС (66 тестов)
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

WinClean.ps1 - монолитный скрипт (4448 строк на 20.07.2026, проверять `wc -l WinClean.ps1` - число растёт с каждым релизом) с модульной структурой на `#region`.

### Основные секции

⚠️ Границы ниже соответствуют реальным `#region` (сверено 20.07.2026, после группы B аудита MyAI-dtx8). При правках проверять командой, а не доверять таблице: `grep -n "^#region" WinClean.ps1`.

| Строки | Секция (`#region`) | Что внутри |
|--------|--------------------|------------|
| 1-265 | PSScriptInfo + Help + param() | Метаданные PSGallery, comment-based help, блок параметров |
| 266-335 | INITIALIZATION | Константы, `$script:Stats` (+PhasesCompleted/PhasesFailed), `$script:Version`, `$script:ProtectedPaths` |
| 336-492 | LOGGING FUNCTIONS | `Write-Log` (персистентный StreamWriter), `Update-Progress`, `Clear-AllProgress` |
| 493-1590 | HELPER FUNCTIONS | `Test-*`, `Format-FileSize`, recovery-маркер (`Set-RunMarker`/`Clear-RunMarker`/`Invoke-StaleMarkerRecovery`), `Get-WindowsUpdateWithTimeout`, `Get-FolderSizeChecked`, `Remove-FolderContent`, `Remove-FilesByPattern`, `New-SystemRestorePoint`, self-update |
| 1591-2022 | UPDATE FUNCTIONS | `Update-WindowsSystem`, `Update-Applications` |
| 2023-2868 | CLEANUP FUNCTIONS | temp, браузеры, кэш WU (маркер WUServiceStop), корзина, системные кэши, журналы (EventLogSession), DNS, privacy, телеметрия, Windows.old |
| 2869-3008 | DEVELOPER CLEANUP | `Clear-DeveloperCaches` |
| 3009-3169 | DOCKER/WSL CLEANUP | `Clear-DockerWSL`, компактирование VHDX |
| 3170-3252 | VISUAL STUDIO CLEANUP | `Clear-VisualStudio` |
| 3253-3941 | SYSTEM CLEANUP | `Clear-KernelDumps`, `Show-DiskSpaceReport`, `Get-SupersededDriverCandidate`, `Get-RedundantDriverPackage`, `Clear-DriverStore`, `Invoke-DISMCleanup`, `Invoke-StorageSense` |
| 3942-конец | MAIN EXECUTION | `Show-Banner`, `Show-FinalStatistics`, `Write-ResultJson`, `Invoke-Phase`, `Start-WinClean` |

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
1. `$script:Version` в WinClean.ps1 (строка 320; проверять `grep -n '\$script:Version =' WinClean.ps1` - номер плывёт)
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
3. **test** - Pester тесты (309, запускается после lint и syntax; интеграционные требуют admin - на GitHub runners это выполняется)

**Исключения PSScriptAnalyzer** (допустимые для CLI):
- PSAvoidUsingWriteHost - это интерактивная утилита
- PSAvoidUsingEmptyCatchBlock - намеренное подавление ошибок
- PSUseShouldProcessForStateChangingFunctions - не применимо

### Pester тесты (v2.13+)

- `tests/Helpers.Tests.ps1` - 105 unit-тестов (дот-сорсят WinClean.ps1), `tests/Fixes.Tests.ps1` - 138 тестов, `tests/Integration.Tests.ps1` - 66 интеграционных (песочница ФС, требуют admin)
- Особенности: функции в BeforeAll (не AST), regex для locale-независимости, отдельные It блоки

---

## 7. Текущие задачи

### В работе
- [ ] **Публикация в PSGallery отстала на 4 версии**: там до сих пор v2.13 (18.01.2026), не публиковались 2.14/2.15/2.16/2.17. Решение за пользователем. ⚠️ Значение выросло: PSGallery - единственный путь, по которому работает встроенная авто-проверка обновлений (`Test-ScriptUpdate`), то есть установленные через PSGallery копии не узнают о критическом фиксе bootstrap из 2.17. One-liner'ы от GitHub Release при этом работают. Команда - в разделе "Публикация в PSGallery" ниже
- [ ] Публикация статьи на Хабре (`docs/habr-article.md` - текст готов, ждёт скриншоты). ⚠️ Текст писался под старую версию - сверить с v2.17 (появились get.ps1/install.ps1, стенд, ночные прогоны, очистка Driver Store, пофазное выполнение)

### v2.17 - ВЫПУЩЕНА 20.07.2026

Релиз корректности и закалки, без новых функций. Пять проходов ревью по кодовой базе 2.16:

1. **Тихие отказы** (17 мест, агент `silent-failure-hunter`): операция молча не срабатывает, а лог рапортует успех.
2. **Полный аудит кодовой базы** (4 параллельные проверки + ревью Codex), более 60 находок. Самое важное:
   - 🔴 **верификация SHA256 в bootstrap была fail-OPEN**: пряталась в `if ($hashAsset)`, релиз без ассета хеша запускался elevated вообще без проверки. Плюс откат на `raw.githubusercontent.com` по тегу вопреки комментарию «fail closed», и сравнение хешей через `-notlike` (wildcard: одна `*` верифицировала что угодно). Урок: **комментарий в коде не является реализацией**, и я успел задокументировать это несуществующее свойство в SECURITY.md;
   - 🔴 **65 тестов проверяли вставленные копии функций**, а не продукт, и уже разошлись с ним. Теперь дот-сорсинг (следствие: тесты требуют прав администратора);
   - 🔴 мутационная проверка: отключение фильтра возраста **не поймал ни один греп-тест**, поймали два поведенческих. Приоритет поведенческим.
3. **MyAI-dtx8 группа A** (14 низкорисковых правок эффективности/корректности + переработка `Get-RedundantDriverPackage`) + **поведенческие тесты на 8 удаляющих функций**, которых не было вовсе.
4. **MyAI-dtx8 группа B** (самое рискованное: `Remove-FolderContent` - один обход дерева вместо трёх-четырёх, `Get-FolderSize`/`Clear-EventLogs` на raw .NET API, пофазный try/catch с `PhasesCompleted`/`PhasesFailed` в JSON, recovery-маркер после hard kill).
5. 🔴 **Независимое ревью группы B перед релизом (Codex) нашло РЕАЛЬНУЮ регрессию, которую не поймали ни 274 теста, ни мои мутационные проверки**: при переписывании фильтра возраста потерялась половина условия. Оригинал требовал И «нет свежих потомков», И «сама папка старше отсечки»; осталась только первая половина -> свежесозданная ПУСТАЯ папка удалялась (у неё нет потомков, доказывающих свежесть) - ровно так выглядит рабочая папка запущенного установщика. Плюс 4 способа промаха новой recovery-логики. Всё исправлено, на каждый случай добавлен тест.
   **Durable-урок**: мутационное тестирование проверяет только то, что я *подумал* сломать. Оно не находит то, что я потерял, не заметив. Внешнее ревью нашло за один проход то, чего не увидели ни я, ни 274 теста.

222 → 279 тестов за сессию (финал 94+126+59).

### 🔴 НЕЗАКРЫТОЕ после v2.17 - что брать в следующую работу

Сгруппировано по тому, **что именно блокирует**, а не по номерам пунктов: главный разделитель - нужен ли живой стенд.

**A. Требует стенда (VM 190 RU / 191 EN) - за столом не закрыть в принципе**
- `MyAI-g7rc` п.1 - скрытые обновления драйверов. Статический анализ и эксперимент прямо противоречат друг другу (детали ниже в разделе v2.16). **Не чинить вслепую.**
- `MyAI-dtx8` п.4 - формат свойства `Categories` у `Get-WindowsUpdate` плавает между версиями модуля; объединение двух поисков в один требует проверки на реальном WU.
- `MyAI-dtx8` п.19 - боевой `winget upgrade --all` пишет прогресс прямо поверх наших рамок (проверочный вызов редиректится, боевой нет). Самый заметный визуальный дефект прогона.
- `MyAI-dtx8` п.30 - ночная матрица гоняет `main`, а пользователи получают ассет релиза. Битый релиз при здоровом `main` = зелёная ночь.
- Блок «проверить на живой системе» (5 гипотез): реальный процент отсева фильтром возраста в TEMP; читает ли `cleanmgr` StateFlags только при старте; систематически ли совпадают SHA256 между `%SystemRoot%\INF` и FileRepository; VS `Packages_Instances` (состояние инстансов, а не кэш); JetBrains-индекс и Toolbox не должны чиститься.

**B. Объём работы, риска мало**
- `MyAI-dtx8` п.22 - **из 39 функций без поведенческих тестов закрыты 9** (8 удаляющих + `Get-SupersededDriverCandidate`). Осталось ~30, среди них нет удаляющих файлы - это уже не про безопасность, а про регрессии.
- `MyAI-dtx8` п.9/п.29 - `AppUpdatesCount` считает ДОСТУПНЫЕ обновления, а не установленные (`MyAI-296v`); нет dead-man switch у ночного стенда (ночь без прогона неотличима от ночи с прогоном).
- Отложенные дети эпика `MyAI-y8j4`: `.2` показ драйверов WU, `.3` инвентарь устройств, `.4` секция здоровья (SMART/WinRE), `.6` дельта прогонов + HTML.

**C. Осознанно НЕ делать** (чтобы не переоткрывали)
- `Install-WindowsUpdate` не обёрнут в job с таймаутом, в отличие от двух поисков: убийство job не гарантирует отмену агента WU, состояние станет непроверяемым. Поиски read-only, поэтому им таймаут дали.
- Идентификация владельца recovery-маркера по PID: PID переиспользуются, два одновременных elevated-прогона увидят друг друга «протухшими». Требует второго WinClean под админом одновременно - неподдерживаемая конфигурация, а все действия восстановления идемпотентны.
- Список отклонённого из эпика `MyAI-y8j4` (winget-драйверы, вендорские SDK, автоустановка драйверов, sfc/ScanHealth, defrag-анализ, `Get-ComputerInfo`) - обоснование в описании эпика.

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

Invoke-Pester ./tests -Output Detailed              # 309 Pester тестов (105+138+66)
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
- 🔴 **Pester тесты (изменилось 20.07.2026)**: `Helpers.Tests.ps1` и `Fixes.Tests.ps1` теперь **дот-сорсят WinClean.ps1**, а не держат копии его функций. Следствие: **прогон тестов требует прав администратора** (в скрипте `#Requires -RunAsAdministrator`). Копии были тавтологией - поломка в продукте не могла уронить тест, и они уже успели разойтись с оригиналом.
  - Регекс-проверки скоупить к телу функции через `Get-FunctionBody` (в `Fixes.Tests.ps1`), иначе тест находит ту же строку в комментарии или в другой функции и проходит при удалённом коде.
  - **Греп-тест не заменяет поведенческий.** Мутационная проверка 20.07: отключение фильтра возраста не поймал ни один греп-тест, поймали два интеграционных.
  - Пропущенные тесты роняют сборку и релиз-гейт: `-Skip` без прав админа раньше делал провал невидимым.
- 🔴 **Перед релизом - `pwsh tools/Invoke-ReleaseCheck.ps1`** (fail-closed, 14 проверок: версия во всех местах, тире, счётчики тестов, CHANGELOG, синтаксис, линтер, Pester без пропусков, смоук, чистота git; `-IncludeStand` и `-VerifyPublished` опционально).
- 🔴 **Codex: вызывать НАПРЯМУЮ, а не через Agent-инструмент.** Проверено 20.07.2026: `Agent(subagent_type: "codex:codex-rescue")` вернул «Codex CLI is not installed», хотя CLI на месте (0.144.5) и авторизован. Рабочий путь: ``node "C:/Users/biv/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs" task --wait "<промпт>"``. В промпте обязательно `Do NOT use web_search` (иначе зависает навсегда).
- 🔴 **Боевые прогоны скрипта - ТОЛЬКО на стенде, не на рабочей станции.** 18.07.2026 e2e-проверка «безопасного» dry-run отработала по-боевому (сплаттинг массива в `get.ps1` биндил `-ReportOnly` позиционно в `LogPath`). Отсюда два durable-правила: у любого «безопасного» прогона сначала ВЕРИФИЦИРОВАТЬ режим (маркер `REPORT MODE` в выводе / `ReportOnly:true` в result JSON), а деструктивное гонять на VM 190/191. Разбор: память `ps-array-splat-positional-trap`
- **Стенд и отчёты**: конфиги стендов `tools/proxmox/stand.config*.json` в git НЕ хранятся (только `.example`); runner на proxmos в `/opt/winclean-stand` (редеплой - `pwsh tools/proxmox/Deploy-StandRunner.ps1`); ночные отчёты шлёт бот **@bivalerter_bot** в личный чат, доставка ТОЛЬКО через SOCKS-шлюз .210 (direct режется DPI). Механика транспорта в гостя: память `proxmox-guest-exec-transport`
- Ссылки: [Issues](https://github.com/bivlked/WinClean/issues) | [PSGallery](https://www.powershellgallery.com/packages/WinClean)

---

## Навигация по коду (Serena + ast-grep)

- **Serena MCP** подключён в этой папке (символьная навигация через LSP). Для понимания и рефакторинга кода предпочитай его инструменты обычным Read/Grep: `get_symbols_overview` (оглавление файла), `find_symbol` (определение по имени), `find_referencing_symbols` (кто вызывает), `replace_symbol_body` / `rename_symbol` (точечная правка). Проверка: `/mcp` -> serena connected.
- **ast-grep** (`ast-grep` / `sg`, в PATH) - структурный поиск/замена по AST, когда нужна синтаксис-осведомлённость (точнее regex-Grep).
- Обычный Grep - для первичного текстового поиска.
