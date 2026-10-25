import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppImages {
  AppImages._();

  static const String _notPhotoPath = 'assets/images/not_image.png';
  static const String _placeholderGifPath = 'assets/images/homer_loading.gif';
  static const String _successIconPath = 'assets/images/success_icon.svg';
  static const String _warningIconPath = 'assets/images/warning.svg';
  static const String _errorIconPath = 'assets/images/error.svg';
  static const String _googleIconPath = 'assets/images/google_icon.svg';
  static const String _etoroLogoPath = 'assets/images/etoro_logo.svg';
  static const String _etoroMarkPath = 'assets/images/etoro_mark.svg';

  /// Proporción del wordmark de eToro (ancho / alto).
  static const double etoroLogoAspect = 107 / 20;

  static Image notPhoto({
    Key? key,
    BoxFit? fit,
    double? width,
    double? height,
    Color? color,
  }) => Image.asset(
    _notPhotoPath,
    key: key,
    fit: fit,
    width: width,
    height: height,
    color: color,
  );

  static const AssetImage placeholderImage = AssetImage(_placeholderGifPath);

  static SvgPicture successIcon({
    Key? key,
    double? width,
    double? height,
    Color? color,
    BoxFit fit = BoxFit.contain,
  }) => SvgPicture.asset(
    _successIconPath,
    key: key,
    width: width,
    height: height,
    color: color,
    fit: fit,
  );

  static SvgPicture warning({
    Key? key,
    double? width,
    double? height,
    Color? color,
    BoxFit fit = BoxFit.contain,
  }) => SvgPicture.asset(
    _warningIconPath,
    key: key,
    width: width,
    height: height,
    color: color,
    fit: fit,
  );

  static SvgPicture error({
    Key? key,
    double? width,
    double? height,
    Color? color,
    BoxFit fit = BoxFit.contain,
  }) => SvgPicture.asset(
    _errorIconPath,
    key: key,
    width: width,
    height: height,
    color: color,
    fit: fit,
  );

  static SvgPicture googleIcon({
    Key? key,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) => SvgPicture.asset(
    _googleIconPath,
    key: key,
    width: width,
    height: height,
    fit: fit,
  );

  /// Wordmark de eToro, en su verde. Con [color], monocromo.
  static SvgPicture etoroLogo({
    Key? key,
    double height = 16,
    Color? color,
    String? semanticsLabel,
  }) => SvgPicture.asset(
    _etoroLogoPath,
    key: key,
    height: height,
    width: height * etoroLogoAspect,
    colorFilter:
        color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
    semanticsLabel: semanticsLabel,
    excludeFromSemantics: semanticsLabel == null,
  );

  /// El ícono de eToro ("‹e›" en verde), sin fondo. Proporción 40,5 × 20.
  static SvgPicture etoroMark({Key? key, double width = 20}) =>
      SvgPicture.asset(
        _etoroMarkPath,
        key: key,
        width: width,
        height: width * 20 / 40.5,
        excludeFromSemantics: true,
      );
}
