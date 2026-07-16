# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-08

### Added

- MIT License for the repository
- Comprehensive README with full documentation: architecture overview, AI/ML pipeline, database schema, threat classification, and troubleshooting guide

### Changed

- Marked as the first stable, publicly documented release

## [0.2.1] - 2026-03-08

### Changed

- Enhanced real-time SMS monitoring for improved data handling
- Improved UI responsiveness with dedicated scroll controllers
- Refined Android build configuration

## [0.2.0] - 2026-03-03

### Added

- Guardian contact management system
- Guardian notification service for alerting trusted contacts on detected scam SMS
- Settings page for managing guardians and app preferences
- SMS sender service for outbound guardian alerts

### Changed

- Extended database schema to support guardian records
- Updated SMS and contacts services to integrate with guardian workflow

## [0.1.0] - 2026-03-01

### Added

- Initial project scaffold (Flutter + Android native project)
- Real-time SMS monitoring service using `another_telephony`
- On-device scam detection engine via ONNX Runtime (MobileBERT model)
- SQLite-backed local database for storing scanned messages
- Background scam processor service for asynchronous message classification
- Contacts service and permission handling
- Model hosting documentation (`MODEL_HOSTING.md`) for the externally hosted ONNX model

[1.0.0]: https://github.com/tanishqmudaliar/SilverGuard/compare/v0.2.1...v1.0.0
[0.2.1]: https://github.com/tanishqmudaliar/SilverGuard/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tanishqmudaliar/SilverGuard/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tanishqmudaliar/SilverGuard/releases/tag/v0.1.0
