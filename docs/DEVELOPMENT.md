# Разработка и Git workflow

## Требования

- macOS 26 Tahoe или новее.
- Swift 6 toolchain и Xcode Command Line Tools.

## Локальная разработка

```bash
swift test
swift run Jungo
```

Собрать и открыть приложение:

```bash
Scripts/run-app.sh
```

Собрать только `.app`:

```bash
Scripts/build-app.sh
```

Скрипт создаёт локальный development bundle, генерирует иконку и использует ad-hoc подпись. Это не notarized-дистрибутив для распространения на чужих Mac.

Версия по умолчанию — `0.1.0`, build number — `1`. Переопределение:

```bash
JUNGO_VERSION="0.1.0" JUNGO_BUILD_NUMBER="1" Scripts/build-app.sh
```

## GitHub Actions

Workflow `.github/workflows/macos-ci.yml` выполняется на `macos-26` и:
1. Показывает версию macOS и Swift toolchain.
2. Запускает `swift test`.
3. Собирает development app bundle.
4. Проверяет `Info.plist`, исполняемый файл и непустую иконку.

CI не запускает интерактивное приложение и не проверяет ручные сценарии SwiftData/Vault.

## Source-only GitHub Release

Текущий канал публикации — GitHub Releases с исходным кодом. GitHub автоматически прикладывает архивы исходников к релизу по тегу. Готовый .app ZIP/DMG в MVP-релиз не входит.

Apple Developer ID и notarization не требуются для публикации исходников. Они понадобятся только при отдельном решении распространять готовое приложение для установки на других Mac.

## Git workflow

Каждый самостоятельный блок — отдельная ветка:
- `feature/<short-name>`
- `fix/<short-name>`
- `docs/<short-name>`

Рекомендуемый поток: ветка → изменения → CI → PR → merge в main. Не выполнять force push в main.

## Ручные проверки

Полные сценарии собраны в:
- [Проверка целостности данных](DATA_INTEGRITY_CHECKLIST.md)
- [Проверка Vault](VAULT_VALIDATION_CHECKLIST.md)

Пункты отмечаются только после фактического выполнения. Unit-тесты и сборка не доказывают корректность интерактивных сценариев SwiftData, VoiceOver или миграций.
