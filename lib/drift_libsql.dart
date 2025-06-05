library drift_libsql;

import 'dart:async';

import 'package:drift/backends.dart';
import 'package:libsql_dart/libsql_dart.dart';

typedef ExtensionDescriptor = ({String path, String? entryPoint});

final class DriftLibsqlDatabase extends DelegatedDatabase {
  DriftLibsqlDatabase._(super.delegate);

  DriftLibsqlDatabase(
    String url, {
    String? authToken,
    String? syncUrl,
    int? syncIntervalSeconds,
    String? encryptionKey,
    bool? readYourWrites,
    bool? offline,
    bool enableExtensions = false,
    List<ExtensionDescriptor>? extensions,
  }) : this._(
          _LibsqlDelegate(
            LibsqlClient(
              url,
              authToken: authToken,
              syncUrl: syncUrl,
              syncIntervalSeconds: syncIntervalSeconds,
              encryptionKey: encryptionKey,
              readYourWrites: readYourWrites,
              offline: offline,
            ),
            extensions: extensions,
          ),
        );

  Future<void> sync() {
    return (delegate as _LibsqlDelegate).sync();
  }
}

final class _LibsqlDelegate extends DatabaseDelegate {
  final LibsqlClient _client;
  final List<ExtensionDescriptor> _extensions;

  bool _open = false;

  _LibsqlDelegate(
    this._client, {
    List<ExtensionDescriptor>? extensions,
  }) : _extensions = extensions ?? [];

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

    if (_extensions.isNotEmpty) {
      await _client.enableExtension();

      for (final ext in _extensions) {
        await _client.loadExtension(
          path: ext.path,
          entryPoint: ext.entryPoint,
        );
      }

      await _client.disableExtension();
    }

    _open = true;
  }

  Future<void> sync() async {
    await _client.sync();
  }

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  DbVersionDelegate get versionDelegate =>
      _LibsqlVersionDelegate(delegate: this);
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
