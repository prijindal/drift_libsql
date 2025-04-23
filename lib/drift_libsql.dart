library drift_libsql;

import 'dart:async';

import 'package:drift/backends.dart';
import 'package:libsql_dart/libsql_dart.dart';

final class DriftLibsqlDatabase extends DelegatedDatabase {
  final LibsqlClient client;

  DriftLibsqlDatabase._(_LibsqlDelegate delegate, this.client) : super(delegate);

  factory DriftLibsqlDatabase(
    String url, {
    String? authToken,
    String? syncUrl,
    int? syncIntervalSeconds,
    String? encryptionKey,
    bool? readYourWrites,
    bool? offline,
    bool enableExtensions = false,
    List<ExtensionDescriptor>? extensions,
  }) {
    final client = LibsqlClient(
      url,
      authToken: authToken,
      syncUrl: syncUrl,
      syncIntervalSeconds: syncIntervalSeconds,
      encryptionKey: encryptionKey,
      readYourWrites: readYourWrites,
      offline: offline,
    );
    final delegate = _LibsqlDelegate(client, enableExtensions, extensions ?? const []);
    return DriftLibsqlDatabase._(delegate, client);
  }
}

final class _LibsqlDelegate extends DatabaseDelegate {
  final LibsqlClient _client;
  final List<ExtensionDescriptor> _extensions;

  bool _enableExtensions;
  
  bool _open = false;

  _LibsqlDelegate(this._client, this._enableExtensions, this._extensions);

  @override
  Future<void> runCustom(String statement, List<Object?> args) async {
    await _client.execute(statement, positional: args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    final _ = await _client.query(statement, positional: args);
    return 0;
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final res = await _client.query(statement, positional: args);
    return QueryResult.fromRows(res);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    return _client.execute(statement, positional: args);
  }

  @override
  FutureOr<bool> get isOpen => Future.value(_open);

  @override
  Future<void> open(QueryExecutorUser db) async {
    await _client.connect();

    if (_enableExtensions == true) {
      await _client.enableExtension();
    
      for (final ext in _extensions) {
        if (ext.entryPoint != null) {
          await _client.loadExtension(
            path: ext.path,
            entryPoint: ext.entryPoint,
          );
        } else {
          await _client.loadExtension(
            path: ext.path,
          );
        }
      }
      
    }
    _open = true;
  }

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  DbVersionDelegate get versionDelegate => _LibsqlVersionDelegate(delegate: this);
}

final class _LibsqlVersionDelegate extends DynamicVersionDelegate {
  final _LibsqlDelegate delegate;

  _LibsqlVersionDelegate({required this.delegate});

  @override
  Future<int> get schemaVersion async {
    final result = await delegate._client.query('pragma user_version;');
    return result.first['user_version'] as int;
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await delegate._client.execute('pragma user_version = $version;');
  }
}

final class ExtensionDescriptor {
  final String path;
  final String? entryPoint;

  const ExtensionDescriptor({
    required this.path,
    this.entryPoint,
  });
}
