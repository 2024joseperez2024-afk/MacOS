import 'package:flutter/material.dart';
import 'package:huevobit/widgets/footer.dart';
import 'package:huevobit/resources/terminos.dart';
import 'package:huevobit/screens/nido.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

// 🎯 Punto de entrada principal de la aplicación Flutter
// Se asegura de inicializar correctamente los bindings y muestra la app con soporte para notificaciones tipo overlay.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(450, 750),
      minimumSize: Size(380, 500),
      center: true,
      title: 'Huevobit 2.1',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    OverlaySupport.global(
      child: const HuevobitApp(),
    ),
  );
}

// Widget raíz de la aplicación Huevobit.
// Configura el tema global y establece la pantalla inicial.
class HuevobitApp extends StatelessWidget {
  const HuevobitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 🌑 Tema oscuro personalizado con colores dominantes del juego
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.yellow,
          secondary: Colors.white,
          surface: Colors.black,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false, // 🚫 Oculta el banner de debug
    );
  }
}

// 🏠 Pantalla inicial (HomeScreen)
// Muestra el título, descripción del juego y gestión de términos y condiciones.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool termsAccepted = false; // ✅ Controla si el usuario aceptó los términos

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20.0, 40.0, 20.0, 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  // Título y subtítulos del juego
                  Text(
                    '🥚 Huevobit 🥚',
                    style: TextStyle(
                      color: Colors.yellow,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '🎮 ¡Juego Blockchain Descentralizado!\n🏆 ¡90% para el ganador!\n¡¡Dale huevo!!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 17),
                  )
                ],
              ),
              const SizedBox(height: 100),

              // 🎮 Sección principal de interacción (entrar / aceptar términos)
              Column(
                children: [
                  // 🚪 Botón para entrar al juego
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 140,
                      maxWidth: 250,
                      minHeight: 50,
                    ),
                    child: ElevatedButton(
                      onPressed: termsAccepted
                          ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => NidoScreen()),
                        );
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: termsAccepted ? Colors.yellow : Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Entrar al juego',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ☑️ Checkbox de aceptación de términos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: termsAccepted,
                        onChanged: (bool? value) {
                          setState(() {
                            termsAccepted = value ?? false;
                          });
                        },
                        fillColor: WidgetStateProperty.resolveWith<Color>(
                              (Set<WidgetState> states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.yellow;
                            }
                            return Colors.white;
                          },
                        ),
                      ),
                      const Text(
                        'Acepto los Términos y Condiciones',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),

                  // 🧾 Texto dinámico de retroalimentación
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      termsAccepted
                          ? '✅ Términos aceptados. Ya puedes entrar al juego.'
                          : 'Debes aceptar los Términos y Condiciones para poder jugar',
                      style: TextStyle(
                        color: termsAccepted ? Colors.green : Colors.yellow,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 📜 Botón para ver los Términos y Condiciones
                  OutlinedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const TerminosDialog(),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      fixedSize: const Size(250, 50),),
                    child: const Text('Ver Términos y Condiciones'),
                  ),
                ],
              ),

              // 👣 Footer con créditos o enlaces
              const SizedBox(height: 120),
              const Padding(
                padding: EdgeInsets.only(bottom: 10.0),
                child: Footer(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}