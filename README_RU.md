<div align="center">

<img src="https://raw.githubusercontent.com/bivlked/WinClean/main/assets/logo.svg" alt="WinClean Logo" width="120" height="120">

# WinClean

### Комплексный скрипт обслуживания Windows 11

[![Последний релиз](https://img.shields.io/github/v/release/bivlked/WinClean?label=релиз&logo=github&color=blue)](https://github.com/bivlked/WinClean/releases/latest)
[![PSGallery](https://img.shields.io/powershellgallery/v/WinClean?label=PSGallery&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/WinClean)
[![CI](https://github.com/bivlked/WinClean/actions/workflows/ci.yml/badge.svg)](https://github.com/bivlked/WinClean/actions/workflows/ci.yml)
[![PowerShell 7.1+](https://img.shields.io/badge/PowerShell-7.1%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![Лицензия: MIT](https://img.shields.io/badge/Лицензия-MIT-green.svg)](LICENSE)

**Одна команда, чтобы обновить, очистить и оптимизировать Windows 11 - безопасно.**

[English](README.md) | [Русский](README_RU.md)

---

[Быстрый старт](#-быстрый-старт) •
[Возможности](#-возможности) •
[Параметры](#-параметры) •
[Безопасность](#%EF%B8%8F-безопасность) •
[Документация](#-подробнее) •
[FAQ](#-faq)

</div>

---

**WinClean** - это бесплатный **скрипт очистки и обслуживания Windows 11** с открытым исходным кодом на **PowerShell**. Одной командой он ставит обновления Windows и приложений, **освобождает место на диске**, очищая временные файлы и кэши браузеров, **чистит кэши разработчика** (npm, pip, NuGet, Docker, WSL, IDE) и выполняет глубокую очистку системы - с точкой восстановления, защищёнными системными путями и режимом предпросмотра, чтобы ничего важного не пострадало.

> 💡 **Средний результат:** освобождается 5-20 ГБ, в зависимости от использования системы.

---

## 🚀 Быстрый старт

> **Требования:** PowerShell 7.1+ (`winget install Microsoft.PowerShell`) и терминал от имени **администратора** (Win+X -> Терминал (Администратор)).

**Сначала посмотрите, что будет сделано (предпросмотр без изменений):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1))) -ReportOnly
```

**Разовый запуск (обновления + очистка):**

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/get.ps1 | iex
```

**Установка (или обновление) + ярлык на рабочем столе, всегда с правами администратора:**

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/install.ps1 | iex
```

<table>
<tr>
<td>

### 🔒 Почему one-liner можно доверять

- Bootstrap-скрипты скачивают WinClean из **последнего GitHub Release** и **сверяют SHA256** с опубликованным ассетом `WinClean.ps1.sha256`. Проверка **fail-closed**: несовпадение или отсутствие ассета прерывают запуск, отката на изменяемую ветку нет.
- `install.ps1` ставит скрипт в `%ProgramFiles%\WinClean` (только для администратора), поэтому ярлык нельзя подменить.
- `-ReportOnly` показывает ровно то, что будет сделано, и ничего не меняет.
- Лицензия MIT, без телеметрии, данные не покидают ваш компьютер. См. **[SECURITY.md](SECURITY.md)** и **[docs/safety.md](docs/safety.md)**.

</td>
</tr>
</table>

<details>
<summary>📥 Альтернативные способы установки</summary>

### 📦 PowerShell Gallery

```powershell
Install-Script -Name WinClean -Scope CurrentUser
```

Затем запустите от имени администратора:
```powershell
WinClean.ps1
```

### Ручная загрузка

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1" -OutFile "WinClean.ps1"
.\WinClean.ps1
```

### Клонирование репозитория

```powershell
git clone https://github.com/bivlked/WinClean.git
cd WinClean
.\WinClean.ps1
```

</details>

---

## 🎯 Зачем WinClean?

<table>
<tr>
<td width="50%">

### 😫 Без WinClean

- Вручную запускать Windows Update
- Открывать каждый браузер для очистки кэша
- Помнить расположение кэшей npm/pip/nuget
- Забывать про очистку Docker месяцами
- Отдельно запускать очистку диска
- Надеяться, что ничего важного не удалил

</td>
<td width="50%">

### 😎 С WinClean

- **Одна команда** делает всё
- **Все браузеры** очищаются автоматически
- **Все инструменты разработки** параллельно
- **Docker и WSL** оптимизированы
- **Глубокая очистка** через DISM
- **Безопасно** - защищённые пути

</td>
</tr>
</table>

---

## ✨ Возможности

<table>
<tr>
<td width="33%" valign="top">

### 🔄 Обновления
- Windows Update (+ драйверы, через PSWindowsUpdate)
- Пакеты winget (в т.ч. Store-пакеты, доступные через winget)

</td>
<td width="33%" valign="top">

### 🗑️ Очистка
- Временные файлы (с учётом возраста)
- Кэши браузеров (7 браузеров)
- Кэши Windows
- Хранилище драйверов (старые версии)
- Устаревшие дампы ядра
- Очистка корзины
- Удаление Windows.old
- Отчёт по месту на диске

</td>
<td width="33%" valign="top">

### 👨‍💻 Разработка
- npm / yarn / pnpm
- pip / Composer
- NuGet / Gradle / Cargo
- Go build cache

</td>
</tr>
<tr>
<td width="33%" valign="top">

### 🐳 Docker и WSL
- Неиспользуемые образы
- Остановленные контейнеры
- Кэш сборки
- Сжатие VHDX WSL2

</td>
<td width="33%" valign="top">

### 🛠️ IDE
- Кэши Visual Studio
- Кэши VS Code
- JetBrains IDE
- MEF cache

</td>
<td width="33%" valign="top">

### 🔒 Приватность
- Очистка DNS кэша
- Очистка журналов событий
- История Run (Win+R)
- История проводника
- Недавние документы
- Телеметрия *(опц.)*

</td>
</tr>
</table>

> **Браузеры:** Edge, Chrome, Brave, Yandex, Opera, Opera GX и Firefox. Для Chrome, Edge и Firefox очищаются все профили, для остальных - профиль по умолчанию. Закладки, пароли и история не затрагиваются. Полный список: **[docs/what-is-cleaned.md](docs/what-is-cleaned.md)**.

---

## 📋 Параметры

| Параметр | Описание | По умолчанию |
|:---------|:---------|:------------:|
| `-SkipUpdates` | Пропустить обновления Windows и winget | `false` |
| `-SkipCleanup` | Пропустить **всю** очистку (система, глубокая, разработчик, Docker/WSL, Visual Studio) | `false` |
| `-SkipRestore` | Пропустить создание точки восстановления | `false` |
| `-SkipDevCleanup` | Пропустить кэши разработчика (npm, pip и т.д.) | `false` |
| `-SkipDockerCleanup` | Пропустить очистку Docker/WSL | `false` |
| `-SkipVSCleanup` | Пропустить очистку Visual Studio | `false` |
| `-DisableTelemetry` | Отключить телеметрию Windows через групповую политику | `false` |
| `-ReportOnly` | **Тестовый режим** - показать, что будет сделано | `false` |
| `-LogPath` | Путь к файлу лога | Авто |
| `-ResultJsonPath` | Машиночитаемый итог прогона (JSON) для автоматизации/CI | Выкл |

> `-SkipCleanup` отключает всю группу очистки целиком. Для более точного контроля, когда системную очистку выполнить нужно, используйте флаги категорий (`-SkipDevCleanup`, `-SkipDockerCleanup`, `-SkipVSCleanup`). Схема `-ResultJsonPath` описана в **[docs/result-json.md](docs/result-json.md)**.

---

## 🎯 Рекомендуемые профили

| Профиль | Команда | Для чего |
|:--------|:--------|:---------|
| **Просмотр** | `.\WinClean.ps1 -ReportOnly` | Первый запуск - посмотреть, что будет очищено, без изменений |
| **Безопасный** | `.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup` | Минимум риска - только временные файлы и кэши |
| **Разработчик** | `.\WinClean.ps1` | Полная очистка - включая npm, pip, nuget, Docker, IDE кэши |
| **Быстрый** | `.\WinClean.ps1 -SkipUpdates -SkipDevCleanup -SkipVSCleanup` | Быстро - только системная очистка |
| **Только обновления** | `.\WinClean.ps1 -SkipCleanup` | Только обновления Windows и приложений, без очистки |

> 💡 **Совет:** Всегда сначала запускайте с `-ReportOnly` для предпросмотра.

---

## 🔧 Требования

| Требование | Версия | Примечания |
|:-----------|:-------|:-----------|
| **Windows** | 11 | Протестировано на 23H2/24H2/25H2 (большинство функций работают и на Windows 10) |
| **PowerShell** | 7.1+ | [Скачать здесь](https://aka.ms/powershell) |
| **Права** | Администратор | Требуется для системных операций |

<details>
<summary>📦 Опциональные зависимости</summary>

| Компонент | Требуется для | Автоустановка |
|:----------|:--------------|:-------------:|
| PSWindowsUpdate | Обновления Windows | ✅ Да |
| winget | Обновления приложений | ❌ Вручную |
| Docker Desktop | Очистка Docker | ❌ Вручную |
| WSL 2 | Оптимизация WSL | ❌ Вручную |

</details>

---

## 🛡️ Безопасность

WinClean создан так, чтобы его можно было безопасно запускать на рабочей машине. Кратко:

| Функция безопасности | Описание |
|:---------------------|:---------|
| 🔄 **Точка восстановления** | Создаётся перед любыми изменениями (отключается `-SkipRestore`) |
| 🛡️ **Защищённые пути** | `C:\Windows`, `C:\Program Files`, `C:\Users` и корни томов никогда не удаляются |
| 📦 **Сохранение пакетов** | `node_modules`, `.nuget\packages`, виртуальные окружения, `vendor` сохраняются |
| 👁️ **Режим предпросмотра** | `-ReportOnly` сначала показывает изменения |
| 🔒 **Fail-closed установка** | One-liner'ы сверяют SHA256 с ассетом релиза |
| 🧪 **Проверка на VM** | Каждый релиз прогоняется end-to-end на реальных Windows 11 VM (ru-RU и en-US) |

<details>
<summary>✅ Очищается vs 🛡️ Сохраняется</summary>

| ✅ Очищается | 🛡️ Сохраняется |
|:-------------|:---------------|
| `%TEMP%\*` | `Документы`, `Загрузки` |
| Кэши браузеров | Закладки, пароли браузеров |
| `npm-cache` | `node_modules` |
| `pip\Cache` | Виртуальные окружения |
| `Composer\cache` | `vendor` |
| `NuGet\v3-cache` | `\.nuget\packages` |
| `\.gradle\build-cache` | `\.gradle\caches\modules` |

</details>

> Полная модель доверия и безопасности, включая Controlled Folder Access и проверку bootstrap: **[docs/safety.md](docs/safety.md)**.

---

## 📊 Порядок выполнения

```
┌────────────────────────────────────────────────────────────────┐
│                     WinClean v2.19                             │
├────────────────────────────────────────────────────────────────┤
│  ПОДГОТОВКА                                                    │
│  ├─ ✓ Проверка прав администратора                             │
│  ├─ ✓ Проверка отложенной перезагрузки                         │
│  └─ ✓ Создание точки восстановления                            │
├────────────────────────────────────────────────────────────────┤
│  ОБНОВЛЕНИЯ                                                    │
│  ├─ 🔄 Обновления Windows (включая драйверы)                   │
│  └─ 🔄 Обновления приложений через Winget                      │
├────────────────────────────────────────────────────────────────┤
│  ОЧИСТКА                                                       │
│  ├─ 🗑️ Временные файлы и кэши браузеров                        │
│  ├─ 🗑️ Кэши разработчика (npm, pip, nuget, gradle)             │
│  ├─ 🐳 Оптимизация Docker и WSL                                │
│  └─ 🛠️ Кэши Visual Studio и IDE                                │
├────────────────────────────────────────────────────────────────┤
│  ГЛУБОКАЯ ОЧИСТКА                                              │
│  ├─ 🔧 Очистка компонентов DISM                                │
│  ├─ 💾 Очистка диска (23 обработчика реестра)                  │
│  ├─ 🚗 Хранилище драйверов (устаревшие пакеты)                 │
│  ├─ 🧹 Старые дампы ядра (старше 30 дней)                      │
│  └─ 📁 Удаление Windows.old (с подтверждением)                 │
├────────────────────────────────────────────────────────────────┤
│  ПРИВАТНОСТЬ (опционально)                                     │
│  ├─ 🔒 Очистка DNS кэша и истории                              │
│  └─ ⚙️ Отключение телеметрии (если -DisableTelemetry)          │
├────────────────────────────────────────────────────────────────┤
│  📊 ОТЧЁТ ПО МЕСТУ НА ДИСКЕ + ИТОГИ                            │
└────────────────────────────────────────────────────────────────┘
```

> Итог каждой фазы записывается в result JSON как **completed**, **skipped** или **failed**, чтобы автоматический прогон отличал «всё выполнено» от «фаза упала». См. **[docs/result-json.md](docs/result-json.md)**.

---

## 📝 Логирование

Каждый запуск пишет подробный лог в `%TEMP%\WinClean_<дата>.log` с временной меткой, статусом (успех / предупреждение / ошибка), освобождённым местом по категориям и общим временем. Для машиночитаемого итога используйте `-ResultJsonPath`.

---

## 📚 Подробнее

Углублённая документация - в **[`docs/`](docs/)**:

| Страница | Что внутри |
|:---------|:-----------|
| [Модель безопасности](docs/safety.md) | Точки восстановления, защищённые пути, fail-closed bootstrap, Controlled Folder Access |
| [Что очищается](docs/what-is-cleaned.md) | Полный список по фазам: очищается vs сохраняется |
| [Result JSON](docs/result-json.md) | Схема `-ResultJsonPath` для автоматизации и CI |
| [Устранение неполадок](docs/troubleshooting.md) | Частые проблемы и решения |
| [FAQ](docs/faq.md) | Расширенные вопросы и ответы |
| [Сравнение](docs/comparison.md) | Чем WinClean отличается от ручной очистки |
| [Процесс релиза](docs/release-process.md) | Как собираются и проверяются релизы |

---

## ❓ FAQ

<details>
<summary><b>Безопасно ли запускать WinClean?</b></summary>

Да. WinClean создаёт точку восстановления перед изменениями и никогда не трогает защищённые системные пути. Используйте `-ReportOnly` для предпросмотра. Подробнее: [docs/safety.md](docs/safety.md).

</details>

<details>
<summary><b>Удалит ли он мои программы или пакеты?</b></summary>

Нет. WinClean очищает только кэши и временные файлы. Установленные программы, пакеты npm/NuGet и пользовательские данные остаются нетронутыми.

</details>

<details>
<summary><b>Как часто нужно запускать?</b></summary>

Хороший вариант по умолчанию - раз в месяц. Активные разработчики или пользователи с ограниченным местом могут запускать еженедельно.

</details>

<details>
<summary><b>Можно ли запустить на Windows 10?</b></summary>

Скрипт разработан для Windows 11, но большинство функций работают на Windows 10 с PowerShell 7.1+.

</details>

Больше вопросов - в **[docs/faq.md](docs/faq.md)** и **[docs/troubleshooting.md](docs/troubleshooting.md)**.

---

## 🤝 Участие и сообщество

Мы приветствуем вклад в проект. См. **[CONTRIBUTING.md](CONTRIBUTING.md)** для процесса, стиля кода и тестирования, и открывайте **[Discussion](https://github.com/bivlked/WinClean/discussions)** для вопросов, идей или истории успеха.

1. Сделайте форк репозитория
2. Создайте ветку для вашей функции (`git checkout -b feature/AmazingFeature`)
3. Закоммитьте изменения (`git commit -m 'feat: add some amazing feature'`)
4. Отправьте ветку (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

---

## 📄 Лицензия

Этот проект лицензирован под MIT License - см. файл [LICENSE](LICENSE) для подробностей.

---

<div align="center">

### ⭐ Поставьте звезду, если проект оказался полезным!

**[Сообщить об ошибке](https://github.com/bivlked/WinClean/issues)** •
**[Предложить функцию](https://github.com/bivlked/WinClean/issues)** •
**[Обсуждения](https://github.com/bivlked/WinClean/discussions)** •
**[История изменений](CHANGELOG.md)**

Сделано с ❤️ для пользователей Windows

</div>
