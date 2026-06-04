import 'package:dartz/dartz.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/content_state/content_state_provider.dart';
import 'package:portfolio_assistant/shared/extensions/DynamicExtensions.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart'
    show HttpError;

abstract class BaseStateNotifier<S, A> extends StateNotifier<S> {
  late Ref ref;

  BaseStateNotifier({required S state, required this.ref}) : super(state);

  Future<void> callService<T>({
    required Future<Either<HttpError, T>> Function() service,
    required Function(T) onSuccess,
    Function(HttpError)? onCustomError,
  }) async {
    final result = await service.call();
    result.fold(
      (error) => {
        onCustomError.let(
          notNull: (value) {
            value.call(error);
          },
          isNull: () => {},
        ),
      },
      (successResponse) => {onSuccess.call(successResponse)},
    );
  }

  void showLoading() {
    ref.read(contentStateNotifierProvider.notifier).setLoading();
  }

  void showContent() {
    ref.read(contentStateNotifierProvider.notifier).setShowContent();
  }

  void reducer({required A action});
}
