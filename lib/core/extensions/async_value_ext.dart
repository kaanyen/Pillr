import 'package:flutter_riverpod/flutter_riverpod.dart';

extension AsyncValueX<T> on AsyncValue<T> {
  T? get valueOrNull => switch (this) {
        AsyncData(:final value) => value,
        _ => null,
      };
}
