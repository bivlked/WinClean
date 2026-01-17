# WinClean - Инструкции для Claude

> Последнее обновление: 2026-01-17
> Текущая версия скрипта: 2.12

---

## 1. О проекте

**WinClean** — комплексный PowerShell скрипт для автоматического обслуживания Windows 11.

| Параметр | Значение |
|----------|----------|
| **Версия** | 2.12 |
| **Язык** | PowerShell 7.1+ |
| **Платформа** | Windows 11 (23H2/24H2/25H2) |
| **Лицензия** | MIT |
| **Автор** | bivlked |
| **Репозиторий** | https://github.com/bivlked/WinClean |
| **PSGallery** | https://www.powershellgallery.com/packages/WinClean |

### Статус публикации

- **GitHub**: ✅ Опубликован, активно развивается
- **PSGallery**: ✅ Опубликован (v2.12, 17.01.2026)
- **CI/CD**: ✅ GitHub Actions с PSScriptAnalyzer

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
├── CLAUDE.md                 # Этот файл — инструкции для Claude
├── assets/
│   └── logo.svg              # Логотип проекта
├── docs/                     # Черновики документации (НЕ в git!)
│   ├── habr-article.md       # Статья для Хабра
│   └── habr-article-info.md  # Документация по статье
└── .github/
    ├── workflows/ci.yml      # GitHub Actions CI
    ├── PULL_REQUEST_TEMPLATE.md
    └── ISSUE_TEMPLATE/       # Шаблоны issues (bug, feature, question)
```

---

## 3. Архитектура скрипта

WinClean.ps1 — монолитный скрипт (~2700 строк) с модульной структурой.

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
$script:Version = "2.10"           # Единый источник версии
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
# Test-ScriptUpdate — проверяет версию на PSGallery
# Invoke-ScriptUpdate — показывает UI и выполняет обновление
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
5. `NOTES` секция — добавить "Changes in X.X"
6. Badges в README.md и README_RU.md
7. Диаграмму "Execution Flow" в README (версия в заголовке)
8. CHANGELOG.md — новая запись в начале

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

**Проверки:**
- PSScriptAnalyzer (Warning, Error)
- Синтаксис PowerShell

**Исключения PSScriptAnalyzer** (допустимые для CLI):
- PSAvoidUsingWriteHost — это интерактивная утилита
- PSAvoidUsingEmptyCatchBlock — намеренное подавление ошибок
- PSUseShouldProcessForStateChangingFunctions — не применимо

---

## 7. Текущие задачи и планы

### Выполнено (январь 2026)

- [x] Публикация в PSGallery (v2.9, затем v2.10)
- [x] CI/CD с PSScriptAnalyzer
- [x] Функция авто-проверки обновлений (v2.10)
- [x] Документация EN/RU синхронизирована
- [x] Issue templates (bug, feature, question)
- [x] Черновик статьи для Хабра

### В работе

- [ ] Публикация статьи на Хабре (песочница)
- [ ] Скриншоты для статьи

### Планы на будущее

- [ ] Профили очистки (aggressive / moderate / minimal)
- [ ] Поддержка WSL дистрибутивов (apt/snap кэши)
- [ ] Интеграция с Windows Terminal
- [ ] Scoop bucket для установки
- [ ] Английская статья для Dev.to

---

## 8. Продвижение проекта

### Стратегия

1. **Хабр** (приоритет) — статья в песочнице
2. **Reddit** — r/PowerShell, r/windows11
3. **Dev.to** — короткая статья на английском
4. **Twitter/X** — анонс с GIF

### Материалы для Хабра

Файлы в `docs/`:
- `habr-article.md` — текст статьи (~1300 слов)
- `habr-article-info.md` — полная документация по статье

**Заголовок:** "Один скрипт вместо десяти утилит: наводим порядок в Windows 11"

**Хабы:** Системное администрирование, DevOps

**Статус:** Текст готов, ожидает скриншоты

---

## 9. Частые задачи

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

## 10. История ключевых решений

### Почему монолитный скрипт?

- Простота установки (`Install-Script`)
- Нет зависимостей между файлами
- Легко копировать и передавать
- PSGallery лучше работает с одним файлом

### Почему PowerShell 7.1+?

- `ForEach-Object -Parallel` (появился в 7.0)
- Улучшенная обработка ошибок
- Лучшая производительность
- Активная поддержка Microsoft

### Почему synchronized hashtable?

- Thread-safe для параллельного выполнения
- Простой доступ через `+=` вместо Interlocked
- Избегает багов с `[ref]` и hashtable элементами

### Почему Write-Host, а не Write-Output?

- Это интерактивная CLI утилита, не модуль
- Write-Host даёт цветной вывод
- Не загрязняет pipeline
- PSScriptAnalyzer исключение оправдано

---

## 11. Известные проблемы и решения

| Проблема | Решение | Версия |
|----------|---------|--------|
| PSWindowsUpdate зависает при установке | TLS 1.2 + таймауты | 2.9 |
| Disk Cleanup зависает | Уменьшен таймаут до 7 мин | 2.8 |
| TotalFreedBytes всегда 0 | Заменён Interlocked на += | 2.3 |
| Рекурсия в Clear-RecycleBin | Переименована функция | 1.3 |

---

## 12. Тестирование

### Быстрая проверка

```powershell
# Режим предпросмотра (без изменений)
.\WinClean.ps1 -ReportOnly
```

### PSScriptAnalyzer

```powershell
Invoke-ScriptAnalyzer -Path .\WinClean.ps1 -Severity Warning,Error
```

### Синтаксис

```powershell
$null = [scriptblock]::Create((Get-Content .\WinClean.ps1 -Raw))
```

### Полный запуск

```powershell
# Требует Admin, создаёт Restore Point
.\WinClean.ps1
```

---

## 13. Контакты и ресурсы

- **GitHub Issues**: https://github.com/bivlked/WinClean/issues
- **GitHub Discussions**: https://github.com/bivlked/WinClean/discussions
- **PSGallery**: https://www.powershellgallery.com/packages/WinClean

---

## 14. Заметки для Claude

### При работе с этим проектом

1. **Всегда читать WinClean.ps1** перед изменениями — это единственный файл кода
2. **Синхронизировать README** — EN и RU версии должны быть идентичны по структуре
3. **Обновлять CHANGELOG** — каждое изменение должно быть задокументировано
4. **Версия в нескольких местах** — см. раздел "Версионирование"
5. **docs/ не в git** — черновики и рабочие материалы

### Что помнить о проекте

- Скрипт требует прав администратора
- Создаёт точку восстановления перед изменениями
- Поддерживает -ReportOnly для безопасного предпросмотра
- Лог сохраняется в `%TEMP%\WinClean_*.log`
- Опубликован в PSGallery — нужен API ключ для публикации
- Статья для Хабра готова, ждёт скриншоты
