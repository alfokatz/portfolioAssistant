enum ErrorType {
  connectionTimeout,
  receiveTimeout,
  sendTimeout,
  cancelled,
  badResponse,
  sslError,
  connectionError,
  unknown,
}

const Map<ErrorType, Map<String, String>> errorLocalizationKeys = {
  ErrorType.connectionTimeout: {
    'title': 'errors.connection_timeout_title',
    'message': 'errors.connection_timeout_message',
  },
  ErrorType.receiveTimeout: {
    'title': 'errors.receive_timeout_title',
    'message': 'errors.receive_timeout_message',
  },
  ErrorType.sendTimeout: {
    'title': 'errors.send_timeout_title',
    'message': 'errors.send_timeout_message',
  },
  ErrorType.cancelled: {
    'title': 'errors.cancelled_title',
    'message': 'errors.cancelled_message',
  },
  ErrorType.badResponse: {
    'title': 'errors.bad_response_title',
    'message': 'errors.bad_response_message',
  },
  ErrorType.sslError: {
    'title': 'errors.ssl_error_title',
    'message': 'errors.ssl_error_message',
  },
  ErrorType.connectionError: {
    'title': 'errors.connection_error_title',
    'message': 'errors.connection_error_message',
  },
  ErrorType.unknown: {
    'title': 'errors.unknown_title',
    'message': 'errors.unknown_message',
  },
};
