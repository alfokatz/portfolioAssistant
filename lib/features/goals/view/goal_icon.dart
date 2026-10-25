import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// El ícono de una meta según de QUÉ se trata (un viaje lleva un avión; una
/// compu, una compu), deducido del nombre que le puso el usuario. Si el
/// nombre no dice nada reconocible, el del tipo: una bolsa para una
/// compra, una sombrilla para la jubilación, una bandera para el resto.
///
/// Todos de la familia "rounded" de Material: el trazo redondeado de Porty
/// (los "outlined" de antes se veían de plantilla).
abstract final class GoalIcon {
  static IconData of(String label, GoalType type) {
    final text = _fold(label);
    for (final (pattern, icon) in _byTopic) {
      if (pattern.hasMatch(text)) return icon;
    }
    return switch (type) {
      GoalType.purchase => Icons.shopping_bag_rounded,
      GoalType.retirement => Icons.beach_access_rounded,
      GoalType.other => Icons.flag_rounded,
    };
  }

  static IconData forGoal(UserGoal goal) => of(goal.label, goal.type);

  /// Minúsculas y sin tildes: "Viaje a Japón" → "viaje a japon".
  static String _fold(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñç';
    const to = 'aaaaeeeeiiiioooouuuunc';
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      out.write(i < 0 ? ch : to[i]);
    }
    return out.toString();
  }

  static RegExp _words(String alternatives) =>
      RegExp('\\b(?:$alternatives)\\b');

  /// En orden: lo más específico primero ("casamiento" antes que "casa",
  /// "moto" antes que "auto").
  static final _byTopic = <(RegExp, IconData)>[
    (
      _words(
        'jubilacion|jubilarme|jubilarse|retiro|retirarme|retirement|pension',
      ),
      Icons.beach_access_rounded,
    ),
    (
      _words('emergencia|emergencias|imprevistos?|colchon|emergency|rainy day'),
      Icons.health_and_safety_rounded,
    ),
    (
      _words('casamiento|boda|casarme|casarnos|anillo|compromiso|wedding|ring'),
      Icons.diamond_rounded,
    ),
    (
      _words(
        'viaje|viajes|viajar|vacaciones|vacacion|pasaje|pasajes|mochilear|trip|travel|vacation|flight|holiday|japon|europa|disney|mundial',
      ),
      Icons.flight_takeoff_rounded,
    ),
    (
      _words('moto|motos|motocicleta|scooter|motorcycle|motorbike'),
      Icons.two_wheeler_rounded,
    ),
    (_words('bici|bicicleta|bike|bicycle'), Icons.pedal_bike_rounded),
    (
      _words('auto|autos|coche|carro|camioneta|car|truck|tesla'),
      Icons.directions_car_rounded,
    ),
    (
      _words(
        'compu|computadora|notebook|laptop|macbook|mac|pc|computer|ordenador',
      ),
      Icons.laptop_mac_rounded,
    ),
    (_words('ipad|tablet|tableta'), Icons.tablet_mac_rounded),
    (
      _words(
        'celular|celu|iphone|telefono|smartphone|movil|phone|samsung|pixel',
      ),
      Icons.phone_iphone_rounded,
    ),
    (_words('reloj|smartwatch|watch'), Icons.watch_rounded),
    (
      _words('auriculares|airpods|headphones|parlante'),
      Icons.headphones_rounded,
    ),
    (_words('tele|televisor|tv|smart tv|television'), Icons.tv_rounded),
    (
      _words('consola|playstation|ps5|ps4|xbox|nintendo|switch|gamer|console'),
      Icons.sports_esports_rounded,
    ),
    (_words('camara|camera|lente'), Icons.photo_camera_rounded),
    (
      _words('guitarra|piano|bateria|instrumento|guitar|instrument'),
      Icons.music_note_rounded,
    ),
    (
      _words(
        'casa|casita|depto|departamento|vivienda|hogar|hipoteca|terreno|house|home|apartment|flat|mortgage',
      ),
      Icons.home_rounded,
    ),
    (
      _words('mudanza|mudarme|alquiler|deposito|moving|rent'),
      Icons.local_shipping_rounded,
    ),
    (
      _words('reforma|refaccion|remodelar|obra|renovation'),
      Icons.construction_rounded,
    ),
    (
      _words('muebles|mueble|sillon|sofa|cama|colchon nuevo|furniture|couch'),
      Icons.weekend_rounded,
    ),
    (
      _words(
        'estudios|estudiar|universidad|facultad|maestria|master|mba|posgrado|curso|carrera|colegio|school|college|university|course|tuition',
      ),
      Icons.school_rounded,
    ),
    (
      _words('bebe|bebes|hijo|hija|hijos|embarazo|baby|kid|kids'),
      Icons.child_friendly_rounded,
    ),
    (_words('perro|gato|mascota|veterinario|dog|cat|pet'), Icons.pets_rounded),
    (
      _words('fiesta|cumple|cumpleanos|quince|party|birthday'),
      Icons.celebration_rounded,
    ),
    (
      _words('regalo|regalos|navidad|gift|christmas'),
      Icons.card_giftcard_rounded,
    ),
    (
      _words(
        'ropa|zapatillas|indumentaria|vestido|traje|clothes|shoes|sneakers',
      ),
      Icons.checkroom_rounded,
    ),
    (
      _words(
        'salud|cirugia|operacion|dentista|ortodoncia|tratamiento|medico|surgery|dentist|health',
      ),
      Icons.medical_services_rounded,
    ),
    (
      _words('negocio|emprendimiento|emprender|local|empresa|business|startup'),
      Icons.storefront_rounded,
    ),
    (
      _words('deuda|deudas|tarjeta|prestamo|cancelar|debt|loan|credit card'),
      Icons.credit_card_rounded,
    ),
    (
      _words(
        'ahorro|ahorrar|ahorros|juntar|reunir|fondo|usd|dolares|savings|save',
      ),
      Icons.savings_rounded,
    ),
  ];
}
