import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ContentState {
  loading,
  loadingOverlay,
  showContent,
  networkError,
  genericError,
}

class ContentStateNotifier extends StateNotifier<ContentState> {
  ContentStateNotifier() : super(ContentState.loading);

  void setLoading() {
    _setState(contentState: ContentState.loading);
  }

  void setLoadingOverlay() {
    _setState(contentState: ContentState.loadingOverlay);
  }

  void setShowContent() {
    _setState(contentState: ContentState.showContent);
  }

  void setNetworkError() {
    _setState(contentState: ContentState.networkError);
  }

  void setGenericError() {
    _setState(contentState: ContentState.genericError);
  }

  void _setState({required ContentState contentState}) {
    Future.microtask(() => state = contentState);
  }
}

final contentStateNotifierProvider =
    StateNotifierProvider<ContentStateNotifier, ContentState>(
  (ref) {
    return ContentStateNotifier();
  },
);
