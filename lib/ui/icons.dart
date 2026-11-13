import 'package:flutter/material.dart';

IconData businessIcon(String key) => switch (key) {
      'grocery' => Icons.local_grocery_store,
      'pharmacy' => Icons.local_pharmacy,
      'clothing' => Icons.checkroom,
      'mobile' => Icons.smartphone,
      'restaurant' => Icons.restaurant,
      'perfume' => Icons.spa,
      'hardware' => Icons.hardware,
      'bakery' => Icons.bakery_dining,
      'salon' => Icons.content_cut,
      'car_rental' => Icons.directions_car,
      'stationery' => Icons.menu_book,
      'auto_parts' => Icons.build,
      _ => Icons.storefront,
    };
