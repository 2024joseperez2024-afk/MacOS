import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'package:huevobit/widgets/footer.dart';
import 'package:lottie/lottie.dart';
import 'nido.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🐣 Pantalla de Incubadora.
///
/// FLUJO:
///
/// 1. Consulta automática de participantes cada 30 segundos.
/// 2. Al llenarse la canasta se detiene el polling de participantes.
/// 3. Comienza:
///      - 1 minuto: enviando huevos.
///      - 1 minuto: abriendo huevo.
/// 4. El listener GanadorDeclarado permanece activo como vía principal.
/// 5. Como respaldo, 30 segundos después de iniciar el proceso se realiza
///    una búsqueda por getLogs desde widget.bloqueEntrada.
/// 6. Si no encuentra el evento, vuelve a buscar cada 30 segundos.
/// 7. Si los temporizadores terminan y todavía no hay ganador,
///    la incubadora permanece esperando mientras continúan el listener
///    y la búsqueda de respaldo.
/// 8. La búsqueda de respaldo se detiene al encontrar el ganador
///    o al iniciar la limpieza.
/// 9. Recibido el ganador, se guarda y se muestra visualmente al instante
///    y nuevamente al final cuando terminan los temporizadores.
/// 10. Después de terminar los temporizadores y tener ganador confirmado,
///     comienza la limpieza de 10 segundos.
/// 11. Luego se regresa al Nido.
///
/// IMPORTANTE:
/// - No existen consultas manuales desde botones.
/// - No existe polling rápido del ganador.
/// - El listener sigue siendo la vía principal.
/// - getLogs es únicamente un respaldo que comienza después de 30 segundos.
/// - Si el ganador aún no ha sido detectado al terminar los temporizadores,
///   el respaldo continúa cada 30 segundos hasta recibirlo.
/// - Al detectarse el ganador comienza la limpieza y toda búsqueda pendiente
///   queda cancelada.
class Incubadora extends StatefulWidget {
  final String rpcUrl;
  final String contractAddress;
  final String abi;
  final int nidoId;
  final int canastaId;
  final int assignedNumber;
  final int bloqueEntrada;

  const Incubadora({
    super.key,
    required this.rpcUrl,
    required this.contractAddress,
    required this.abi,
    required this.nidoId,
    required this.canastaId,
    required this.assignedNumber,
    required this.bloqueEntrada,
  });

  @override
  State<Incubadora> createState() => _Incubadora();
}

class _Incubadora extends State<Incubadora> {
  late Web3Client ethClient;
  late DeployedContract contract;

  int? numeroAsignado;

  Duration restante = const Duration(minutes: 1);

  int participantesCount = 0;

  /// Segundos restantes para la próxima consulta automática
  /// de participantes.
  int restantePollingParticipantes = 30;

  int restanteLimpiando = 10;

  bool _mostrarMensajeBienvenida = true;
  bool _noMostrarMas = false;

  String ganadorDireccion = '';
  int ganadorNumero = 0;

  bool mostrandoGanador = false;

  /// Indica que el proceso de temporizadores ya comenzó.
  bool _procesoIniciado = false;

  /// Indica que el polling de participantes sigue activo.
  bool _pollingActivo = false;

  bool _enviandoHuevos = false;
  bool _abriendoHuevo = false;

  /// Indica que ya comenzó la limpieza final.
  ///
  /// Cuando es true:
  /// - no se aceptan resultados tardíos;
  /// - no se inicia ninguna nueva fase;
  /// - se cancela la búsqueda de respaldo;
  /// - se ignoran eventos posteriores.
  bool _cicloTerminado = false;

  /// Indica que los dos temporizadores principales ya terminaron.
  bool _temporizadoresFinalizados = false;

  /// Indica que el ganador fue detectado por alguna de las dos vías:
  /// listener o búsqueda de respaldo.
  bool _ganadorDetectado = false;

  Timer? _timer;

  Timer? _limpiezaTimer;

  Timer? _pollingTimer;

  /// Timer visual del contador de 30 segundos de participantes.
  Timer? _contadorPollingTimer;

