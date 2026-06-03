# WinClean - Инструкции для Claude

> Последнее обновление: 2026-01-18
> Текущая версия скрипта: 2.13

---

## 1. О проекте

**WinClean** - комплексный PowerShell скрипт для автоматического обслуживания Windows 11.

| Параметр | Значение |
|----------|----------|
| **Версия** | 2.13 |
| **Язык** | PowerShell 7.1+ |
| **Платформа** | Windows 11 (23H2/24H2/25H2) |
| **Лицензия** | MIT |
| **Автор** | bivlked |
| **Репозиторий** | https://github.com/bivlked/WinClean |
| **PSGallery** | https://www.powershellgallery.com/packages/WinClean |

### Статус публикации

- **GitHub**: ✅ Опубликован, активно развивается
- **PSGallery**: ✅ Опубликован (v2.13, 18.01.2026)
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
├── tests/                    # Pester тесты (v2.13+)
│   ├── Helpers.Tests.ps1     # Unit-тесты helper-функций (52 теста)
│   └── Fixes.Tests.ps1       # Валидационные тесты исправлений (42 теста)
├── docs/                     # Черновики документации (НЕ в git!)
│   ├── habr-article.md       # Статья для Хабра
│   └── habr-article-info.md  # Документация по статье
└── .github/
    ├── workflows/ci.yml      # GitHub Actions CI (lint + syntax + Pester)
    ├── PULL_REQUEST_TEMPLATE.md
    └── ISSUE_TEMPLATE/       # Шаблоны issues (bug, feature, question)
```

---

## 3. Архитектура скрипта

WinClean.ps1 - монолитный скрипт (~2700 строк) с модульной структурой.

### Основные секции

| Строки | Секция | Описание |
|--------|--------|----------|
| 1-167 | PSScriptInfo + Help | Метаданные для PSGallery, документация |
| 168-220 | Initialization | Константы, $script:Stats, $script:Version |
| 220-430 | Logging & Helpers | Write-Log, Test-*, Format-*, утилиты |
| 430-560 | **Update Check** | Test-ScriptUpdate, Invoke-ScriptUpdate (v2.10) |
| 560-1200 | Clear-* Functions | Очистка (браузеры, система, dev, Docker, VS) |
| 1200-1600 | Update-* Functions | Windows Update, winget |
| 1600-2000 | Privacy & Telemetry | DNS, event logs, телеметрия |
| 2000-2400 | UI Functions | Banner, Progress, FinalStatistics |
| 2400-2700 | Main Function | Start-WinClean (оркестрация) |

### Ключевые переменные

```powershell
$script:Version = "2.13"           # Единый источник версии
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

При выпуске новой версии обновить:
1. `$script:Version` в WinClean.ps1 (строка ~208)
2. `.VERSION` в PSScriptInfo (строка 2)
3. `.RELEASENOTES` в PSScriptInfo (строки 14-18)
4. `SYNOPSIS` (строка 24)
5. `NOTES` секция - добавить "Changes in X.X"
6. Badges в README.md и README_RU.md
7. Диаграмму "Execution Flow" в README (версия в заголовке)
8. CHANGELOG.md - новая запись в начале

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
3. **test** - Pester тесты (94 теста, запускается после lint и syntax)

**Исключения PSScriptAnalyzer** (допустимые для CLI):
- PSAvoidUsingWriteHost - это интерактивная утилита
- PSAvoidUsingEmptyCatchBlock - намеренное подавление ошибок
- PSUseShouldProcessForStateChangingFunctions - не применимо

### Pester тесты (v2.13+)

- `tests/Helpers.Tests.ps1` - 52 unit-теста, `tests/Fixes.Tests.ps1` - 42 теста
- Особенности: функции в BeforeAll (не AST), regex для locale-независимости, отдельные It блоки

---

## 7. Текущие задачи

### В работе
- [ ] Публикация статьи на Хабре (`docs/habr-article.md` - текст готов, ждёт скриншоты)
- [ ] Интеграционное тестирование в Hyper-V VM

### Планы
- [ ] Профили очистки (aggressive / moderate / minimal)
- [ ] Поддержка WSL дистрибутивов (apt/snap кэши)
- [ ] Scoop bucket для установки
- [ ] Продвижение: Reddit (r/PowerShell), Dev.to

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

## 10. Тестирование

```powershell
Invoke-Pester ./tests -Output Detailed              # 94 Pester теста
Invoke-ScriptAnalyzer -Path .\WinClean.ps1 -Severity Warning,Error
.\WinClean.ps1 -ReportOnly                          # Предпросмотр без изменений
```

---

## 11. Важное для Claude

- **WinClean.ps1** - единственный файл кода, всегда читать перед изменениями
- **Синхронизировать README** EN и RU при любых изменениях
- **Обновлять CHANGELOG** при каждом изменении
- **Версия в нескольких местах** - см. раздел "Версионирование"
- **docs/ не в git** - черновики (статья для Хабра, ждёт скриншоты)
- **Pester тесты**: функции в BeforeAll (не AST), regex для locale-независимости, отдельные It блоки
- Ссылки: [Issues](https://github.com/bivlked/WinClean/issues) | [PSGallery](https://www.powershellgallery.com/packages/WinClean)

---

## Навигация по коду (Serena + ast-grep)

- **Serena MCP** подключён в этой папке (символьная навигация через LSP). Для понимания и рефакторинга кода предпочитай его инструменты обычным Read/Grep: `get_symbols_overview` (оглавление файла), `find_symbol` (определение по имени), `find_referencing_symbols` (кто вызывает), `replace_symbol_body` / `rename_symbol` (точечная правка). Проверка: `/mcp` -> serena connected.
- **ast-grep** (`ast-grep` / `sg`, в PATH) - структурный поиск/замена по AST, когда нужна синтаксис-осведомлённость (точнее regex-Grep).
- Обычный Grep - для первичного текстового поиска.
