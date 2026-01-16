<div align="center">

<img src="https://raw.githubusercontent.com/bivlked/WinClean/main/assets/logo.svg" alt="WinClean Logo" width="120" height="120">

# WinClean

### Комплексный скрипт обслуживания Windows 11

[![Версия](https://img.shields.io/badge/версия-2.9-blue.svg)](https://github.com/bivlked/WinClean/releases)
[![PowerShell 7.1+](https://img.shields.io/badge/PowerShell-7.1%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![Лицензия: MIT](https://img.shields.io/badge/Лицензия-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/bivlked/WinClean/pulls)

**Автоматическое обслуживание системы: обновления, очистка и оптимизация в одном скрипте**

[English](README.md) | [Русский](README_RU.md)

---

[Зачем WinClean?](#-зачем-winclean) •
[Возможности](#-возможности) •
[Быстрый старт](#-быстрый-старт) •
[Параметры](#-параметры) •
[Безопасность](#%EF%B8%8F-безопасность) •
[FAQ](#-faq)

</div>

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
- **Безопасно** — защищённые пути

</td>
</tr>
</table>

> 💡 **Средний результат очистки:** 5-20 ГБ освобождено, в зависимости от использования системы

---

## ✨ Возможности

<table>
<tr>
<td width="33%" valign="top">

### 🔄 Обновления
- Windows Update (+ драйверы)
- Приложения Microsoft Store
- Пакеты winget
- Модуль PSWindowsUpdate

</td>
<td width="33%" valign="top">

### 🗑️ Очистка
- Временные файлы (3 места)
- Кэши браузеров (6 браузеров)
- Кэши Windows (8 типов)
- Очистка корзины
- Удаление Windows.old

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

---

## 🚀 Быстрый старт

### ⚡ Установка и запуск одной командой

```powershell
irm https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1 -OutFile "$env:TEMP\WinClean.ps1"; Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$env:TEMP\WinClean.ps1`""
```

<details>
<summary>📥 Альтернативные способы установки</summary>

### Ручная загрузка

```powershell
# Скачать
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bivlked/WinClean/main/WinClean.ps1" -OutFile "WinClean.ps1"

# Запустить от имени администратора
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

## 📋 Параметры

| Параметр | Описание | По умолчанию |
|:---------|:---------|:------------:|
| `-SkipUpdates` | Пропустить обновления Windows и winget | `false` |
| `-SkipCleanup` | Пропустить все операции очистки | `false` |
| `-SkipRestore` | Пропустить создание точки восстановления | `false` |
| `-SkipDevCleanup` | Пропустить кэши разработчика (npm, pip и т.д.) | `false` |
| `-SkipDockerCleanup` | Пропустить очистку Docker/WSL | `false` |
| `-SkipVSCleanup` | Пропустить очистку Visual Studio | `false` |
| `-DisableTelemetry` | Отключить телеметрию Windows через групповую политику | `false` |
| `-ReportOnly` | **Тестовый режим** — показать, что будет сделано | `false` |
| `-LogPath` | Путь к файлу лога | Авто |

---

## 💡 Примеры использования

<table>
<tr>
<td width="50%">

### Полное обслуживание
```powershell
.\WinClean.ps1
```
Все обновления + вся очистка

</td>
<td width="50%">

### Только очистка
```powershell
.\WinClean.ps1 -SkipUpdates
```
Без обновлений, только очистка

</td>
</tr>
<tr>
<td width="50%">

### Режим предпросмотра
```powershell
.\WinClean.ps1 -ReportOnly
```
Посмотреть, что будет сделано

</td>
<td width="50%">

### Быстрая очистка
```powershell
.\WinClean.ps1 -SkipUpdates -SkipDockerCleanup
```
Только быстрая очистка

</td>
</tr>
</table>

---

## 🔧 Требования

| Требование | Версия | Примечания |
|:-----------|:-------|:-----------|
| **Windows** | 11 | Протестировано на 23H2/24H2/25H2 |
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

### ✅ Что делает WinClean

| Функция безопасности | Описание |
|:---------------------|:---------|
| 🔄 **Точка восстановления** | Создаётся перед любыми изменениями |
| 🛡️ **Защищённые пути** | Системные папки никогда не затрагиваются |
| 📦 **Сохранение пакетов** | NuGet, npm, Maven пакеты сохраняются |
| ❓ **Подтверждение** | Windows.old запрашивает подтверждение |
| 🔧 **Восстановление служб** | Использует try/finally для служб |
| 👁️ **Режим предпросмотра** | `-ReportOnly` показывает изменения заранее |

### 🚫 Защищённые пути (никогда не удаляются)

```
C:\Windows\
C:\Program Files\
C:\Program Files (x86)\
C:\Users\
C:\Users\ВашеИмя\
```

### ✅ Безопасно очищается vs 🛡️ Сохраняется

| ✅ Очищается | 🛡️ Сохраняется |
|:-------------|:---------------|
| `%TEMP%\*` | `Документы`, `Загрузки` |
| Кэши браузеров | Закладки, пароли браузеров |
| `npm-cache` | `node_modules` |
| `pip\Cache` | Виртуальные окружения |
| `Composer\cache` | `vendor` |
| `NuGet\v3-cache` | `\.nuget\packages` |
| `\.gradle\build-cache` | `\.gradle\caches\modules` |

---

## 📊 Порядок выполнения

```
┌────────────────────────────────────────────────────────────────┐
│                     WinClean v2.9                              │
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
│  ├─ 💾 Очистка диска (20+ категорий)                           │
│  └─ 📁 Удаление Windows.old (с подтверждением)                 │
├────────────────────────────────────────────────────────────────┤
│  ПРИВАТНОСТЬ (опционально)                                     │
│  ├─ 🔒 Очистка DNS кэша и истории                              │
│  └─ ⚙️ Отключение телеметрии (если -DisableTelemetry)          │
├────────────────────────────────────────────────────────────────┤
│  📊 ИТОГОВЫЙ ОТЧЁТ                                             │
└────────────────────────────────────────────────────────────────┘
```

---

## 📝 Логирование

Каждый запуск создаёт подробный лог:

```
%TEMP%\WinClean_20250115_143052.log
```

**Содержимое лога:**
- ⏰ Временная метка каждой операции
- ✅ Успех / ⚠️ Предупреждение / ❌ Ошибка
- 📊 Освобождённое место по категориям
- ⏱️ Общее время выполнения

---

## ❓ FAQ

<details>
<summary><b>Безопасно ли запускать WinClean?</b></summary>

Да! WinClean создаёт точку восстановления перед изменениями и никогда не трогает защищённые системные пути. Используйте `-ReportOnly` для предварительного просмотра изменений.

</details>

<details>
<summary><b>Удалит ли он мои установленные программы?</b></summary>

Нет. WinClean очищает только кэши и временные файлы. Ваши установленные программы, npm-пакеты, NuGet-пакеты и пользовательские данные остаются нетронутыми.

</details>

<details>
<summary><b>Как часто нужно запускать?</b></summary>

Рекомендуется раз в месяц. Активные разработчики или пользователи с ограниченным дисковым пространством могут запускать еженедельно.

</details>

<details>
<summary><b>Зачем нужны права администратора?</b></summary>

Требуются для: Windows Update, очистки системного кэша, операций DISM, управления службами и создания точек восстановления.

</details>

<details>
<summary><b>Можно ли запустить на Windows 10?</b></summary>

Скрипт разработан для Windows 11, но большинство функций работают на Windows 10 с PowerShell 7.1+.

</details>

<details>
<summary><b>Что делать, если что-то пошло не так?</b></summary>

Используйте точку восстановления, созданную в начале работы, для отката. Проверьте лог-файл для получения информации о выполненных изменениях.

</details>

---

## 🤝 Участие в разработке

Мы приветствуем вклад в проект! Не стесняйтесь создавать Pull Request.

1. Сделайте форк репозитория
2. Создайте ветку для вашей функции (`git checkout -b feature/AmazingFeature`)
3. Закоммитьте изменения (`git commit -m 'Add some AmazingFeature'`)
4. Отправьте ветку (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

---

## 📄 Лицензия

Этот проект лицензирован под MIT License — см. файл [LICENSE](LICENSE) для подробностей.

---

<div align="center">

### ⭐ Поставьте звезду, если проект оказался полезным!

**[Сообщить об ошибке](https://github.com/bivlked/WinClean/issues)** •
**[Предложить функцию](https://github.com/bivlked/WinClean/issues)** •
**[История изменений](CHANGELOG.md)**

Сделано с ❤️ для пользователей Windows

</div>
