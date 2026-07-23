# Support

WinClean runs elevated and performs system maintenance, so a good report is worth more
here than in most projects: it is often the only way to tell "WinClean did not clean X"
from "there was nothing left of X to clean".

## Start here

| Question | Where to look |
|:---------|:--------------|
| Something failed, or a step did nothing | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Is this safe? What exactly gets deleted? | [docs/safety.md](docs/safety.md), [docs/what-is-cleaned.md](docs/what-is-cleaned.md) |
| General questions (Windows 10, how often to run it, rollback) | [docs/faq.md](docs/faq.md) |
| What the run summary fields mean | [docs/result-json.md](docs/result-json.md) |

## Where to go next

**A reproducible defect** - open a [bug report](https://github.com/bivlked/WinClean/issues/new?template=bug_report.md).
Something behaved differently from what the documentation says, and you can describe the
steps that produced it.

**A question, an idea, or a story about how you use it** -
open a [Discussion](https://github.com/bivlked/WinClean/discussions). Questions like "why
does winget keep offering the same package" or "which profile should I use" are answered
there, and feature ideas are easier to shape in a conversation than in an issue.

**A security vulnerability** - do **not** open a public issue. Use private reporting as
described in [SECURITY.md](SECURITY.md).

## What to include

Most of this comes straight from the run, and it is what turns "it did not work" into
something that can actually be diagnosed:

- **WinClean version** - the banner prints it, and it is also `Version` in the result JSON
- **How you installed it** - `get.ps1` one-liner, `install.ps1` + shortcut, PowerShell
  Gallery, or a manual download
- **Windows version** - `winver`, e.g. Windows 11 24H2 (build 26100)
- **PowerShell version** - `$PSVersionTable.PSVersion`
- **Whether the shell was elevated**, and whether you passed `-ReportOnly`
- **The log** from `%TEMP%\WinClean_<date>.log` - the relevant part is enough; it contains
  file paths from your machine, so read it before pasting
- **The result JSON**, if you ran with `-ResultJsonPath`. This is the single most useful
  artefact: it records which phases ran, which were skipped, which failed, and the
  warning and error counts

If a cleanup step freed less than you expected, `-ReportOnly` output from the same machine
is very helpful too: it shows what WinClean believed was there to clean.

## What is not supported

- Windows versions before 10, and PowerShell 5.1 (WinClean requires PowerShell 7.1+)
- Running without administrator rights - most maintenance operations simply cannot work
- Modified copies. If you changed `WinClean.ps1`, please reproduce the problem with an
  unmodified release first, so it is clear whose behaviour is being discussed.

## Response times

This is a personal open-source project maintained in spare time. Issues and discussions
are read, but there is no service level attached to them. Security reports are looked at
first.
