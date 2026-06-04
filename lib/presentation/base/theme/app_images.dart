import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppImages {
  AppImages._();

  static const String _notPhotoPath = 'assets/images/not_image.png';
  static const String _placeholderGifPath = 'assets/images/homer_loading.gif';
  static const String _successIconPath = 'assets/images/success_icon.svg';
  static const String _warningIconPath = 'assets/images/warning.svg';
  static const String _errorIconPath = 'assets/images/error.svg';

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
}
