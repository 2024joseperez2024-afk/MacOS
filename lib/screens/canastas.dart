import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:huevobit/widgets/footer.dart';
import 'incubadora.dart';

/// 🎮 Pantalla principal de las canastas del juego Huevobit.
/// Desde aquí los jugadores seleccionan y entran a canastas de su Nido.
/// Gestiona interacciones on-chain (entrada, verificación, y transacción).
class CanastasScreen extends StatefulWidget {
  final String rpcUrl;
  final String contractAddress;
  final String abi;
  final String userAddress;
  final int idNido;
  final String idUsuario;
  final String firmaId;
  final String hashPago;
  final int chainId;

  // 🧩 Recibe toda la configuración necesaria para conectarse a la blockchain:
  // rpcUrl, contrato, ABI, dirección del usuario, ID del nido, hash de pago y firma.
  const CanastasScreen({
    super.key,
    required this.rpcUrl,
    required this.contractAddress,
    required this.abi,
    required this.userAddress,
    required this.idNido,
    required this.idUsuario,
    required this.firmaId,
    required this.hashPago,
    required this.chainId
  });

  @override
  State<CanastasScreen> createState() => _CanastasScreenState();
}

// 🔐 Estado interno de la pantalla de canastas:
// - Maneja conexión al contrato Web3.
// - Carga las credenciales seguras.
// - Controla los temporizadores y estados visuales de las canastas.
class _CanastasScreenState extends State<CanastasScreen> {

