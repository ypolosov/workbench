# workbench

Личный верстак для работы с ИИ-агентами в любых проектах. Основа — FPF (First Principles Framework, [ailev/FPF](https://github.com/ailev/FPF)): агент опирается на его паттерны, а практика работы записана как зародыш собственного фреймворка локальной практики (LPF). Часть практики взята из шаблона IWE ([TserenTserenov/FMT-exocortex-template](https://github.com/TserenTserenov/FMT-exocortex-template), MIT): ВДВ, учёт рабочих продуктов (РП), напоминания и защита от опасных команд.

Устроено как dotfiles: в каждом проекте лежит клон **твоей закрытой** базы знаний в папке `.workbench`, а git проекта её не видит. Этот публичный репозиторий - шаблон и установщик.

## Установка

В корне своего проекта (это должен быть git-проект):

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
```

Установщик спросит адрес закрытого хранилища для личной базы. Можно указать его сразу:

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --repo git@gitlab.com:you/my-workbench.git
# или из пространства и имени (по умолчанию имя my-workbench):
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --base git@gitlab.com:you --name my-workbench
```

Что происходит:

1. Хранилище уже есть и не пустое → клонируется в `.workbench`.
2. Хранилище пустое или его нет → создаётся из этого шаблона и отправляется туда. GitLab создаёт закрытый проект прямо при первой отправке; на GitHub сначала создай пустое закрытое хранилище.
3. Готовится закреплённое издание FPF (`.workbench/.fpf`, издание - в `.fpf-edition`).
4. workbench подключается к проекту только локальными файлами, прописанными в `.git/info/exclude` проекта: `CLAUDE.local.md`, `.claude/settings.local.json`, ссылки на скиллы в `.claude/skills/`. Существующие локальные настройки дополняются, копия сохраняется. Если у проекта уже есть свой `CLAUDE.local.md`, workbench дописывает в его конец отмеченный блок и при отключении убирает его.

Все параметры: `curl -fsSL .../install.sh | sh -s -- --help`. Нужны `git`, `sh`, `jq`; для переходника - [Claude Code](https://claude.com/claude-code).

## Раскладка

```text
<проект>/                  проект не меняется; .workbench исключён в его .git/info/exclude
  .workbench/              клон личной базы (в VS Code виден как отдельное хранилище)
    .fpf/                  закреплённое издание FPF: рабочая копия git, в .gitignore
```

| Часть | Где |
|---|---|
| Инструкции для любых агентов | `AGENTS.md` (Claude Code получает его через локальный `CLAUDE.local.md`) |
| Практика работы и её основания в FPF | `lpf/README.md` |
| Реестр РП, карточки, заметки, решения | `docs/WP-REGISTRY.md`, `inbox/`, `decisions/` |
| Личная память | `memory/` (видна агенту во всех проектах) |
| Скиллы в общем для агентов формате | `.agents/skills/` (`vdv`, `wp-new`, `close-session`) |
| Переходник для Claude Code | `adapters/claude/hooks/` |
| Проверки для любого агента и человека | `.githooks/`: маркеры компании и секреты при сохранении, запрет перезаписи истории |
| Подготовка и подключение | `scripts/setup.sh`, `scripts/attach.sh` |
| Тесты и проверка стиля | `tests/` (bats), `Makefile` |

## Работа

- `claude` в корне проекта. В начале сессии агент видит пути, издание FPF, состояние клона и активные РП.
- Любая задача сначала связывается с РП: принять, отложить, отклонить или вернуть (OPS.5 из FPF).
- «закрывай» → карточка РП обновлена и сохранена в личной базе; в проекте ничего не сохраняется без команды.
- Отправка личной базы в удалённое хранилище - по команде владельца, после этого изменения видят клоны в других проектах (`git -C .workbench pull`).
- Личную базу можно открыть и отдельно, например для планирования: в её клоне `sh scripts/setup.sh`, затем `claude` в её корне.
- Сам workbench разрабатывается так же: установи workbench в рабочую копию шаблона, как в любой проект. Агент работает по твоей личной базе, а шаблон для него - обычный код.

## Обновление и удаление

- Обновить личную базу: `git -C .workbench pull` или ещё раз запустить установщик в проекте.
- Подтянуть обновления шаблона: `git -C .workbench pull template main`.
- Отключить от проекта: `sh .workbench/scripts/attach.sh --detach`; сама папка `.workbench` остаётся, её можно удалить вручную.

## Разработка

Код - только POSIX sh (`#!/bin/sh`). Изменения - через тесты: сначала падающий тест на [bats](https://github.com/bats-core/bats-core), потом код. Команды собраны в `Makefile`:

| Команда | Что делает |
|---|---|
| `make check` | проверка стиля, форматирования и все тесты; то же запускается на GitHub при каждом изменении |
| `make test` | тесты `tests/*.bats` |
| `make lint` | проверка стиля shellcheck, для скриптов - в режиме POSIX sh |
| `make format-check` | проверка форматирования shfmt, правила - в `.editorconfig` |
| `make format` | форматирует скрипты и тесты |

Тесты не трогают сеть и твои хранилища. Каждый файл тестов собирает песочницу во временной папке: закрытое хранилище заменяет локальное, FPF - маленькая локальная копия, шаблон - текущая рабочая копия вместе с несохранёнными правками. Проверяются установка в новый и во второй проект, отключение, издание FPF, перенос папки проекта, личная база отдельно и в разработке шаблона, хуки Claude Code, защита от опасных команд и проверки перед сохранением. Нужны `bats`, `shellcheck` и `shfmt`. В закрытых копиях шаблона прогон на GitHub пропускается.

## Личные настройки

- Раздел «Личные правила владельца» в `AGENTS.md` шаблон не меняет.
- `adapters/claude/settings.overlay.json` (нет в шаблоне) добавляется к настройкам Claude Code в каждом проекте: например, выключить плагины или запретить инструменты.
- Маркеры компании - в `.workbench/.git/info/company-markers`, по одному слову на строку: проверка перед сохранением не даст им попасть в личную базу.

## Ограничения

- Переходник есть только для Claude Code. Codex, Cursor и Kimi читают `AGENTS.md`, но их переходники ещё не сделаны.
- В Windows ссылкам на скиллы нужен режим разработчика.
- В WSL с git ниже 2.48 ссылка рабочей копии `.fpf` делается относительной вручную (как у подмодулей), `setup.sh` делает это сам.

## English

**workbench** is a personal, dotfiles-style workbench for working with AI coding agents in any project. It builds on the [First Principles Framework (FPF)](https://github.com/ailev/FPF): the agent relies on FPF patterns, and the owner's way of working is kept as a seed of a Local Practice Framework (LPF). Each project gets a clone of the owner's **private** knowledge-base repository in `.workbench`, invisible to the project's git.

Install in the root of a git project:

```sh
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
  --repo git@gitlab.com:you/my-workbench.git
```

An empty or missing private repository is created from this template (GitLab creates a private project on first push; on GitHub create an empty private repository first). The installer prepares the pinned FPF edition and connects the workbench to the project with local, git-excluded files only. The content (agent instructions, practice, skills) is in Russian; a Claude Code adapter is included, other agents read `AGENTS.md`. The code is POSIX sh; `make check` runs the offline bats tests, shellcheck and shfmt.

## Лицензия

MIT, см. `LICENSE`. Сторонние материалы и их лицензии - в `THIRD-PARTY.md`. FPF в шаблон не входит: он скачивается при установке и распространяется по CC BY 4.0.
