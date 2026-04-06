import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

bool listIndicatesOffline(List<ConnectivityResult> results) {
  if (results.isEmpty) return true;
  return results.length == 1 && results.first == ConnectivityResult.none;
}
