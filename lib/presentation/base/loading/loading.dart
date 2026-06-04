import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

String loadingAnimation = 'assets/animations/loading_animation.json';

class Loading extends StatelessWidget {
  const Loading({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Center(
        child: Lottie.asset(
          loadingAnimation,
          animate: true,
          repeat: true,
        ),
      ),
    );
  }
}
