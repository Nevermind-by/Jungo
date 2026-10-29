# Jungo

**A native, local-first Kanban app for macOS.**

Jungo is an independent project to build a fast, thoughtfully designed Kanban board that feels at home on the Mac. The repository is being bootstrapped; product scope and architecture are documented in [`docs/`](docs/).

## Product principles

- **Native first:** Swift and SwiftUI, with AppKit where it improves the macOS experience.
- **Local-first:** core task management must work without an account or network connection.
- **Fast capture:** creating and moving tasks should take as few interactions as possible.
- **Keyboard-friendly:** important actions should be discoverable and have shortcuts.
- **Trustworthy data:** changes persist reliably; export and backup are part of the product design.
- **Focused scope:** ship a useful personal Kanban before adding collaboration or integrations.

## Planned first release

- Multiple boards and configurable columns.
- Task cards with descriptions, priorities, labels, due dates and checklists.
- Drag-and-drop between columns and reorder within a column.
- Search, filters and quick capture.
- Local persistence, backup/export and recovery from interrupted writes.
- Light and dark appearance, accessibility and macOS keyboard conventions.

This list is a starting proposal, not a claim that these features are implemented yet.

## Documentation

- [Product vision and requirements](docs/PRODUCT.md)
- [Roadmap](docs/ROADMAP.md)
- [Architecture proposal](docs/ARCHITECTURE.md)
- [Development workflow](docs/DEVELOPMENT.md)
- [Decisions and open questions](docs/DECISIONS.md)

## Status

**Planning / repository bootstrap.** No application implementation has been added yet.

## License

Not selected yet. Do not assume this project is open source under a particular license until a license file is added.
