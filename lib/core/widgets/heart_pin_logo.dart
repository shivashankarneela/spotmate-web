import 'package:flutter/material.dart';

class HeartPinLogo extends StatelessWidget {
  final double size;
  const HeartPinLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Location pin body
          Icon(
            Icons.location_on_rounded,
            size: size,
            color: const Color(0xFFFF4B6E),
          ),
          // Heart shape embedded inside the pin
          Positioned(
            top: size * 0.16,
            child: Icon(
              Icons.favorite_rounded,
              size: size * 0.36,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
