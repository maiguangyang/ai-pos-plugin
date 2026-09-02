# EasyPOS Demo App

This is the independently runnable Android/iOS shell for the `easypos_demo`
Integration Workspace. It imports `easypos_demo_integration` by local path, so
shared business and UI changes participate in normal Flutter hot reload.

## Run

```bash
flutter pub get
flutter run
```

The application owns only its platform packaging and standalone root. Delivery
orders, navigation, runtime resources, and the host plugin adapter stay in the
shared package; do not duplicate them here.

## Scope

The current proof-of-concept uses local data only and does not configure
production endpoints, credentials, permissions, signing, or store metadata.
