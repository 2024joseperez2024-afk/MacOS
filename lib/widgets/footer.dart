import 'package:flutter/material.dart';

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 12);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text('Creada por Ramón Telleria (Kanopola)', style: textStyle),
          SizedBox(height: 5),
          Text('Versión: 2.1. Licencia MIT.', style: textStyle),
          SizedBox(height: 5),
          Text('www.huevobit.com', style: textStyle),
          SizedBox(height: 5),
          Text('© 2025 Huevobit. Todos los derechos reservados.',
              style: textStyle),
        ],
      ),
    );
  }
}