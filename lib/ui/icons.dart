import 'package:flutter/material.dart';

IconData businessIcon(String key) => switch (key) {
      'grocery' => Icons.local_grocery_store,
      'pharmacy' => Icons.local_pharmacy,
      'clothing' => Icons.checkroom,
      'mobile' => Icons.smartphone,
      'restaurant' => Icons.restaurant,
      'perfume' => Icons.spa,
      'hardware' => Icons.hardware,
      _ => Icons.storefront,
    };
