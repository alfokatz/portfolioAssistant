extension DynamicExtension<T> on T? {
  void let({
    required Function(T) notNull,
    Function? isNull,
  }) {
    if (this != null) {
      notNull.call(this as T);
    } else {
      isNull?.call();
    }
  }
}