  late Web3Client ethClient;
  late DeployedContract contract;
  late EthPrivateKey _credentials;
  final ScrollController _scrollController = ScrollController();
  bool _mostrarMensajeBienvenida = true;
  bool _noMostrarMensajeBienvenida = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
  mOptions: MacOsOptions(
    usesDataProtectionKeychain: false,
  ),
);
  final Map<int, int> _participantesPorCanasta = {};
  final Map<int, String> _estadosPorCanasta = {};
  double? balance;
  Timer? _balanceTimer;

  // 🚀 Inicializa la conexión Web3, carga contrato y credenciales seguras.
  @override
  void initState() {
    super.initState();
    ethClient = Web3Client(widget.rpcUrl, http.Client());
    _initContract();
    _loadCredentials();
    _cargarPreferenciaMensajeBienvenida();
    _fetchBalance();
    _startBalanceAutoRefresh();
  }

  // 💰 Obtiene el balance actual del usuario en BNB desde el nodo RPC.
  Future<void> _fetchBalance() async {
    try {
      final bal = await ethClient.getBalance(
          EthereumAddress.fromHex(widget.userAddress));
      if (!mounted) return;
      setState(() {
        balance = bal.getValueInUnit(EtherUnit.ether);
      });
    } catch (e) {
      'Error al obtener el balance de la dirección ${widget.userAddress}: $e';
    }
  }

  // 🔄 Actualiza automáticamente el balance cada 60 segundos.
  void _startBalanceAutoRefresh() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
      } else {
        _fetchBalance();
      }
    });
  }

  Future<void> _cargarPreferenciaMensajeBienvenida() async {
    final valor = await _secureStorage.read(
      key: 'noMostrarMensajeBienvenida',
    );

    if (!mounted) return;

    setState(() {
      _noMostrarMensajeBienvenida = valor == 'true';
      _mostrarMensajeBienvenida = !_noMostrarMensajeBienvenida;
    });
  }

  // 📄 Inicializa la instancia del contrato inteligente usando la ABI y la dirección recibidas.
  // Esto permite llamar sus funciones desde Dart.
  Future<void> _initContract() async {
    contract = DeployedContract(
      ContractAbi.fromJson(widget.abi, "Huevobit"),
      EthereumAddress.fromHex(widget.contractAddress),
    );
  }

  // 🔑 Carga la clave privada desde almacenamiento seguro y crea las credenciales Web3.
  // Si no existen o hay error, lanza excepción informativa.
  Future<void> _loadCredentials() async {
    try {
      final pk = await _secureStorage.read(key: 'privateKey');
      if (pk == null || pk.isEmpty) {
        throw Exception('No hay privateKey en Secure Storage');
      }
      _credentials = EthPrivateKey.fromHex(pk);
    } catch (e) {
      throw Exception(
          'No se pudieron cargar las credenciales. Por favor, inténtalo nuevamente.'
      );
    }
  }

  ///    Lógica completa para entrar a una canasta del Nido.
  /// 1️⃣ Verifica si el jugador ya participó.
  /// 2️⃣ Muestra diálogos informativos y loaders.
  /// 3️⃣ Estima gas, prepara y envía la transacción al contrato.
  /// 4️⃣ Espera número asignado y redirige a la pantalla de incubadora.
  ///
  /// Maneja de forma segura y amigable los errores comunes:
  /// - Falta de gas o saldo
  /// - Nodo saturado o conexión caída
  /// - Hash duplicado o expirado
  Future<void> _entrarCanasta(int canastaId) async {
    try {

      // 🔍 Consulta los jugadores actuales de la canasta en el contrato
      final resultJugadores = await ethClient.call(
        contract: contract,
        function: contract.function("obtenerJugadores"),
        params: [BigInt.from(widget.idNido), BigInt.from(canastaId)],
      );

      final direcciones = (resultJugadores[0] as List).map((addr) {
        if (addr is EthereumAddress) return addr;
        if (addr is String) return EthereumAddress.fromHex(addr);
        throw Exception("Tipo de dirección inesperado: $addr");
      }).toList();

      if (direcciones.any((addr) =>
      addr.hex.toLowerCase() == _credentials.address.hex.toLowerCase())) {
        await _mostrarDialogo(
          "Información",
          "Como estás participando o participaste en un sorteo anterior en esta canasta, no puedes entrar de primero; espera a que entre alguien primero o entra en otra canasta.",
          Colors.blue,
        );
        return;
      }

      // ⚠️ Si el jugador ya participó en el sorteo anterior, muestra advertencia
      // y bloquea la entrada hasta que otro entre primero.
      final participantesResult = await ethClient.call(
        contract: contract,
        function: contract.function("jugadoresEnCanasta"),
        params: [BigInt.from(widget.idNido), BigInt.from(canastaId)],
      );

      final participantesCount = participantesResult.isNotEmpty
          ? (participantesResult[0] as BigInt).toInt()
          : 0;

      // 👥 Actualiza el contador local de participantes para la canasta seleccionada.
      if (mounted) {
        setState(() {
          _participantesPorCanasta[canastaId] = participantesCount;
        });
      }
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          backgroundColor: Colors.black87,
          title: Text(
            "⏳ Verificando estado de Canasta...",
            style: TextStyle(color: Colors.yellow),
            textAlign: TextAlign.center,
          ),
          content: Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.yellow),
                SizedBox(height: 20),
                Text(
                  "Después de ver el estado, si vas a entrar espera unos 5 segundos para no saturar el Nodo.",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));

      // Cerrar el loader
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // ⏳ Muestra un diálogo mientras se verifica el estado actual de la canasta.
      // Da tiempo para que los datos on-chain se actualicen antes de permitir entrar.
      if (!mounted) return;
      final entrarConfirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Canasta $canastaId'),
          content: Text(
              'Participantes: ${_participantesPorCanasta[canastaId] ?? 0}/10\n¿Deseas entrar a esta canasta?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.red))),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Entrar', style: TextStyle(color: Colors.green))),
          ],
        ),
      );

      if (entrarConfirmado != true) return;

      // Preparar la transacción dinámicamente
      final function = contract.function("entrarCanasta");
      final firma = Uint8List.fromList(hexToBytes(widget.firmaId));

      // 🔹 Obtener gasPrice recomendado por la red
      final gasPrice = await ethClient.getGasPrice();

      final hashLimpio = widget.hashPago.trim();

      if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hashLimpio)) {
        await _mostrarDialogo(
          "Hash inválido",
          "⚠️ El Hash introducido no tiene un formato válido.\n\n"
              "Debes utilizar el HashPago generado por el contrato.",
          Colors.blue,
        );
        return;
      }

      final hashPagoBytes = hexToBytes(hashLimpio);

      final data = function.encodeCall([
        widget.idUsuario,
        firma,
        hashPagoBytes,
        BigInt.from(widget.idNido),
        BigInt.from(canastaId),
      ]);

      // 🔹 Estimar gas real para esta llamada
      final estimatedGas = await ethClient.estimateGas(
        sender: _credentials.address,
        to: contract.address,
        data: data,
      );

      // ⚙️ Construye dinámicamente la transacción con gasPrice y gasLimit calculados.
      // Añade 10% de margen para evitar fallos por fluctuación de red.
      final gasLimit = (estimatedGas * BigInt.from(11)) ~/ BigInt.from(10);

      // 🔹 Crear la transacción usando ese gas estimado
      final tx = Transaction.callContract(
        contract: contract,
        function: function,
        parameters: [
          widget.idUsuario,
          firma,
          hashPagoBytes,
          BigInt.from(widget.idNido),
          BigInt.from(canastaId),
        ],
        gasPrice: gasPrice,
        maxGas: gasLimit.toInt(),
      );

      // Mostrar inmediatamente que la entrada está siendo procesada.
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          title: Text("⏳ Procesando tu entrada..."),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "La transacción está siendo enviada a la Blockchain. "
                    "No cierres la aplicación.",
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );

      await Future.delayed(Duration(seconds: 5));

      /// 🚀 Envía la transacción a la red usando las credenciales locales.
      final txHash = await ethClient.sendTransaction(
        _credentials,
        tx,
        chainId: widget.chainId,
      );

      // Esperar hasta que la transacción quede incluida en un bloque.
      TransactionReceipt? receipt;

      final limiteReceipt =
      DateTime.now().add(const Duration(seconds: 30));

      while (DateTime.now().isBefore(limiteReceipt)) {
        receipt = await ethClient.getTransactionReceipt(txHash);

        if (receipt != null) {
          break;
        }

        await Future.delayed(const Duration(seconds: 3));
      }

      final receiptConfirmado = receipt;

      if (receiptConfirmado == null) {
        throw Exception(
          'La transacción fue enviada, pero todavía no se pudo obtener su confirmación.',
        );
      }

      if (receiptConfirmado.status != true) {
        throw Exception(
          'La transacción fue revertida en el contrato. '
              'Se cobró el gas, pero la entrada no fue registrada.',
        );
      }

      final int bloqueEntrada = receiptConfirmado.blockNumber.blockNum;
      // 🧮 Espera a que el contrato devuelva el número asignado al jugador.
      // Reintenta periódicamente hasta 30 segundos antes de desistir.
      int? assignedNumber;
      final waitUntilNumber = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(waitUntilNumber) && assignedNumber == null) {
        try {
          final result = await ethClient.call(
            contract: contract,
            function: contract.function("numeroDeJugador"),
            params: [
              _credentials.address,
              BigInt.from(widget.idNido),
              BigInt.from(canastaId),
            ],
          );
          if (result.isNotEmpty) {
            assignedNumber = (result[0] as BigInt).toInt();
          }
        } catch (_) {}
        if (assignedNumber == null) {
          await Future.delayed(const Duration(seconds: 5));
        }
      }

      if (assignedNumber == null) {
        // Cerrar el diálogo "Procesando tu entrada..."
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        await _mostrarDialogo(
          "Información",
          "El número asignado no llegó. Reintenta, puede ser el Nodo, o verifica los Eventos del contrato a ver si ya lo recibiste.",
          Colors.blue,
        );
        return;
      }

      // 🥚 Si todo salió bien, redirige a la pantalla de incubadora
      // pasando todos los datos necesarios para continuar la experiencia del jugador.
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Incubadora(
            rpcUrl: widget.rpcUrl,
            contractAddress: contract.address.hex,
            abi: widget.abi,
            nidoId: widget.idNido,
            canastaId: canastaId,
            assignedNumber: assignedNumber!,
            bloqueEntrada: bloqueEntrada,
          ),
        ),
      );
      // ⚠️ Manejo de errores detallado para casos comunes de blockchain.
      // Muestra mensajes claros al usuario dependiendo del problema.
} catch (e) {
      final msg = e.toString().toLowerCase();
      // 1️⃣ Cerrar el loader "Procesando..." antes de mostrar cualquier error
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (msg.contains('insufficient funds') ||
          msg.contains('insufficient funds for gas')) {
        await _mostrarDialogo(
          "Saldo insuficiente",
          "⛽ Tu billetera no tiene suficiente BNB para cubrir el gas de esta operación.\n\n"
              "💰 Deposita un poco más de BNB y vuelve a intentarlo.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('rate limit') ||
          msg.contains('too many requests') ||
          msg.contains('limit exceeded') ||
          msg.contains('-32005')) {
        await _mostrarDialogo(
          "RPC ocupado",
          "📡 El nodo RPC rechazó temporalmente la consulta porque alcanzó su límite de solicitudes.\n\n"
              "Tu Hash no se pierde. Espera unos segundos o cambia de RPC y vuelve a intentarlo.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('hash ya utilizado')) {
        await _mostrarDialogo(
          "Hash ya utilizado",
          "⚠️ Este Hash ya fue utilizado.\n\n"
              "Regresa al Nido para obtener un Hash disponible y realiza una nueva entrada.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('hash no corresponde al nido')) {
        await _mostrarDialogo(
          "Hash incorrecto",
          "⚠️ Este Hash no corresponde a este Nido.\n\n"
              "Regresa al Nido y utiliza el Hash correspondiente.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('hash no pertenece al remitente')) {
        await _mostrarDialogo(
          "Hash no válido",
          "⚠️ Este Hash no pertenece a esta billetera.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('firma no validada')) {
        await _mostrarDialogo(
          "Firma no válida",
          "⚠️ La firma de tu billetera no pudo ser validada por el contrato.",
          Colors.blue,
        );
        return;
      }

      if (msg.contains('connection reset') ||
          msg.contains('socketexception') ||
          msg.contains('connection closed') ||
          msg.contains('network')) {
        await _mostrarDialogo(
          "Problema de conexión:",
          "📡 No se pudo completar la comunicación con la Blockchain.\n\n"
              "⚠️ Revisa tu conexión a Internet o verifica que tu RPC está correcto.",
          Colors.blueAccent,
        );
        return;
      }
      await _mostrarDialogo(
        "Error en la operación",
        "⚠️ No se pudo completar la operación porque ocurrió un error que la aplicación no pudo identificar.\n\n"
            "🔄 Revisa las Instrucciones Rápidas, verifica tu conexión a Internet, RPC, Hash válido y tu saldo de BNB, y vuelve a intentarlo.\n\n"
            "Si el problema continúa, revisa los Eventos del contrato para comprobar si la entrada llegó a la Blockchain.",
        Colors.blue,
      );
    }
   }

  // 💬 Muestra un diálogo de alerta o información con colores personalizables.
  // Se usa en toda la clase para mostrar errores o advertencias al usuario.
  Future<void> _mostrarDialogo(String titulo, String mensaje,
      Color colorFondo) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            backgroundColor: colorFondo,
            title: Text(titulo, style: const TextStyle(color: Colors.white)),
            content: Text(mensaje, style: const TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () {
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text('Aceptar'),
              ),
            ],
          ),
    );
  }

  // 🧹 Limpia los recursos y cancela timers activos para evitar fugas de memoria.
  @override
  void dispose() {
    _balanceTimer?.cancel();
    _scrollController.dispose();
    ethClient.dispose();
    super.dispose();
  }

  /// 🖥️ Construye toda la interfaz de la pantalla de Canastas.
  /// Incluye:
  /// - AppBar personalizado.
  /// - Instrucciones y advertencias.
  /// - Cuadrícula de 20 canastas.
  /// - Mensaje inicial de seguridad.
  @override
  Widget build(BuildContext context) {
    final double appBarTopPadding = MediaQuery.of(context).padding.top + 50;
    // Altura fija estimada del contenido (título + subtítulo + fila de balance
    // + espaciados), independiente del tamaño de pantalla. Incluye un margen
    // moderado para que quepa incluso con fuentes grandes de accesibilidad,
    // sin dejar espacio vacío de más en dispositivos normales.
    const double appBarContentHeight = 140;
    final double appBarHeight = appBarTopPadding + appBarContentHeight;

    return PopScope(
      // 🔒 Intercepta el botón "Atrás" para advertir al usuario
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final navigator = Navigator.of(context);

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Quieres salir?'),
            content: const Text('Recuerda que puedes usar tu Hash más tarde si no eliminas la App ni tu billetera actual.\n\n'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Salir', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (shouldExit ?? false) {
          if (mounted) {
            navigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(appBarHeight),
          child: AppBar(
            surfaceTintColor: Colors.black,
            backgroundColor: Colors.black,
            centerTitle: true,
            automaticallyImplyLeading: true,
            titleSpacing: 1,
            flexibleSpace: Padding(
              padding: EdgeInsets.only(
                  top: appBarTopPadding, left: 12, right: 12, bottom: 8),
              child: Align(
                // ⬆️ Alinea el contenido arriba: si sobra espacio (dispositivo
                // con pantalla más alta), el hueco queda abajo en vez de
                // repartirse arriba y abajo.
                alignment: Alignment.topCenter,
                child: FittedBox(
                  // 🛡️ Red de seguridad: si en algún dispositivo el contenido
                  // sigue sin caber (fuentes grandes, pantallas muy chicas),
                  // se reduce de forma proporcional en vez de desbordar.
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('🎮🥚 Huevobit 🥚🎮',
                          style: TextStyle(color: Colors.yellow, fontSize: 26)),
                      const SizedBox(height: 15),
                      const Text('Lista de Canastas',
                          style: TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            balance != null
                                ? 'Balance: ${balance!.toStringAsFixed(4)} BNB'
                                : 'Balance: --',
                            style: const TextStyle(color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.yellow),
                            tooltip: "Refrescar Balance",
                            onPressed: _fetchBalance,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                        children: [
                          const Text('⚠️ IMPORTANTE: si la canasta se muestra en rojo y dice "Finalizado", puedes entrar, ya que, las canastas se limpian al entrar por diseño del contrato. No hay servidores para actualizar en tiempo real.\n\n',
                            style: TextStyle(color: Colors.white, fontSize: 14), textAlign: TextAlign.justify,),
                          const SizedBox(height: 3),
                          const Text(
                            '🎮Instrucciones Rápidas:\n\n'
                                '✅ Las canastas disponibles están en color verde.\n\n'
                                '✅ Toca una canasta para actualizar su estado y ver los participantes (las consultas son gratis).\n\n'
                                '✅ Si al tocar se pone de color naranja, es porque el sorteo está en progreso y puedes entrar.\n\n'
                                '✅ Si al tocar se pone de color rojo y dice "Finalizado", puede entrar de primero quien no haya participado en el sorteo anterior.\n\n'
                                '✅ Entra en una canasta disponible con tu Hash.\n\n'
                                '⚠️ Importante:\n\n'
                                '✅ Recuerda tener suficiente BNB para pagar el gas de la red antes de entrar.\n\n'
                                '✅ No basta con haber pagado en el Nido, necesitas el número asignado para poder participar. Si tras varios intentos para recibirlo sin poder entrar, en uno de ellos te dice que "participaste en el sorteo anterior o que el Hash ya fue utilizado", es porque se logró recibir en la blockchain aunque la app no te dejara entrar en la canasta. Revisa tu participación en la sección de Eventos del contrato.\n\n'
                                '⏱️ Dinámica del sorteo:\n\n'
                                '✅ Cada participante recibe una posición representada con un número aleatorio al entrar a la canasta.\n\n'
                                '✅ El ganador no depende del orden de entrada; este se elige de forma aleatoria, segura e inmutable dentro del contrato inteligente con el Sistema VRF de un Oráculo.\n\n'
                                '✅ Inicio automático del sorteo cuando la canasta se llena (si hay 10 participantes).\n\n'
                                '🏆 Premio:\n\n'
                                '✅ 90% del bote para el ganador.\n\n'
                                '✅ 10% para gas de la blockchain y fee del Desarrollador.\n\n'
                                '✅ Si ganas el pago llegará a tu billetera en 1-60 minutos (tiempo estimado de la red EVM).\n\n'
                                '🔒 Seguridad:\n\n'
                                '✅ El sorteo y la elección del ganador se ejecutan directamente en el contrato inteligente, con el Sistema VRF de un Oráculo para garantizar seguridad, integridad e inmutabilidad.\n\n'
                                '✅ Tú eres el único dueño y responsable de tu frase, clave y fondos.\n\n',
                            style: TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ]
                    ),
                  ),

                    // 🧺 Genera la cuadrícula de 20 canastas.
                    // Cada una cambia de color según su estado:
                    // - Verde: disponible
                    // - Naranja: en progreso
                    // - Rojo: finalizada
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 0.85,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: 20,
                      itemBuilder: (context, index) {
                        final canastaId = index + 1;
                        final participantes = _participantesPorCanasta[canastaId] ?? 0;

                        return InkWell(
                          // 👆 Al tocar una canasta, se consulta su estado en blockchain
                          // y se inicia el flujo para entrar en ella si está disponible.
                          onTap: () => _entrarCanasta(canastaId),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border.all(
                                color: participantes == 10
                                    ? Colors.red
                                    : (participantes > 0 ? Colors.orange : Colors.green),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("$canastaId", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text("$participantes/10", style: TextStyle(color: participantes > 0 ? Colors.yellow : Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(
                                  participantes == 10
                                      ? "Finalizado"
                                      : (_estadosPorCanasta[canastaId] ?? "Canasta"),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 20),
                      child: Footer(),
                    ),
                  ],
                ),
              ),
            ),

            // 🚨 Pantalla inicial superpuesta con advertencias importantes
            // sobre los clics y la seguridad del nodo.
            // Se muestra una sola vez por sesión con opción de no volver a mostrar.
            if (_mostrarMensajeBienvenida)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.85,
                      ),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.yellow,
                          width: 2,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '⚠️ Advertencia importante',
                              style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 15),

                            const Text(
                              '⚠️ Sugiero moderación con los clics de consultas a las canastas para que el Nodo no bloquee tu IP.\n\n'
                                  '❗ Si sales puedes usar tu Hash después; siempre que no elimines la app ni cambies la billetera actual por una nueva.\n\n',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.justify,
                            ),

                            StatefulBuilder(
                              builder: (context, setDialogState) {
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: _noMostrarMensajeBienvenida,
                                  onChanged: (value) {
                                    setState(() {
                                      _noMostrarMensajeBienvenida = value ?? false;
                                    });
                                  },
                                  title: const Text(
                                    'No volver a mostrar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  activeColor: Colors.yellow,
                                  checkColor: Colors.black,
                                );
                              },
                            ),

                            const SizedBox(height: 10),

                            ElevatedButton(
                              onPressed: () async {
                                if (_noMostrarMensajeBienvenida) {
                                  await _secureStorage.write(
                                    key: 'noMostrarMensajeBienvenida',
                                    value: 'true',
                                  );
                                }

                                if (!mounted) return;

                                setState(() {
                                  _mostrarMensajeBienvenida = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.yellow,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text(
                                'Entendido',
                                style: TextStyle(fontSize: 16),
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
    );
  }
}
