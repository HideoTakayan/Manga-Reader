/// Result type for handling success/failure cases
/// A simple Either-like type without external dependencies

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => switch (this) {
    Success<T> s => s.value,
    Failure<T> _ => null,
  };

  R when<R>({
    required R Function(T value) success,
    required R Function(String message) failure,
  }) {
    return switch (this) {
      Success<T> s => success(s.value),
      Failure<T> f => failure(f.message),
    };
  }

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T> s => Success(transform(s.value)),
      Failure<T> f => Failure(f.message),
    };
  }
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

class Failure<T> extends Result<T> {
  final String message;
  const Failure(this.message);
}
