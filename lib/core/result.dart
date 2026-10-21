enum FailureKind {
  notFound,
  invalidInput,
  io,
  permission,
  network,
  unsupported,
  unknown,
}

class Failure {
  const Failure(this.kind, this.message, {this.cause});

  final FailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'Failure(${kind.name}: $message)';
}

sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
