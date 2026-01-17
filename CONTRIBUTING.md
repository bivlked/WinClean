# Contributing to WinClean

Thank you for your interest in contributing to WinClean! This document provides guidelines and instructions for contributing.

[English](#english) | [Русский](#русский)

---

## English

### How Can I Contribute?

#### Reporting Bugs

Before creating bug reports, please check the [existing issues](https://github.com/bivlked/WinClean/issues) to avoid duplicates.

When creating a bug report, please include:

- **Clear title** describing the issue
- **Steps to reproduce** the behavior
- **Expected behavior** vs **actual behavior**
- **Screenshots** if applicable
- **System information:**
  - Windows version (e.g., Windows 11 23H2)
  - PowerShell version (`$PSVersionTable.PSVersion`)
  - WinClean version

#### Suggesting Features

Feature requests are welcome! Please:

1. Check if the feature was already requested
2. Describe the feature and its use case
3. Explain why this would be useful to most users

#### Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b feature/AmazingFeature`)
3. **Make your changes**
4. **Test thoroughly** on Windows 11 with PowerShell 7.1+
5. **Commit** with clear messages (`git commit -m 'Add some AmazingFeature'`)
6. **Push** to your branch (`git push origin feature/AmazingFeature`)
7. **Open a Pull Request**

### Code Style Guidelines

#### PowerShell Best Practices

- Use **approved verbs** for function names (Get-, Set-, Remove-, Clear-, etc.)
- Use **PascalCase** for function names and parameters
- Use **camelCase** for local variables
- Add **comment-based help** for public functions
- Use **Write-Log** for logging, not Write-Host directly
- Always handle errors with **try/catch** blocks

#### Code Structure

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description of function.
    .DESCRIPTION
        Detailed description.
    .PARAMETER ParamName
        Parameter description.
    .EXAMPLE
        Example usage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParamName
    )

    try {
        # Implementation
    }
    catch {
        Write-Log "Error: $_" -Level Error
    }
}
```

#### Safety Rules

- **Never** delete protected system paths
- **Always** check if paths exist before operations
- **Always** use `-WhatIf` support where applicable
- **Never** store credentials or sensitive data
- **Always** create restore points before system changes

### Testing

WinClean uses **Pester** for automated testing. Before submitting a PR:

#### Run Pester Tests

```powershell
# Install Pester (if not installed)
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0

# Run all tests
Invoke-Pester ./tests -Output Detailed

# Run specific test file
Invoke-Pester ./tests/Helpers.Tests.ps1
Invoke-Pester ./tests/Fixes.Tests.ps1
```

#### Test Structure

- `tests/Helpers.Tests.ps1` — Unit tests for helper functions (safe, no system changes)
- `tests/Fixes.Tests.ps1` — Validation tests for bug fixes (code inspection)

#### Manual Testing

1. Run with `-ReportOnly` to verify no unintended changes
2. Test on a clean Windows 11 installation if possible
3. Test with various skip flags (`-SkipUpdates`, `-SkipCleanup`, etc.)
4. Verify logging works correctly

#### CI/CD

All PRs automatically run:
- PSScriptAnalyzer (linting)
- Syntax check
- Pester tests (94 tests)

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation changes
- `refactor:` code refactoring
- `perf:` performance improvements
- `test:` adding tests
- `chore:` maintenance tasks

---

## Русский

### Как я могу помочь?

#### Сообщения об ошибках

Перед созданием отчёта об ошибке проверьте [существующие issues](https://github.com/bivlked/WinClean/issues).

При создании отчёта укажите:

- **Понятный заголовок** с описанием проблемы
- **Шаги для воспроизведения**
- **Ожидаемое поведение** vs **фактическое поведение**
- **Скриншоты** при необходимости
- **Информация о системе:**
  - Версия Windows (например, Windows 11 23H2)
  - Версия PowerShell (`$PSVersionTable.PSVersion`)
  - Версия WinClean

#### Предложение функций

Предложения приветствуются! Пожалуйста:

1. Проверьте, не было ли уже такого предложения
2. Опишите функцию и сценарий использования
3. Объясните, почему это будет полезно большинству пользователей

#### Pull Requests

1. **Сделайте форк** репозитория
2. **Создайте ветку** от `main` (`git checkout -b feature/AmazingFeature`)
3. **Внесите изменения**
4. **Тщательно протестируйте** на Windows 11 с PowerShell 7.1+
5. **Закоммитьте** с понятным сообщением (`git commit -m 'Add some AmazingFeature'`)
6. **Отправьте** ветку (`git push origin feature/AmazingFeature`)
7. **Откройте Pull Request**

### Правила кода

#### Лучшие практики PowerShell

- Используйте **одобренные глаголы** для имён функций (Get-, Set-, Remove-, Clear-, и т.д.)
- Используйте **PascalCase** для имён функций и параметров
- Используйте **camelCase** для локальных переменных
- Добавляйте **справку на основе комментариев** для публичных функций
- Используйте **Write-Log** для логирования
- Всегда обрабатывайте ошибки блоками **try/catch**

#### Правила безопасности

- **Никогда** не удаляйте защищённые системные пути
- **Всегда** проверяйте существование путей перед операциями
- **Никогда** не храните учётные данные
- **Всегда** создавайте точки восстановления перед системными изменениями

### Тестирование

WinClean использует **Pester** для автоматического тестирования. Перед отправкой PR:

#### Запуск Pester тестов

```powershell
# Установить Pester (если не установлен)
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0

# Запустить все тесты
Invoke-Pester ./tests -Output Detailed

# Запустить конкретный файл тестов
Invoke-Pester ./tests/Helpers.Tests.ps1
Invoke-Pester ./tests/Fixes.Tests.ps1
```

#### Структура тестов

- `tests/Helpers.Tests.ps1` — Unit-тесты вспомогательных функций (безопасные, без изменений системы)
- `tests/Fixes.Tests.ps1` — Валидационные тесты исправлений (проверка кода)

#### Ручное тестирование

1. Запустите с `-ReportOnly` для проверки
2. Протестируйте на чистой установке Windows 11
3. Проверьте с различными флагами пропуска
4. Убедитесь, что логирование работает корректно

#### CI/CD

Все PR автоматически проходят:
- PSScriptAnalyzer (линтинг)
- Проверка синтаксиса
- Pester тесты (94 теста)

---

## Questions?

Feel free to open an issue or start a discussion!

*Thank you for contributing!*
