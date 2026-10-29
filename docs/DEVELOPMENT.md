# Разработка и Git workflow

## Требования

- macOS 26 Tahoe или новее.
- Xcode Command Line Tools и Swift 6 toolchain.
- Для notarized-релиза: Apple Developer account, Developer ID Application certificate и notarytool keychain profile.

## Локальные команды

    swift test
    swift run Jungo
    Scripts/build-app.sh
    Scripts/run-app.sh

Scripts/build-app.sh генерирует иконку, собирает release executable и создаёт development bundle с ad-hoc подписью. Это локальная сборка, не notarized-релиз.

## Настройка релизной подписи

1. Установить Developer ID Application certificate в Keychain.
2. Проверить доступную identity:

       security find-identity -v -p codesigning

3. Сохранить credentials для нотариализации в Keychain profile:

       xcrun notarytool store-credentials "JungoNotary" --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"

4. Собрать подписанный и notarized ZIP:

       DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="JungoNotary" Scripts/package-release.sh

Не сохраняй Apple ID пароль, app-specific password, сертификаты или другие секреты в репозитории. Скрипт проверяет подпись, отправляет архив на notarization, прикрепляет ticket и создаёт dist/Jungo-macOS.zip.

## GitHub Actions

.github/workflows/macos-ci.yml запускает swift test, собирает .app на macOS 26 и проверяет Info.plist, исполняемый файл и иконку. CI не выполняет подпись Developer ID или notarization.

## Правило веток

Каждый функциональный блок — отдельная ветка. Именование: feature/<short-name>, fix/<short-name>, docs/<short-name>.

## Чек-лист ручной проверки

- [ ] Создание/переименование доски; восстановление выбранной доски.
- [ ] Создание, редактирование и перемещение задачи.
- [ ] Удаление задачи в корзину, восстановление, окончательное удаление.
- [ ] После окончательного удаления удаляются пункты чек-листа.
- [ ] Перетаскивание между колонками и перестановка внутри колонки.
- [ ] Удаление колонки переносит задачи.
- [ ] Метки, чек-лист, сроки и приоритет сохраняются после перезапуска.
- [ ] Экспорт/импорт включает метки, сроки, чек-листы и корзину.
- [ ] Импорт старого JSON-архива без новых полей.
- [ ] Повреждённый JSON вызывает понятную ошибку.
- [ ] Проверка светлой/тёмной темы и VoiceOver.
- [ ] Запуск через dist/Jungo.app; иконка отображается в Finder и Dock.
- [ ] Подписанная/notarized сборка открывается на чистом Mac.

## Принцип

Не отмечать проверку выполненной, если команда или сценарий фактически не запускались. Статическая проверка кода не заменяет сборку и тесты на macOS.
