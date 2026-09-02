# EasyPOS Demo Integration Workspace

This EasyPOS-owned development workspace proves that one shared Flutter
business package can run both inside the AI POS host and as an independently
publishable application. It contains local demonstration data only.

## Run independently

```bash
cd apps/easypos_demo_app
flutter run
```

The application imports `packages/easypos_demo_integration` by local path, so
changes to shared UI and business code participate in normal Flutter hot reload.

## Boundaries

- No production endpoint, credential, permission, or native SDK is included.
- The integration package depends only on `ai_pos_plugin_api` in production.
- The standalone App owns signing and store configuration; the AI POS host only
  consumes the integration package.
