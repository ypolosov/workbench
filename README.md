# workbench

Личный верстак для работы с ИИ-агентами в любых проектах. Основа — FPF (First Principles Framework, [ailev/FPF](https://github.com/ailev/FPF)): агент опирается на его паттерны, а практика работы записана как зародыш собственного фреймворка локальной практики (LPF). Часть практики взята из шаблона IWE ([TserenTserenov/FMT-exocortex-template](https://github.com/TserenTserenov/FMT-exocortex-template), MIT): ВДВ, учёт рабочих продуктов (РП), напоминания и защита от опасных команд.

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

1. Хранилище уже есть → клонируется в папку базы. Хранилище пустое или его нет → база создаётся из этого шаблона и отправляется туда: GitLab создаёт закрытый проект прямо при первой отправке, на GitHub сначала создай пустое закрытое хранилище.
2. Готовятся закреплённое издание FPF (`.fpf` в папке базы) и проверки git.
3. Ставится команда `workbench` (в `~/.local/bin`, другое место - `--bin-dir`).

Повторный запуск для той же папки обновляет базу. Все параметры: `curl -fsSL .../install.sh | sh -s -- --help`. Нужны `git`, `sh`, `jq`. Windows - в Git Bash (ставится вместе с Git for Windows) или в WSL; Linux и macOS - в обычном терминале.

## Подключение

Инструкции и память базы - один раз на машине, в любой папке:

```sh
workbench attach --user    # подключить ко всем проектам Claude Code на этой машине
workbench detach --user    # убрать; свой текст файла остаётся
```

`attach --user` дописывает в пользовательский `~/.claude/CLAUDE.md` (при заданном `CLAUDE_CONFIG_DIR` - в `CLAUDE.md` этой папки) отмеченный блок: пути к базе и FPF и импорты `AGENTS.md` и `memory/MEMORY.md` по абсолютным путям. Свой текст файла сохраняется, ссылка на файл из dotfiles остаётся ссылкой. Импорты из пользовательского файла Claude Code загружает без вопроса о внешних импортах, поэтому агент видит инструкции и память базы в любом проекте этой машины, подключённом к базе или нет.

Хуки и скиллы базы - в папке проекта:

```sh
workbench attach    # подключить базу к проекту
workbench detach    # отключить; сама база остаётся
```

`attach` делает `.workbench` ссылкой на базу (в Windows - точкой соединения, junction) и подключает её хуки и скиллы к Claude Code локальными файлами: хуки в `.claude/settings.local.json` (свои настройки дополняются, копия лежит рядом), ссылки на скиллы в `.claude/skills/`. Всё это прописывается в `.git/info/exclude` проекта, так что git проекта ничего не видит. `detach` убирает ровно это и возвращает проект в прежнее состояние. Пока инструкций и памяти базы нет на уровне пользователя, `attach` и начало сессии подсказывают `workbench attach --user`, а агент читает эти файлы сам.

### Контейнер (devcontainer)

Контейнер видит только папку проекта, поэтому ссылка `.workbench` работает в нём, если смонтировать базу по тому же пути. `workbench attach` в проекте с контейнером подсказывает строку для `mounts` настроек контейнера:

```json
{"source": "/home/you/my-workbench", "target": "/home/you/my-workbench", "type": "bind"}
```

После пересборки контейнера база доступна в проекте так же, как снаружи. Если у Claude Code в контейнере своя папка настроек (например, `~/.claude` на отдельном томе), один раз выполни в контейнере `sh <папка базы>/bin/workbench attach --user`.

### Несколько машин

На каждой машине своя копия базы: тот же установщик с тем же `--repo`. Синхронизация - через удалённое хранилище: `git pull` и `git push` в папке базы.

## Раскладка

| Часть | Где |
|---|---|
| Инструкции для любых агентов | `AGENTS.md` (Claude Code получает его через пользовательский `~/.claude/CLAUDE.md`) |
| Практика работы и её основания в FPF | `lpf/README.md` |
| Реестр РП, карточки, заметки, решения | `docs/WP-REGISTRY.md`, `inbox/`, `decisions/` |
| Личная память | `memory/` (видна агенту во всех проектах) |
| Скиллы в общем для агентов формате | `.agents/skills/` (`vdv`, `wp-new`, `close-session`) |
| Переходник для Claude Code | `adapters/claude/hooks/` |
| Проверки для любого агента и человека | `.githooks/`: маркеры компании и секреты при сохранении, запрет перезаписи истории |
| Установка, команда, подготовка и подключение | `install.sh`, `bin/workbench`, `scripts/setup.sh`, `scripts/attach.sh` |
| Тесты и проверка стиля | `tests/` (bats), `Makefile` |

## Работа

- `claude` в корне проекта. В начале сессии агент видит пути, издание FPF, состояние базы и активные РП.
- Любая задача сначала связывается с РП: принять, отложить, отклонить или вернуть (OPS.5 из FPF).
- «закрывай» → карточка РП обновлена и сохранена в личной базе; в проекте ничего не сохраняется без команды.
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

Тесты не трогают сеть, твои хранилища и твою домашнюю папку. Каждый файл тестов собирает песочницу во временной папке: закрытое хранилище заменяет локальное, FPF - маленькая локальная копия, шаблон - текущая рабочая копия вместе с несохранёнными правками, домашняя папка - своя. Проверяются установка базы на двух машинах, подключение и отключение к проекту и на уровне пользователя, команда `workbench`, издание FPF, перенос папок, база отдельно и в разработке шаблона, хуки Claude Code, защита от опасных команд и проверки перед сохранением. Нужны `bats`, `shellcheck` и `shfmt`. На GitHub тесты идут в Linux, macOS и Windows (Git Bash); в закрытых копиях шаблона прогон пропускается.

## Личные настройки

- Раздел «Личные правила владельца» в `AGENTS.md` шаблон не меняет.
- `adapters/claude/settings.overlay.json` (нет в шаблоне) добавляется к настройкам Claude Code в каждом проекте: например, выключить плагины или запретить инструменты.
- Маркеры компании - в `.git/info/company-markers` папки базы, по одному слову на строку: проверка перед сохранением не даст им попасть в личную базу.

## Ограничения

- Переходник есть только для Claude Code. Codex, Cursor и Kimi читают `AGENTS.md`, но их переходники ещё не сделаны.
- Windows - только через Git Bash или WSL: весь код на sh.
- В WSL с git ниже 2.48 ссылка рабочей копии `.fpf` делается относительной вручную (как у подмодулей), `setup.sh` делает это сам.

## English

**workbench** is a personal, dotfiles-style workbench for working with AI coding agents in any project. It builds on the [First Principles Framework (FPF)](https://github.com/ailev/FPF): the agent relies on FPF patterns, and the owner's way of working is kept as a seed of a Local Practice Framework (LPF). Each machine keeps one clone of the owner's **private** knowledge-base repository; `workbench attach --user` imports its instructions and memory into every Claude Code project through a marked block in the user-level `~/.claude/CLAUDE.md`, whose imports Claude Code loads without the external-import prompt. `workbench attach` links the base into a project as `.workbench`, invisible to the project's git, and adds its hooks and skills; `workbench detach` removes them. Machines sync through the private repository.

Install once per machine (Linux, macOS; Windows in Git Bash or WSL):

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --repo git@gitlab.com:you/my-workbench.git --dir ~/my-workbench
```

An empty or missing private repository is created from this template (GitLab creates a private project on first push; on GitHub create an empty private repository first). A devcontainer sees the base when it is mounted at the same path; `workbench attach` prints the mount line. The content (agent instructions, practice, skills) is in Russian; a Claude Code adapter is included, other agents read `AGENTS.md`. The code is POSIX sh; `make check` runs the offline bats tests, shellcheck and shfmt.

## Лицензия

MIT, см. `LICENSE`. Сторонние материалы и их лицензии - в `THIRD-PARTY.md`. FPF в шаблон не входит: он скачивается при установке и распространяется по CC BY 4.0.
