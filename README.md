# workbench

Личный верстак для работы с ИИ-агентами в любых проектах. Основа — FPF (First Principles Framework, [ailev/FPF](https://github.com/ailev/FPF)): агент опирается на его паттерны, а практика работы записана как зародыш собственного фреймворка локальной практики (LPF). Часть практики взята из шаблона IWE ([TserenTserenov/FMT-exocortex-template](https://github.com/TserenTserenov/FMT-exocortex-template), MIT): ВДВ, учёт рабочих продуктов (РП), напоминания и защита от опасных команд.

Устроено как dotfiles: в каждом проекте лежит клон **твоей закрытой** базы знаний в папке `.workbench`, а git проекта её не видит. Этот публичный репозиторий - шаблон и установщик.

## Установка

В корне своего проекта (это должен быть git-проект):

```bash
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash
```

Установщик спросит адрес закрытого хранилища для личной базы. Можно указать его сразу:

```bash
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash -s -- \
  --repo git@gitlab.com:you/my-workbench.git
# или из пространства и имени (по умолчанию имя my-workbench):
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash -s -- \
  --base git@gitlab.com:you --name my-workbench
```

Что происходит:

1. Хранилище уже есть и не пустое → клонируется в `.workbench`.
2. Хранилище пустое или его нет → создаётся из этого шаблона и отправляется туда. GitLab создаёт закрытый проект прямо при первой отправке; на GitHub сначала создай пустое закрытое хранилище.
3. Готовится закреплённое издание FPF (`.workbench/.fpf`, издание - в `.fpf-edition`).
4. workbench подключается к проекту только локальными файлами, прописанными в `.git/info/exclude` проекта: `CLAUDE.local.md`, `.claude/settings.local.json`, ссылки на скиллы в `.claude/skills/`. Существующие локальные настройки дополняются, копия сохраняется.

Все параметры: `curl -fsSL .../install.sh | bash -s -- --help`. Нужны `git`, `bash`, `jq`; для переходника - [Claude Code](https://claude.com/claude-code).

## Раскладка

```text
<проект>/                  проект не меняется; .workbench исключён в его .git/info/exclude
  .workbench/              клон личной базы (в VS Code виден как отдельное хранилище)
    .fpf/                  закреплённое издание FPF: рабочая копия git, в .gitignore
```

| Часть | Где |
|---|---|
| Инструкции для любых агентов | `AGENTS.md` (Claude Code читает его через `CLAUDE.md`) |
| Практика работы и её основания в FPF | `lpf/README.md` |
| Реестр РП, карточки, заметки, решения | `docs/WP-REGISTRY.md`, `inbox/`, `decisions/` |
| Личная память | `memory/` |
| Скиллы в общем для агентов формате | `.agents/skills/` (`vdv`, `wp-new`, `close-session`) |
| Переходник для Claude Code | `adapters/claude/hooks/` |
| Проверки для любого агента и человека | `.githooks/`: маркеры компании и секреты при сохранении, запрет перезаписи истории |
| Подготовка и подключение | `scripts/setup.sh`, `scripts/attach.sh` |
| Проверка установки | `tests/smoke.sh` |

## Работа

- `claude` в корне проекта. В начале сессии агент видит пути, издание FPF, состояние клона и активные РП.
- Любая задача сначала связывается с РП: принять, отложить, отклонить или вернуть (OPS.5 из FPF).
- «закрывай» → карточка РП обновлена и сохранена в личной базе; в проекте ничего не сохраняется без команды.
- Отправка личной базы в удалённое хранилище - по команде владельца, после этого изменения видят клоны в других проектах (`git -C .workbench pull`).

## Обновление и удаление

- Обновить личную базу: `git -C .workbench pull` или ещё раз запустить установщик в проекте.
- Подтянуть обновления шаблона: `git -C .workbench pull template main`.
- Отключить от проекта: `bash .workbench/scripts/attach.sh --detach`; сама папка `.workbench` остаётся, её можно удалить вручную.

## Проверка

`bash tests/smoke.sh` прогоняет установку от начала до конца во временной папке: без сети и без твоих хранилищ. Закрытое хранилище заменяет локальное, FPF - маленькая локальная копия, шаблон - текущая рабочая копия вместе с несохранёнными правками. Проверяется:

- установка в новый проект и во второй проект с уже существующей личной базой, обновление повторным запуском;
- git проекта ничего не видит, а отключение возвращает проект в прежнее состояние;
- издание FPF: одна ревизия, запертая рабочая копия, перенос папки проекта;
- хуки Claude Code в том виде, в каком их запускает Claude Code, и проверки перед сохранением в личной базе.

`KEEP=1 bash tests/smoke.sh` оставляет временную папку для разбора. На GitHub тот же прогон запускается при каждом изменении шаблона; в закрытых копиях он пропускается.

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

```bash
curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash -s -- \
  --repo git@gitlab.com:you/my-workbench.git
```

An empty or missing private repository is created from this template (GitLab creates a private project on first push; on GitHub create an empty private repository first). The installer prepares the pinned FPF edition and connects the workbench to the project with local, git-excluded files only. The content (agent instructions, practice, skills) is in Russian; a Claude Code adapter is included, other agents read `AGENTS.md`. `bash tests/smoke.sh` runs an offline end-to-end check of the installer in a temporary directory.

## Лицензия

MIT, см. `LICENSE`. Сторонние материалы и их лицензии - в `THIRD-PARTY.md`. FPF в шаблон не входит: он скачивается при установке и распространяется по CC BY 4.0.
