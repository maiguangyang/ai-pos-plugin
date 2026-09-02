# EasyPOS Demo Integration

This package contains the single shared delivery-order implementation used by
the `easypos_demo` Integration Workspace. The same runtime and UI are exposed
through an AI POS plugin adapter and a standalone Flutter application root.

## Features

- Implements the AI POS plugin API `0.3` contract.
- Displays three local demo delivery orders and an order-detail flow.
- Pauses its periodic Timer while floating, resumes it in the foreground, and
  retains the same StreamController and page state.
- Owns and disposes its Timer, visibility listener, and Stream resources
  idempotently.
- Runs without host dependencies through `EasyPosDemoStandaloneApp`.

## Getting started

Run `flutter pub get` from this directory. For interactive development, run
the sibling application in `../../apps/easypos_demo_app`.

## Usage

```dart
import 'package:easypos_demo_integration/easypos_demo_integration.dart';

final plugin = EasyPosDemoPlugin();
```

## Additional information

This is a local-data feasibility integration. It contains no production
endpoint, credential, native SDK, or host capability request. See the
Workspace-level `README.md` and `integration.yaml` for composition details.
