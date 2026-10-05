# workbench

Личный верстак для работы с ИИ-агентами (Claude Code, Codex, Cursor) в любых проектах, из терминала и из любой IDE. Основа - FPF (First Principles Framework, [ailev/FPF](https://github.com/ailev/FPF)): агент опирается на его паттерны, а практика работы записана как зародыш собственного фреймворка локальной практики (LPF), и каждое её правило опирается на паттерн FPF.

Устроено как dotfiles: на машине лежит одна копия **твоей закрытой** базы знаний, и она подключается к проектам ссылкой `.workbench`, а git проекта её не видит. Между машинами база синхронизируется через своё удалённое хранилище. Этот публичный репозиторий - шаблон, установщик и команда `workbench`.

## Установка на машину

Один раз на машину, в любой папке:

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
```

Установщик спросит папку базы (по умолчанию `./my-workbench`) и адрес закрытого хранилища. То же без вопросов:

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --repo git@gitlab.com:you/my-workbench.git --dir ~/my-workbench
```

Что происходит:

1. Хранилище уже есть -> клонируется в папку базы. Хранилище пустое или его нет -> база создаётся из этого шаблона и отправляется туда: GitLab создаёт закрытый проект прямо при первой отправке, на GitHub сначала создай пустое закрытое хранилище.
2. Готовятся закреплённое издание FPF (`.fpf` в папке базы) и проверки git.
3. Ставится команда `workbench` (в `~/.local/bin`, другое место - `--bin-dir`).

Повторный запуск для той же папки обновляет базу. Все параметры: `curl -fsSL .../install.sh | sh -s -- --help`. Нужны `git`, `sh`, `jq`. Windows - в Git Bash (ставится вместе с Git for Windows) или в WSL; Linux и macOS - в обычном терминале.

### Windows: cmd и PowerShell

Обязательная зависимость - Git for Windows: весь код на sh и выполняется его `bin\sh.exe`. Установка - в Git Bash, а пользоваться командой и агентами можно из cmd, PowerShell и Git Bash:

- `bin\workbench.cmd` в папке базы вызывает ту же команду через `sh.exe` Git. Чтобы `workbench` работала из любой папки, добавь папку `bin` базы в PATH пользователя, один раз, в PowerShell:

  ```powershell
  $p = [Environment]::GetEnvironmentVariable('Path', 'User')
  [Environment]::SetEnvironmentVariable('Path', "$p;$HOME\my-workbench\bin", 'User')
  ```

  Новые окна cmd, PowerShell и Git Bash увидят команду. `jq` тоже должен быть в PATH (например, `winget install jqlang.jq`).
- Claude Code в Windows выполняет хуки через Git Bash, из какой бы оболочки его ни запустили, поэтому его хуки те же, что в Linux.
- Codex в Windows выполняет хуки через `cmd.exe`, а не через sh. Поэтому `attach` в Windows пишет каждому хуку Codex ещё и `commandWindows`: абсолютный путь к `bin\sh.exe` Git (берётся при `attach`) и абсолютный путь к проекту. Переехал Git или проект - повтори `workbench attach`. После `attach` хуки Codex надо одобрить заново.

## Подключение

Инструкции и память базы - один раз на машине, в любой папке:

```sh
workbench attach --user    # подключить ко всем проектам этой машины
workbench detach --user    # убрать; свой текст файлов остаётся
```

`attach --user` дописывает отмеченные блоки в пользовательские инструкции агентов:

- Claude Code - в `~/.claude/CLAUDE.md` (при заданном `CLAUDE_CONFIG_DIR` - в `CLAUDE.md` этой папки): пути к базе и FPF и импорты `AGENTS.md` и `memory/MEMORY.md` по абсолютным путям. Импорты из пользовательского файла Claude Code загружает без вопроса о внешних импортах, поэтому агент видит инструкции и память базы в любом проекте этой машины.
- Codex - в `~/.codex/AGENTS.md` (при заданном `CODEX_HOME` - в `AGENTS.md` этой папки): пути к базе и указание прочитать `AGENTS.md` и `memory/MEMORY.md` в начале сессии. Импортов у Codex нет, поэтому файлы агент читает сам.

Свой текст файлов сохраняется, ссылка на файл из dotfiles остаётся ссылкой. У Cursor пользовательские правила живут только в его настройках, поэтому ему указатель на базу даёт `attach` в проекте.

Хуки и скиллы базы - в папке проекта:

```sh
workbench attach    # подключить базу к проекту
workbench detach    # отключить; сама база остаётся
```

`attach` делает `.workbench` ссылкой на базу (в Windows - точкой соединения, junction) и подключает её к трём агентам локальными файлами:

| Агент | Что получает | Файлы в проекте |
|---|---|---|
| Claude Code | хуки, скиллы | `.claude/settings.local.json` (свои настройки дополняются, копия лежит рядом), ссылки в `.claude/skills/` |
| Codex | хуки, скиллы | `.codex/hooks.json` (так же дополняется), ссылки в `.agents/skills/` |
| Cursor | указатель на инструкции и память базы, хуки, скиллы | правило `.cursor/rules/workbench.mdc`; хуки и скиллы Cursor берёт из файлов Claude Code и из `.agents/skills/` |

Всё это прописывается в `.git/info/exclude` проекта, так что git проекта ничего не видит. Файл, который проект хранит в git (например, общий для команды `.codex/hooks.json`), `attach` не трогает и говорит об этом. `detach` убирает ровно то, что сделал `attach`, и возвращает проект в прежнее состояние. Пока инструкций и памяти базы нет на уровне пользователя, `attach` и начало сессии подсказывают `workbench attach --user`, а агент читает эти файлы сам.

Хуки написаны один раз: общее ядро (`scripts/hooks.sh` - что сказать агенту, `scripts/guard.sh` - какие команды не пускать) и тонкий переходник в протоколе хуков Claude Code (`adapters/claude/hooks/`). Codex понимает этот протокол как есть, Cursor переводит его сам. Среда запуска значения не имеет: терминал, VS Code, Cursor, IntelliJ IDEA - важен агент.

Первый запуск агента в подключённом проекте:

- Codex спрашивает, доверять ли проекту, и один раз просит одобрить хуки: команда `/hooks`. Без доверия проекту хуки из `.codex/` не загружаются. Изменилась команда хука (например, после `attach` в Windows) - одобрение нужно снова.
- Cursor выполняет хуки из файлов Claude Code, когда включена настройка "Include Third-Party Plugins, Skills, and Other Configs" (по умолчанию включена).

### Контейнер (devcontainer)

Контейнер видит только папку проекта, поэтому ссылка `.workbench` работает в нём, если смонтировать базу по тому же пути. `workbench attach` в проекте с контейнером подсказывает строку для `mounts` настроек контейнера:

```json
{"source": "/home/you/my-workbench", "target": "/home/you/my-workbench", "type": "bind"}
```

После пересборки контейнера база доступна в проекте так же, как снаружи. Если у агентов в контейнере своя папка настроек (например, `~/.claude` на отдельном томе), один раз выполни в контейнере `sh <папка базы>/bin/workbench attach --user`.

### Несколько машин

На каждой машине своя копия базы: тот же установщик с тем же `--repo`. Синхронизация - через удалённое хранилище: `git pull` и `git push` в папке базы.

## Раскладка

| Часть | Где |
|---|---|
| Инструкции для любых агентов | `AGENTS.md` (Claude Code импортирует его из пользовательского `~/.claude/CLAUDE.md`, Codex и Cursor читают по указателю) |
| Практика работы и её основания в FPF (семя LPF) | `lpf/README.md` |
| Слои знаний: личные LPF и DPF в базе, проектные - в `lpf/` и `dpf/` проекта (раздел 3 `AGENTS.md`) | `lpf/`, `dpf/` |
| Реестр РП, карточки, заметки, решения | `docs/WP-REGISTRY.md`, `inbox/`, `decisions/` |
| Личная память | `memory/` (видна агенту во всех проектах) |
| Скиллы в общем для агентов формате | `.agents/skills/` (`wp-new`, `stages` - этапы работы, `close-session`, `distill` - разбор источника по слоям) |
| Хуки: общее ядро и переходник в протоколе Claude Code (его понимает Codex, Cursor переводит сам) | `scripts/hooks.sh`, `scripts/guard.sh`, `adapters/claude/hooks/` |
| Проверки для любого агента и человека | `.githooks/`: маркеры компании и секреты при сохранении, запрет перезаписи истории |
| Установка, команда, подготовка и подключение | `install.sh`, `bin/workbench` (для cmd и PowerShell - `bin/workbench.cmd`), `scripts/setup.sh`, `scripts/attach.sh` |
| Тесты и проверка стиля | `tests/` (bats), `Makefile` |

## Работа

- `claude`, `codex` или Cursor в корне проекта. В начале сессии агент видит пути, издание FPF, состояние базы и активные РП.
- Любая задача сначала связывается с РП: принять, отложить, отклонить или вернуть (OPS.5 из FPF).
- "закрывай" -> карточка РП обновлена и сохранена в личной базе; в проекте ничего не сохраняется без команды.
- Личную базу можно открыть и отдельно, например для планирования: `claude` в папке базы.
- Сам workbench разрабатывается так же: `workbench attach` в рабочей копии шаблона. Агент работает по твоей личной базе, а шаблон для него - обычный код.

## Обновление и удаление

- Обновить базу: `git -C <папка базы> pull` или ещё раз запустить установщик.
- Подтянуть обновления шаблона: `git -C <папка базы> pull template main`.
- Удалить: `workbench detach` в каждом проекте и `workbench detach --user`, затем папку базы и команду `~/.local/bin/workbench`.

## Разработка

Код - только POSIX sh (`#!/bin/sh`). Изменения - через тесты: сначала падающий тест на [bats](https://github.com/bats-core/bats-core), потом код. Команды собраны в `Makefile`:

| Команда | Что делает |
|---|---|
| `make check` | проверка стиля, форматирования и все тесты; то же запускается на GitHub при каждом изменении |
| `make test` | тесты `tests/*.bats` |
| `make lint` | проверка стиля shellcheck, для скриптов - в режиме POSIX sh |
| `make format-check` | проверка форматирования shfmt, правила - в `.editorconfig` |
| `make format` | форматирует скрипты и тесты |

Тесты не трогают сеть, твои хранилища и твою домашнюю папку. Каждый файл тестов собирает песочницу во временной папке: закрытое хранилище заменяет локальное, FPF - маленькая локальная копия, шаблон - текущая рабочая копия вместе с несохранёнными правками, домашняя папка - своя. Проверяются установка базы на двух машинах, подключение и отключение к проекту и на уровне пользователя, команда `workbench`, издание FPF, перенос папок, база отдельно и в разработке шаблона, хуки так, как их запускают Claude Code, Codex и Cursor, защита от опасных команд и проверки перед сохранением. Нужны `bats`, `shellcheck` и `shfmt`. На GitHub тесты идут в Linux, macOS и Windows (Git Bash); в закрытых копиях шаблона прогон пропускается.

## Личные настройки

- Раздел "Личные правила владельца" в `AGENTS.md` шаблон не меняет.
- `adapters/claude/settings.overlay.json` (нет в шаблоне) добавляется к настройкам Claude Code в каждом проекте: например, выключить плагины или запретить инструменты.
- Маркеры компании - в `.git/info/company-markers` папки базы, по одному слову на строку: проверка перед сохранением не даст им попасть в личную базу.

## Ограничения

- Импорт файлов по ссылке есть только у Claude Code. Codex и Cursor получают указатель на `AGENTS.md` и читают его сами, а индекс памяти `memory/MEMORY.md` приходит им целиком в сообщении начала сессии: проверка показала, что сам Codex эти файлы не читает. Codex заменяет сообщение хука длиннее 10 000 байт обрезанным с путём к полному тексту, поэтому индекс памяти стоит держать коротким.
- Cursor в IDE по документации не передаёт агенту контекст из хука на сообщение, поэтому напоминание о допуске РП туда может не дойти (правило допуска всё равно есть в `AGENTS.md`). Причину отказа защиты Cursor показывает человеку, а не агенту.
- Скиллы базы Cursor находит и в `.claude/skills`, и в `.agents/skills`.
- Kimi и другие агенты читают `AGENTS.md`, но их переходники не сделаны.
- Windows - только с Git for Windows: весь код на sh, а `workbench.cmd` и хуки Codex вызывают его `sh.exe`. Сторож разбирает команду по правилам sh. В Windows Codex выполняет команды в PowerShell: `git add -A` и `cd` сторож там ловит, а `Set-Location` и `Remove-Item -Recurse -Force` не узнаёт (удаление отклоняет защита самого Codex).
- В WSL с git ниже 2.48 ссылка рабочей копии `.fpf` делается относительной вручную (как у подмодулей), `setup.sh` делает это сам.

## English

**workbench** is a personal, dotfiles-style workbench for working with AI coding agents (Claude Code, Codex, Cursor) in any project, from a terminal or any IDE. It builds on the [First Principles Framework (FPF)](https://github.com/ailev/FPF): the agent relies on FPF patterns, and the owner's way of working is kept as a seed of a Local Practice Framework (LPF). Each machine keeps one clone of the owner's **private** knowledge-base repository. `workbench attach --user` adds marked blocks to the user-level instructions: `~/.claude/CLAUDE.md` imports the base's instructions and memory into every Claude Code project (user-level imports load without the external-import prompt), and `~/.codex/AGENTS.md` points Codex to the same files, since Codex has no imports. `workbench attach` links the base into a project as `.workbench`, invisible to the project's git, and adds its hooks and skills for all three agents: `.claude/settings.local.json` (Cursor runs these hooks too), `.codex/hooks.json`, a Cursor rule and skill links; `workbench detach` removes them. The hooks are written once: a shared core in `scripts/` and a thin adapter in Claude Code's hook protocol, which Codex speaks as is and Cursor translates. Machines sync through the private repository.

Install once per machine (Linux, macOS; Windows in Git Bash or WSL):

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --repo git@gitlab.com:you/my-workbench.git --dir ~/my-workbench
```

An empty or missing private repository is created from this template (GitLab creates a private project on first push; on GitHub create an empty private repository first). A devcontainer sees the base when it is mounted at the same path; `workbench attach` prints the mount line. The content (agent instructions, practice, skills) is in Russian; other agents read `AGENTS.md`. The code is POSIX sh; `make check` runs the offline bats tests, shellcheck and shfmt.

## Лицензия

MIT, см. `LICENSE`. Сторонние материалы и их лицензии - в `THIRD-PARTY.md`. FPF в шаблон не входит: он скачивается при установке и распространяется по CC BY 4.0.
