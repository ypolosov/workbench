# workbench

Личный верстак для работы с ИИ-агентами (Claude Code, Codex, Cursor) в любых проектах, из терминала и из любой IDE. Основа - FPF (First Principles Framework, [ailev/FPF](https://github.com/ailev/FPF)): агент опирается на его паттерны, а практика работы записана как зародыш собственного фреймворка локальной практики (LPF), и каждое её правило опирается на паттерн FPF.

Устроено как dotfiles: на машине лежит одна копия **твоей закрытой** базы знаний, и она подключается к проектам ссылкой `.workbench`, а git проекта её не видит. Между машинами база синхронизируется через своё удалённое хранилище. Этот публичный репозиторий - шаблон, установщик и команда `workbench`.

## Установка на машину

В Linux, macOS, Bash и Zsh, из любой папки:

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
```

В Windows, из PowerShell или cmd, без заранее установленного Git:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/ypolosov/workbench/main/install.ps1'))"
```

В Git Bash работает и первая команда. Мастер использует [Gum](https://github.com/charmbracelet/gum): стрелки выбирают вариант, Enter продолжает, Esc или Ctrl+C отменяет. Node.js, Python и Go для мастера не нужны.

**Личная папка workbench** - ваши файлы памяти, рабочих продуктов, решений и скиллов, а не дополнительный сервер или отдельная база данных. Установщик сначала ищет уже подключённый workbench. Если его нет, мастер предлагает создать workbench впервые или скачать свой из частного Git-хранилища. Папку можно выбрать; начальный вариант - `~/my-workbench`. Регистрация в облаке для первого запуска не требуется.

Установщик подготавливает Git, jq и интерфейс мастера; загружаемые бинарники проверяются по закреплённым SHA-256. В Windows используется существующий Git for Windows или его переносимая копия в пользовательской папке. В Linux для отсутствующего Git используется системный менеджер пакетов; macOS может запросить подтверждение установки системных компонентов в своём диалоге.

После подтверждения настроек установщик готовит закреплённое издание FPF и проверки git, подключает инструкции агентов, предлагает подключить текущий проект и одобрить четыре хука workbench в Codex. Команда `workbench` становится доступна автоматически: Windows получает пользовательский PATH, Bash и Zsh - отмеченный блок в файлах запуска. Свои записи сохраняются. В конце открывается подготовленная оболочка; ручная правка PATH и перезапуск терминала не нужны.

Сразу выполняется диагностика; отчёт остаётся в `.runtime/doctor.json`. Повторить её вручную:

```sh
workbench doctor
workbench doctor --project /path/to/project
workbench doctor --json
workbench location
```

Диагностика проверяет зависимости, издание FPF, инструкции, подключение проекта, ответы хуков и, если Codex установлен, его подтверждение активности и доверия хукам. Она не делает запросов к модели и не подтверждает доступность аккаунта. Проверка реальных сессий агентов описана ниже.

Повторный запуск использует существующую личную папку. Обновляются файлы программы (`bin`, `scripts`, `adapters`, `.githooks`); память, рабочие продукты, решения, практика и свои скиллы сохраняются. Местные правки программы объединяются с обновлением, прежние версии остаются в `.runtime/backups`. Конфликт останавливает обновление до замены программных файлов. Изменения не сохраняются и не отправляются в Git автоматически.

Для управляемой установки без вопросов:

```sh
sh install.sh --local --yes --dir ~/my-workbench --project /path/to/project --no-launch
sh install.sh --repo git@gitlab.com:you/my-workbench.git --yes --no-launch
```

Первый вариант создаёт workbench впервые, второй подключает свою существующую копию из Git. `--no-launch` завершает установщик после диагностики; новый терминал получает подготовленную среду. `--core-only` готовит только папку и команду для управляемых окружений, без мастера и настройки пользовательской среды. Все параметры: `sh install.sh --help`; у Windows-загрузчика им соответствуют `-Local`, `-Yes`, `-Dir`, `-Repo`, `-Project`, `-NoLaunch`, `-CoreOnly`.

Поддерживаемые платформы: Windows с Git for Windows, Linux и macOS, x64 и ARM64. Gum в Windows ARM64 использует системное выполнение x64-программ. В Windows Claude Code выполняет хуки через Git Bash, а Codex - через cmd и запускатель `workbench.cmd`; путь с пробелами обрабатывается внутри запускателя.

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

- При ручном подключении Codex спрашивает, доверять ли проекту, и один раз просит одобрить хуки: команда `/hooks`. Мастер установки делает это через API самого Codex после вашего подтверждения. Без доверия проекту хуки из `.codex/` не загружаются. Изменилась команда хука (например, после `attach` в Windows) - одобрение нужно снова.
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

- Обновить базу: `git -C <папка базы> pull`, затем `workbench setup` (или ещё раз запустить установщик).
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
