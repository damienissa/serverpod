import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:serverpod_serialization/serverpod_serialization.dart';

typedef void ServerpodClientErrorCallback(Error e);

class ServerpodClient {
  final String _authorizationKeyEntry = 'serverpod_authorizationKey';

  final String host;
  final SerializationManager serializationManager;
  HttpClient _httpClient;
  String _authorizationKey;
  bool _initialized = false;
  ServerpodClientErrorCallback errorHandler;

  ServerpodClient(this.host, this.serializationManager, {SecurityContext context, this.errorHandler}) {
    _httpClient = HttpClient(context: context);
    assert(host.endsWith('/'), 'host must end with a slash, eg: https://example.com/');
    assert(host.startsWith('http://') || host.startsWith('https://'), 'host must include protocol, eg: https://example.com/');
  }

  Future<Null> _initialize() async {
    var prefs = await SharedPreferences.getInstance();
    _authorizationKey = prefs.get(_authorizationKeyEntry);

    _initialized = true;
  }

  Future<dynamic> callServerEndpoint(String endpoint, String method, String returnTypeName, Map<String, dynamic> args) async {
    if (!_initialized)
      await _initialize();

    try {
      var formattedArgs = <String>[];
      for (var argName in args.keys) {
        var value = args[argName];
        if (value != null)
          formattedArgs.add('$argName=${Uri.encodeQueryComponent('$value')}');
      }
      if (_authorizationKey != null)
        formattedArgs.add('auth=${Uri.encodeQueryComponent(_authorizationKey)}');
      formattedArgs.add('method=${Uri.encodeQueryComponent(method)}');

      var queryStr = formattedArgs.join('&');
      if (formattedArgs.length > 0)
        queryStr = '?$queryStr';

      Uri url = Uri.parse('$host$endpoint$queryStr');

      HttpClientRequest request = await _httpClient.getUrl(url);
      HttpClientResponse response = await request
          .close(); // done instead of close() ?
      String data = await _readResponse(response);

      if (returnTypeName == 'int')
        return int.parse(data);
      else if (returnTypeName == 'String')
        return data;

      return serializationManager.createEntityFromSerialization(
          jsonDecode(data));
    }
    catch(e) {
      if (errorHandler != null)
        errorHandler(e);
      else
        rethrow;
    }
  }

  Future<dynamic> _readResponse(HttpClientResponse response) {
    var completer = new Completer();
    var contents = new StringBuffer();
    response.transform(Utf8Decoder()).listen((String data) {
      contents.write(data);
    }, onDone: () => completer.complete(contents.toString()));
    return completer.future;
  }

  Future<Null> setAuthorizationKey(String authorizationKey) async {
    _authorizationKey = authorizationKey;
    var prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authorizationKeyEntry, authorizationKey);
  }
}