extension StartWith<T> on Stream<T> {
  /// Emits [value] first, then everything from this stream.
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
