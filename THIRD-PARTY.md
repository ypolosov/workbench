# Сторонние материалы

## First Principles Framework (FPF) и наборы DPF

- Автор: Anatoly Levenchuk. Источник: https://github.com/ailev/FPF
- Лицензия: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
- Использование: без изменений, рабочей копией git `.fpf` на издании из `.fpf-edition`; в историю workbench не входит.
- Абзац о подключении FPF в `AGENTS.md` (раздел 1) процитирован из FPF `Readme.md`; путь `fpf/` заменён на `$FPF`, как предлагает сам Readme.

## FMT-exocortex-template (IWE)

- Автор: Tseren Tserenov. Источник: https://github.com/TserenTserenov/FMT-exocortex-template
- Лицензия: MIT (текст ниже).
- Взято без изменений: `.agents/skills/vdv/SKILL.md`, `.agents/skills/vdv/test_cases.md`, `.githooks/pre-push`.
- Адаптировано: `adapters/claude/hooks/destructive-guard.sh` (убрана проверка путей от корня IWE), `adapters/claude/hooks/wp-gate-reminder.sh`, `adapters/claude/hooks/close-gate-reminder.sh`.
- По мотивам (новые тексты): правила в `AGENTS.md`, скиллы `wp-new` и `close-session`, соглашение «один РП - одна папка».

### Текст лицензии MIT

    MIT License
    
    Copyright (c) 2026 Tseren Tserenov
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
