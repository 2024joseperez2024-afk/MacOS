import 'package:flutter/material.dart';

class ReglasJuegoDialog extends StatelessWidget {
  const ReglasJuegoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Reglas Oficiales de Huevobit',
          style: TextStyle(color: Colors.yellow, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text(
                '📌 Cómo Jugar:\n',
                style: TextStyle(color: Colors.yellow, fontSize: 16),
              ),
              const Text(
                    '1. Genera tu billetera blockchain (solo una vez)\n\n'
                    '2. Deposita BNB en tu dirección\n\n'
                    '3. Elige un Nido con monto de participación (Ejemplo: 0.01, 0.02, 0.03, etc.)\n\n'
                    '4. Selecciona una Canasta disponible\n\n'
                    '5. El contrato te asignará automáticamente un número aleatorio según tu posición al entrar\n\n'
                    '6. Espera el sorteo después que se llene la Canasta\n\n'
                    '7. El contrato elegirá el ganador de forma segura, íntegra e inmutable con el Sistema VRF de un Oráculo\n\n',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 10),
              const Text(
                '🏆 Sistema de Premios:\n',
                style: TextStyle(color: Colors.yellow, fontSize: 16),
              ),
              const Text(
                    '✅ 90% del bote para el ganador\n\n'
                    '✅ 10% para el gas de la blockchain y el fee del Desarrollador\n\n'
                    '✅ Premios distribuidos automáticamente por contrato inteligente\n\n'
                    '✅ Si ganas, recibes el pago directamente en tu dirección\n\n',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),

              const SizedBox(height: 10),
              const Text(
                '⏳ Temporizadores:\n',
                style: TextStyle(color: Colors.yellow, fontSize: 16),
              ),
              const Text(
                    '✅ El primero y el segundo de 1 minuto con sus animaciones, son para dar un tiempo de confirmación de la red\n\n',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),

              const SizedBox(height: 10),
              const Text(
                '⚠️ Advertencias:\n',
                style: TextStyle(color: Colors.yellow, fontSize: 16),
              ),
              const Text(
                    '✅ Huevobit NO almacena tu frase ni tu clave privada en servidores ni en ningún sitio, todo es local\n\n'
                    '✅ Las transacciones en blockchain son irreversibles\n\n'
                    '✅ Debes guardar tu frase de recuperación para acceder a tus fondos fuera de la app\n\n'
                    '⚠️ No hay reembolsos ni reclamos de ningún tipo.\n\n',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Entendido',
              style: TextStyle(color: Colors.yellow),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.yellow, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
}