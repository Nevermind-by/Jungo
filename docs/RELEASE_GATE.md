# Jungo — release gate

## Цель релиза

Первый GitHub Release публикует **исходный код MVP**. Бинарный .app, ZIP/DMG, Developer ID signing и Apple notarization в этот релиз не входят.

## Зафиксированное состояние

- Репозиторий: `Nevermind-by/Jungo`.
- Целевая ветка: `main`.
- Последний интегрированный функциональный commit: `662f413d0df966bc208c00d0b2480b12d952f4a3`.
- PR #67 — Quick Add layout fix — слит в main.
- Последний CI для main перед подготовкой документации: [run #186](https://github.com/Nevermind-by/Jungo/actions/runs/41058799530), conclusion: `success`.
- Пользователь запустил приложение локально и подтвердил, что Quick Add отображается корректно.
- До этой подготовки GitHub Releases и git tags отсутствовали.

## Что входит в MVP

- Kanban: доски, колонки, задачи, drag-and-drop.
- Приоритеты, сроки, метки, чек-листы, Markdown preview.
- Поиск, фильтры, архив и корзина.
- Быстрое добавление, меню-бар и горячие клавиши.
- Undo/Redo.
- JSON import/export.
- Локальный Vault.
- Нативный адаптивный macOS UI.

## Проверка

### Подтверждено автоматикой
- `swift test` в macOS 26 CI.
- Сборка development app bundle.
- Проверка Info.plist, исполняемого файла и AppIcon.
- Последний зафиксированный main CI #186 успешен.

### Подтверждено пользователем
- Локальный запуск приложения после изменения Quick Add.
- Визуальная компоновка Quick Add признана корректной.

### Не подтверждается этим CI и остаётся отдельной ручной проверкой
- Миграции SwiftData и перенос Vault на разных состояниях/дисках.
- Восстановление после принудительного завершения.
- Полная матрица Undo/Redo и каскадных операций.
- VoiceOver и полный keyboard-only проход.
- Все негативные сценарии импорта/экспорта на живой базе.

См. [DATA_INTEGRITY_CHECKLIST.md](DATA_INTEGRITY_CHECKLIST.md) и [VAULT_VALIDATION_CHECKLIST.md](VAULT_VALIDATION_CHECKLIST.md). Не отмечать пункты выполненными без фактического прогона.

## Чек-лист публикации исходного кода

- [x] Основной функциональный объём MVP интегрирован в main.
- [x] Последний функциональный PR #67 слит.
- [x] CI для последнего функционального commit успешен.
- [ ] Документация обновлена и слита в main.
- [ ] CI после документационных изменений успешен.
- [ ] Создать git tag `v0.1.0` на итоговом main commit.
- [ ] Создать GitHub Release `Jungo v0.1.0 — MVP` с release notes.
- [ ] Указать, что релиз содержит исходники и не содержит готового бинарного приложения.

## Известные ограничения

- SwiftData integration tests не входят в текущий SwiftPM CI: экспериментальная suite завершалась с `signal 5`.
- Notarized binary distribution не является целью этого source-only релиза.