  /// Timer de búsqueda de respaldo del ganador.
  Timer? _busquedaGanadorTimer;

  /// Timer que espera los primeros 30 segundos antes de la primera
  /// búsqueda de respaldo.
  Timer? _esperaPrimeraBusquedaTimer;

  final List<StreamSubscription> _subs = [];

  final ScrollController _scrollController = ScrollController();

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _cargarPreferenciaMensaje();

    ethClient = Web3Client(
      widget.rpcUrl,
      Client(),
    );

    numeroAsignado = widget.assignedNumber;

    _mostrarMensajeBienvenida = true;

    _initContract().then((_) async {
      if (!mounted) return;

      await _actualizarContadorParticipantes();

      if (!mounted) return;

      if (!_procesoIniciado) {
        _iniciarPollingParticipantes();
      }

      _listenEvents();
    });
  }

  // ---------------------------------------------------------------------------
  // PREFERENCIA MENSAJE BIENVENIDA
  // ---------------------------------------------------------------------------

  Future<void> _cargarPreferenciaMensaje() async {
    final prefs = await SharedPreferences.getInstance();

    final noMostrar =
        prefs.getBool('noMostrarMensajeBienvenida') ?? false;

    if (!mounted) return;

    setState(() {
      _mostrarMensajeBienvenida = !noMostrar;
      _noMostrarMas = noMostrar;
    });
  }

  Future<void> _guardarPreferenciaMensaje(bool valor) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'noMostrarMensajeBienvenida',
      valor,
    );
  }

  // ---------------------------------------------------------------------------
  // CONTADOR PARTICIPANTES
  // ---------------------------------------------------------------------------

  /// Consulta jugadoresEnCanasta().
  ///
  /// Esta consulta solamente se utiliza para conocer la cantidad de participantes. El intervalo automático es de 30 segundos.
  Future<void> _actualizarContadorParticipantes() async {
    if (_cicloTerminado || _procesoIniciado) return;

    try {
      final resultCount = await _callWithRetry(
            () => ethClient.call(
          contract: contract,
          function: contract.function('jugadoresEnCanasta'),
          params: [
            BigInt.from(widget.nidoId),
            BigInt.from(widget.canastaId),
          ],
        ),
        operationName: 'Obtener contador participantes',
        maxRetries: 2,
      );

      if (!mounted || _cicloTerminado || _procesoIniciado) return;

      final int count = (resultCount[0] as BigInt).toInt();

      setState(() {
        participantesCount = count;
      });

      if (count >= 10) {
        _detenerPollingParticipantes();

        if (!_procesoIniciado) {
          _iniciarFaseEnviandoHuevos();
        }
      } else {
        _pollingActivo = true;
      }
    } catch (e) {
      // Error puntual del RPC.
      //
      // No se hace otra consulta inmediatamente.
      // Se espera al siguiente ciclo de 30 segundos.
    }
  }

  /// Inicia el polling automático de participantes cada 30 segundos.
  void _iniciarPollingParticipantes() {
    _detenerPollingParticipantes();

    if (_cicloTerminado || _procesoIniciado) return;

    _pollingActivo = true;

    _iniciarContadorVisualPolling();

    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
          (timer) async {
        if (!mounted ||
            !_pollingActivo ||
            _cicloTerminado ||
            _procesoIniciado) {
          timer.cancel();
          return;
        }

        _reiniciarContadorVisualPolling();

        try {
          final resultCount = await _callWithRetry(
                () => ethClient.call(
              contract: contract,
              function: contract.function('jugadoresEnCanasta'),
              params: [
                BigInt.from(widget.nidoId),
                BigInt.from(widget.canastaId),
              ],
            ),
            operationName: 'Obtener participantes',
            maxRetries: 2,
          );

          if (!mounted ||
              _cicloTerminado ||
              _procesoIniciado) {
            timer.cancel();
            return;
          }

          final int count = (resultCount[0] as BigInt).toInt();

          setState(() {
            participantesCount = count;
          });

          if (count >= 10) {
            _detenerPollingParticipantes();

            if (!_procesoIniciado) {
              _iniciarFaseEnviandoHuevos();
            }
          }
        } catch (e) {
          // No se reintenta inmediatamente.
          // El próximo ciclo será dentro de 30 segundos.
        }
      },
    );
  }

  /// Detiene todo lo relacionado con el polling de participantes.
  void _detenerPollingParticipantes() {
    _pollingActivo = false;

    _pollingTimer?.cancel();
    _pollingTimer = null;

    _contadorPollingTimer?.cancel();
    _contadorPollingTimer = null;

    if (mounted && !_cicloTerminado) {
      setState(() {
        restantePollingParticipantes = 0;
      });
    }
  }

  /// Contador visual de los 30 segundos restantes para la próxima consulta.
  void _iniciarContadorVisualPolling() {
    _contadorPollingTimer?.cancel();

    if (!_pollingActivo ||
        _cicloTerminado ||
        _procesoIniciado) {
      return;
    }

    if (mounted) {
      setState(() {
        restantePollingParticipantes = 30;
      });
    }

    _contadorPollingTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted ||
            !_pollingActivo ||
            _cicloTerminado ||
            _procesoIniciado) {
          timer.cancel();
          return;
        }

        setState(() {
          if (restantePollingParticipantes > 0) {
            restantePollingParticipantes--;
          }
        });
      },
    );
  }

  void _reiniciarContadorVisualPolling() {
    if (!mounted ||
        !_pollingActivo ||
        _cicloTerminado ||
        _procesoIniciado) {
      return;
    }

    setState(() {
      restantePollingParticipantes = 30;
    });
  }

  // ---------------------------------------------------------------------------
  // CONTRATO
  // ---------------------------------------------------------------------------

  Future<void> _initContract() async {
    contract = DeployedContract(
      ContractAbi.fromJson(widget.abi, 'Huevobit'),
      EthereumAddress.fromHex(widget.contractAddress),
    );
  }

  // ---------------------------------------------------------------------------
  // LISTENER GANADOR
  // ---------------------------------------------------------------------------

  /// Listener principal del ganador.
  ///
  /// No hace polling.
  /// No inicia búsquedas.
  /// No altera los temporizadores.
  /// Solamente captura GanadorDeclarado.
  void _listenEvents() {
    final evGanadorDeclarado =
    contract.event('GanadorDeclarado');

    _subs.add(
      ethClient
          .events(
        FilterOptions.events(
          contract: contract,
          event: evGanadorDeclarado,
        ),
      )
          .listen((event) {
        try {
          if (_cicloTerminado) return;

          if (event.topics == null ||
              event.topics!.length < 4 ||
              event.data == null) {
            return;
          }

          final nidoIdEvent = BigInt.parse(
            event.topics![1]!.replaceFirst('0x', ''),
            radix: 16,
          );

          final canastaIdEvent = BigInt.parse(
            event.topics![2]!.replaceFirst('0x', ''),
            radix: 16,
          );

          if (nidoIdEvent != BigInt.from(widget.nidoId) ||
              canastaIdEvent != BigInt.from(widget.canastaId)) {
            return;
          }

          final ganadorAddr = EthereumAddress.fromHex(
            '0x${event.topics![3]!.substring(26)}',
          );

          final numeroGanador = BigInt.parse(
            event.data!.replaceFirst('0x', ''),
            radix: 16,
          ).toInt();

          if (numeroGanador <= 0) return;

          _registrarGanador(
            ganadorAddr.hex,
            numeroGanador,
          );
        } catch (e) {
          // Listener pasivo.
          // Se ignoran errores de eventos individuales.
        }
      }),
    );
  }

  /// Guarda el ganador sin adelantar ni modificar los temporizadores.
  void _registrarGanador(
      String direccion,
      int numero,
      ) {
    if (!mounted || _cicloTerminado) return;

    setState(() {
      ganadorDireccion = direccion;
      ganadorNumero = numero;
      _ganadorDetectado = true;
    });

    // Una vez que ya tenemos el ganador, el respaldo por getLogs
    // deja de ser necesario.
    _detenerBusquedaGanador();

    if (_temporizadoresFinalizados &&
        !_cicloTerminado) {
      _mostrarGanadorYLimpiar();
    }
  }

  // ---------------------------------------------------------------------------
  // FASE 1: ENVIANDO HUEVOS
  // ---------------------------------------------------------------------------

  void _iniciarFaseEnviandoHuevos() {
    if (!mounted || _cicloTerminado) return;

    _timer?.cancel();

    _procesoIniciado = true;

    // El polling de participantes deja de existir desde este momento.
    _detenerPollingParticipantes();

    setState(() {
      restante = const Duration(minutes: 1);

      _enviandoHuevos = true;
      _abriendoHuevo = false;

      mostrandoGanador = false;
    });

    // El respaldo de GanadorDeclarado comienza DESPUÉS de 30 segundos.
    _iniciarRespaldoBusquedaGanador();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted || _cicloTerminado) {
          timer.cancel();
          return;
        }

        setState(() {
          final newSeconds = restante.inSeconds - 1;

          restante = Duration(
            seconds: newSeconds > 0 ? newSeconds : 0,
          );
        });

        if (restante.inSeconds <= 0) {
          timer.cancel();

          if (!_cicloTerminado) {
            _iniciarFaseAbriendoHuevo();
          }
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FASE 2: ABRIENDO HUEVO
  // ---------------------------------------------------------------------------

  void _iniciarFaseAbriendoHuevo() {
    if (!mounted || _cicloTerminado) return;

    _timer?.cancel();

    setState(() {
      restante = const Duration(minutes: 1);

      _enviandoHuevos = false;
      _abriendoHuevo = true;
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted || _cicloTerminado) {
          timer.cancel();
          return;
        }

        setState(() {
          final newSeconds = restante.inSeconds - 1;

          restante = Duration(
            seconds: newSeconds > 0 ? newSeconds : 0,
          );
        });

        if (restante.inSeconds <= 0) {
          timer.cancel();

          if (!_cicloTerminado) {
            _finalizarTemporizadores();
          }
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BÚSQUEDA DE RESPALDO DEL GANADOR
  // ---------------------------------------------------------------------------

  /// Inicia el mecanismo de respaldo.
  ///
  /// Primera búsqueda: después de 30 segundos.
  ///
  /// Siguientes búsquedas: cada 30 segundos.
  ///
  /// No utiliza Timer.periodic para realizar llamadas concurrentes:
  /// cada búsqueda termina antes de programar la siguiente.
  void _iniciarRespaldoBusquedaGanador() {
    _detenerBusquedaGanador();

    if (_cicloTerminado ||
        _ganadorDetectado) {
      return;
    }

    _esperaPrimeraBusquedaTimer = Timer(
      const Duration(seconds: 30),
          () async {
        if (!mounted ||
            _cicloTerminado ||
            _ganadorDetectado) {
          return;
        }

        await _ejecutarBusquedaRespaldo();
      },
    );
  }

  /// Ejecuta una búsqueda de respaldo.
  ///
  /// Si no encuentra el evento, programa otra para 30 segundos después.
  Future<void> _ejecutarBusquedaRespaldo() async {
    if (!mounted ||
        _cicloTerminado ||
        _ganadorDetectado) {
      return;
    }

    final encontrado =
    await _buscarGanadorDeclarado();

    if (!mounted ||
        _cicloTerminado ||
        _ganadorDetectado) {
      return;
    }

    if (encontrado) {
      return;
    }

    // Esperar otros 30 segundos antes de volver a consultar.
    _busquedaGanadorTimer = Timer(
      const Duration(seconds: 30),
          () async {
        if (!mounted ||
            _cicloTerminado ||
            _ganadorDetectado) {
          return;
        }

        await _ejecutarBusquedaRespaldo();
      },
    );
  }

  /// Busca GanadorDeclarado desde el bloque de entrada.
  ///
  /// Esta es la única función que consulta los logs como respaldo.
  Future<bool> _buscarGanadorDeclarado() async {
    if (_cicloTerminado ||
        _ganadorDetectado) {
      return false;
    }

    try {
      final eventoGanador =
      contract.event('GanadorDeclarado');

      final eventosGanador = await ethClient.getLogs(
        FilterOptions.events(
          contract: contract,
          event: eventoGanador,
          fromBlock: BlockNum.exact(
            widget.bloqueEntrada,
          ),
        ),
      );

      if (!mounted ||
          _cicloTerminado ||
          _ganadorDetectado) {
        return false;
      }

      // El evento más nuevo primero.
      for (final event in eventosGanador.reversed) {
        if (event.topics == null ||
            event.topics!.length < 4 ||
            event.data == null) {
          continue;
        }

        final nidoIdEvent = BigInt.parse(
          event.topics![1]!.replaceFirst('0x', ''),
          radix: 16,
        );

        final canastaIdEvent = BigInt.parse(
          event.topics![2]!.replaceFirst('0x', ''),
          radix: 16,
        );

        if (nidoIdEvent != BigInt.from(widget.nidoId) ||
            canastaIdEvent != BigInt.from(widget.canastaId)) {
          continue;
        }

        final ganadorAddr = EthereumAddress.fromHex(
          '0x${event.topics![3]!.substring(26)}',
        );

        final numeroGanador = BigInt.parse(
          event.data!.replaceFirst('0x', ''),
          radix: 16,
        ).toInt();

        if (numeroGanador <= 0) {
          continue;
        }

        if (!mounted ||
            _cicloTerminado) {
          return false;
        }

        _registrarGanador(
          ganadorAddr.hex,
          numeroGanador,
        );

        return true;
      }

      return false;
    } catch (e) {
      // Si falla el RPC, no se hace una segunda consulta inmediatamente.
      // El siguiente intento será después de 30 segundos.
      return false;
    }
  }

  /// Detiene por completo el mecanismo de búsqueda de respaldo.
  void _detenerBusquedaGanador() {
    _esperaPrimeraBusquedaTimer?.cancel();
    _esperaPrimeraBusquedaTimer = null;

    _busquedaGanadorTimer?.cancel();
    _busquedaGanadorTimer = null;
  }

  // ---------------------------------------------------------------------------
  // FINAL DE TEMPORIZADORES
  // ---------------------------------------------------------------------------

  /// Los dos temporizadores terminaron.
  ///
  /// Si ya tenemos ganador -> mostrar y limpiar.
  ///
  /// Si todavía no lo tenemos -> mostrar "Esperando evento del ganador".
  /// La búsqueda de respaldo continúa cada 30 segundos.
  void _finalizarTemporizadores() {
    if (!mounted || _cicloTerminado) return;

    _timer?.cancel();

    _temporizadoresFinalizados = true;

    setState(() {
      _enviandoHuevos = false;
      _abriendoHuevo = false;

      restante = Duration.zero;
    });

    if (_ganadorDetectado &&
        ganadorNumero > 0 &&
        ganadorDireccion.isNotEmpty) {
      _mostrarGanadorYLimpiar();
      return;
    }

    // Todavía no llegó el evento.
    //
    // NO iniciamos la limpieza todavía.
    // La pantalla queda esperando mientras el listener y el respaldo
    // continúan buscando el ganador.
    setState(() {
      mostrandoGanador = false;
    });
  }

  // ---------------------------------------------------------------------------
  // MOSTRAR GANADOR Y LIMPIEZA
  // ---------------------------------------------------------------------------

  void _mostrarGanadorYLimpiar() {
    if (!mounted || _cicloTerminado) return;

    if (!_ganadorDetectado ||
        ganadorNumero <= 0 ||
        ganadorDireccion.isEmpty) {
      return;
    }

    _detenerBusquedaGanador();

    setState(() {
      mostrandoGanador = true;

      _enviandoHuevos = false;
      _abriendoHuevo = false;

      restante = Duration.zero;
    });

    _iniciarLimpieza();
  }

  // ---------------------------------------------------------------------------
  // LIMPIEZA
  // ---------------------------------------------------------------------------

  /// La limpieza solamente empieza después de tener el ganador.
  ///
  /// En este punto se marca inmediatamente el ciclo como terminado.
  /// Esto evita que cualquier evento o RPC tardío pueda modificar
  /// nuevamente la pantalla.
  void _iniciarLimpieza() {
    if (!mounted || _cicloTerminado) return;

    _cicloTerminado = true;

    _pollingActivo = false;

    _pollingTimer?.cancel();
    _pollingTimer = null;

    _contadorPollingTimer?.cancel();
    _contadorPollingTimer = null;

    _timer?.cancel();

    _detenerBusquedaGanador();

    _limpiezaTimer?.cancel();

    restanteLimpiando = 10;

    setState(() {});

    _limpiezaTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          restanteLimpiando--;
        });

        if (restanteLimpiando <= 0) {
          timer.cancel();

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const NidoScreen(),
            ),
                (Route<dynamic> route) => false,
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RETRY RPC
  // ---------------------------------------------------------------------------

  Future<T> _callWithRetry<T>(
      Future<T> Function() rpcCall, {
        String operationName = 'Operación RPC',
        int maxRetries = 3,
      }) async {
    int attempt = 0;

    while (true) {
      try {
        attempt++;

        return await rpcCall();
      } catch (e) {
        if (attempt >= maxRetries) {
          rethrow;
        }

        await Future.delayed(
          Duration(seconds: 2 * attempt),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UTILIDADES
  // ---------------------------------------------------------------------------

  String _short(String address) {
    if (address.length <= 10) {
      return address;
    }

    return '${address.substring(0, 6)}...'
        '${address.substring(address.length - 4)}';
  }

  String _formatDurationHMS(Duration d) {
    final m = d.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    final s = d.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return '$m:$s';
  }

  // ---------------------------------------------------------------------------
  // ANIMACIÓN
  // ---------------------------------------------------------------------------

  Widget _buildAnimacionLottie() {
    String assetPath =
        'assets/animations/incubadora.json';

    if (_abriendoHuevo) {
      assetPath =
      'assets/animations/abriendo_huevo.json';
    }

    return SizedBox(
      height: 300,
      width: 300,
      child: Lottie.asset(
        assetPath,
        repeat: true,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _limpiezaTimer?.cancel();
    _pollingTimer?.cancel();
    _contadorPollingTimer?.cancel();
    _busquedaGanadorTimer?.cancel();
    _esperaPrimeraBusquedaTimer?.cancel();

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();

    _scrollController.dispose();
    ethClient.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final double appBarTopPadding =
        MediaQuery.of(context).padding.top + 5;

    final tiempo = _formatDurationHMS(restante);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final nav = Navigator.of(context);

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('¿Quieres salir?'),
            content: const Text(
              'No pasa nada, ya estás participando.\n\n',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(true),
                child: const Text(
                  'Salir',
                  style: TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          nav.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const NidoScreen(),
            ),
                (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            AppBar(
              backgroundColor: Colors.black,
              centerTitle: true,
              toolbarHeight: 150,
              title: Padding(
                padding: EdgeInsets.only(
                  top: appBarTopPadding,
                  bottom: 10.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🥚 Huevobit 🥚',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Nido ${widget.nidoId} - Canasta ${widget.canastaId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: Stack(
                children: [
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      children: [
                        const SizedBox(height: 12),

                        // -----------------------------------------------------
                        // ESTADO PRINCIPAL
                        // -----------------------------------------------------

                        if (_enviandoHuevos)
                          Column(
                            children: [
                              Text(
                                '⏱️ Cargando huevos en la incubadora: $tiempo',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),

                              Container(
                                margin:
                                const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                padding:
                                const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                  const Color(0x1AFFFF00),
                                  border: Border.all(
                                    color: Colors.yellow,
                                  ),
                                  borderRadius:
                                  BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.yellow,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Sorteo seguro, íntegro e inmutable con el Sistema VRF de un Oráculo. Revisa el contrato en la blockchain.',
                                        style:
                                        const TextStyle(
                                          color:
                                          Color(0xFFB7950B),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              _buildAnimacionLottie(),
                            ],
                          )
                        else if (_abriendoHuevo)
                          Column(
                            children: [
                              Text(
                                '🕵️ Buscando huevo ganador: $tiempo',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              _buildAnimacionLottie(),
                            ],
                          )
                        else if (mostrandoGanador)
                            const Text(
                              '🙏 ¡Gracias por participar!',
                              style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            )
                          else if (_temporizadoresFinalizados &&
                                !_ganadorDetectado)
                              Column(
                                children: [
                                  const SizedBox(height: 5),

                                  const Icon(
                                    Icons.hourglass_empty,
                                    color: Colors.orange,
                                    size: 42,
                                  ),

                                  const SizedBox(height: 10),

                                  const Text(
                                    '⏳ Esperando evento del ganador...',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 8),

                                  const Text(
                                    'La blockchain todavía no ha reflejado el evento en el nodo.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.groups,
                                        color: Colors.yellow,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Participantes $participantesCount/10',
                                        style: const TextStyle(
                                          color: Colors.yellow,
                                          fontSize: 20,
                                          fontWeight:
                                          FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 30),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text('Información importante'),
                                              content: const SingleChildScrollView(
                                                child: Text(
                                                  '✅ Cuando el contador de participantes se llene, '
                                                      'comienza el proceso del sorteo. Los temporizadores dan '
                                                      'tiempo a la Blockchain para procesar las operaciones.\n\n'

                                                      '✅ El ganador se detecta automáticamente mediante el '
                                                      'evento de la Blockchain. La información de espera cambia cuando llega el ganador.\n\n'

                                                      '🔄 Como respaldo, la aplicación realiza consultas '
                                                      'periódicas por si el evento todavía no ha sido recibido por tu RPC. '
                                                      'Estas consultas están limitadas para evitar sobrecargar '
                                                      'el nodo.\n\n'

                                                      '⚠️ Si tu dispositivo tarda unos segundos más que otros '
                                                      'en mostrar el ganador, no significa que haya un problema. '
                                                      'Cada dispositivo depende de la respuesta de su propio '
                                                      'RPC y de la congestión de la red.\n\n'

                                                      '🔒 La Blockchain y el contrato son la fuente de verdad '
                                                      'del sorteo.',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.justify,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                                  child: const Text('Cerrar'),
                                                ),
                                              ],
                                              backgroundColor: Colors.black,
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.info_outline,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Mostrar información importante',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 15),

                                  if (restantePollingParticipantes >
                                      0 &&
                                      _pollingActivo)
                                    Padding(
                                      padding:
                                      const EdgeInsets.only(
                                        top: 8,
                                      ),
                                      child: Text(
                                        'Próxima actualización en ${restantePollingParticipantes}s',
                                        style:
                                        const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                        const SizedBox(height: 30),

                        // -----------------------------------------------------
                        // ESTADO DEL GANADOR
                        // -----------------------------------------------------

                        if (_procesoIniciado &&
                            !mostrandoGanador)
                          _buildEstadoGanador(),

                        const SizedBox(height: 30),

                        // -----------------------------------------------------
                        // MI HUEVO
                        // -----------------------------------------------------

                        if (!mostrandoGanador)
                          _buildMiHuevo(),

                        const SizedBox(height: 30),

                        // -----------------------------------------------------
                        // GANADOR
                        // -----------------------------------------------------

                        if (mostrandoGanador)
                          _buildGanadorDestacado(),

                        if (mostrandoGanador)
                          _buildLimpiandoIncubadora(),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // -----------------------------------------------------------
                  // MENSAJE DE BIENVENIDA
                  // -----------------------------------------------------------

                  if (_mostrarMensajeBienvenida &&
                      !_noMostrarMas)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: Center(
                          child: Container(
                            width:
                            MediaQuery.of(context)
                                .size
                                .width *
                                0.8,
                            padding:
                            const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius:
                              BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.yellow,
                                width: 2,
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize:
                                MainAxisSize.min,
                                children: [
                                  const Text(
                                    '⚠️ ¡Ya estás participando!',
                                    style: TextStyle(
                                      color: Colors.yellow,
                                      fontSize: 20,
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                    textAlign:
                                    TextAlign.center,
                                  ),

                                  const SizedBox(height: 15),

                                  const Text(
                                    'Ya estás participando aunque salgas de la App. Lee la información importante del botón ante cualquier duda.\n\n'
                                        'Cuando se llene la canasta inician los temporizadores para dar oportunidad a la Blockchain.\n\n',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    textAlign:
                                    TextAlign.justify,
                                  ),

                                  CheckboxListTile(
                                    value: _noMostrarMas,
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }

                                      setState(() {
                                        _noMostrarMas =
                                            value;
                                      });
                                    },
                                    title: const Text(
                                      'No volver a mostrar',
                                      style: TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    controlAffinity:
                                    ListTileControlAffinity
                                        .leading,
                                    activeColor:
                                    Colors.yellow,
                                  ),

                                  const SizedBox(height: 20),

                                  ElevatedButton(
                                    onPressed: () async {
                                      await _guardarPreferenciaMensaje(
                                        _noMostrarMas,
                                      );

                                      if (!mounted) return;

                                      setState(() {
                                        _mostrarMensajeBienvenida =
                                        false;
                                      });
                                    },
                                    style:
                                    ElevatedButton.styleFrom(
                                      backgroundColor:
                                      Colors.yellow,
                                      foregroundColor:
                                      Colors.black,
                                      padding:
                                      const EdgeInsets
                                          .symmetric(
                                        horizontal: 30,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'Entendido',
                                      style: TextStyle(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ESTADO DEL GANADOR
  // ---------------------------------------------------------------------------

  Widget _buildEstadoGanador() {
    if (_ganadorDetectado &&
        ganadorNumero > 0 &&
        ganadorDireccion.isNotEmpty) {
      return Column(
        children: [
          const Icon(
            Icons.emoji_events,
            color: Colors.yellow,
            size: 42,
          ),
          const SizedBox(height: 8),
          Text(
            'El ganador fue el Nº $ganadorNumero',
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _short(ganadorDireccion),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return const Column(
      children: [
        Icon(
          Icons.hourglass_empty,
          color: Colors.orange,
          size: 40,
        ),
        SizedBox(height: 8),
        Text(
          '⏳ Esperando evento del ganador...',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // GANADOR DESTACADO
  // ---------------------------------------------------------------------------

  Widget _buildGanadorDestacado() {
    return Column(
      children: [
        const Text(
          '🏆 GANADOR',
          style: TextStyle(
            color: Colors.yellow,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 20),

        Container(
          width: 180,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(90),
            border: Border.all(
              color: Colors.yellow,
              width: 4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08FFFFFF),
                blurRadius: 15,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Text(
                '$ganadorNumero',
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _short(ganadorDireccion),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                '¡FELICIDADES!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // LIMPIANDO
  // ---------------------------------------------------------------------------

  Widget _buildLimpiandoIncubadora() {
    return Column(
      children: [
        const SizedBox(height: 20),

        const Icon(
          Icons.clean_hands,
          color: Colors.grey,
          size: 50,
        ),

        const SizedBox(height: 10),

        const Text(
          '🧹 Limpiando incubadora...',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 18,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Saliendo en $restanteLimpiando segundos',
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MI HUEVO
  // ---------------------------------------------------------------------------

  Widget _buildMiHuevo() {
    return Column(
      children: [
        const Text(
          '🎯 TU NÚMERO',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 15),

        Container(
          width: 140,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(80),
            border: Border.all(
              color: Colors.blue,
              width: 3,
            ),
          ),
          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Text(
                '$numeroAsignado',
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 72,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(2, 2),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        const Footer(),

        const SizedBox(height: 10),
      ],
    );
  }
}