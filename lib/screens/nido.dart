import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:huevobit/widgets/footer.dart';
import 'package:huevobit/resources/reglas_juego.dart';
import 'package:huevobit/screens/canastas.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bip32/bip32.dart' as bip32;


/// 🥚 Pantalla Nido:
/// Punto de entrada para crear/gestionar la billetera local, ver balance,
/// elegir RPC, y lanzar los flujos de pago/entrada a los Nidos.
/// No usa servidores: todo es local + blockchain.
class NidoScreen extends StatefulWidget {
  const NidoScreen({super.key});

  /// Estado del Nido:
  /// Mantiene claves/ID del usuario, conexión Web3, lista de RPCs,
  /// temporizadores de balance y toda la UI/UX de seguridad (copias, ocultar/mostrar).
  @override
  State<NidoScreen> createState() => _NidoScreenState();
}

// 🔧 Convierte una cadena hexadecimal (0x...) en bytes puros (Uint8List)
// Necesario para manipular hashes, firmas y datos del contrato en bajo nivel.
Uint8List hexToBytes(String hex) {
  hex = hex.replaceAll('0x', '');
  if (hex.length % 2 != 0) hex = '0$hex';
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

// 💾 Variables principales de la billetera y conexión blockchain
// mnemonic, privateKey, publicAddress: datos de la wallet generada localmente.
// userId y userIdSignature: identificador interno firmado (no blockchain).
// web3client: conexión con el nodo RPC seleccionado.
class _NidoScreenState extends State<NidoScreen> {

  String? mnemonic;
  String? privateKey;
  String? publicAddress;
  String? userId;
  String? userIdSignature;
  double? balance;
  bool walletGenerated = false;
  final Uuid uuid = Uuid();
  String? contractAbiJson;
  bool _isLoadingWallet = true;

  // Cliente Web3 reutilizable para todas las llamadas on-chain.
  // Se re-instancia al cambiar de RPC para apuntar al nuevo nodo.
  Web3Client? web3client;
  Timer? _balanceTimer;
  bool showMnemonic = false;
  bool showPrivateKey = false;
  static const int defaultRpcCount = 9;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage(
  mOptions: const MacOsOptions(
    usesDataProtectionKeychain: false,
  ),
);
  final ScrollController _scrollController = ScrollController();
  Map<int, List<String>> paymentHashes = {};
  Map<String, String>? selectedRpc;
  final TextEditingController urlController = TextEditingController();
  final TextEditingController chainIdController = TextEditingController();
  String rpcUrl = 'https://bsc-dataseed.bnbchain.org';
  int chainId = 56;
  static const String contractAddress = '0x3f290eE8c772eE0B5c00E6d98341DA0c251DdeCB';

  // 🌐 Lista inicial de RPCs por defecto
  List<Map<String, String>> rpcList = [
    {'url': 'https://bsc-dataseed.bnbchain.org',        'chainId': '56'},
    {'url': 'https://bsc-dataseed.nariox.org',         'chainId': '56'},
    {'url': 'https://bsc-dataseed.defibit.io',         'chainId': '56'},
    {'url': 'https://bsc-dataseed.ninicoin.io',        'chainId': '56'},
    {'url': 'https://bsc-dataseed-public.bnbchain.org', 'chainId': '56'},
    {'url': 'https://bsc-dataseed1.binance.org/',      'chainId': '56'},
    {'url': 'https://bsc-dataseed2.binance.org/',      'chainId': '56'},
    {'url': 'https://bsc-dataseed3.binance.org/',      'chainId': '56'},
    {'url': 'https://bsc-dataseed4.binance.org/',      'chainId': '56'},
  ];

  // Precios para los Nidos
  Map<int, double> preciosActivos = {
    1: 0.01,
    2: 0.02,
    3: 0.03, // Valores por defecto mientras carga de la blockchain
  };

  // 🚀 Inicializa la pantalla cargando datos de la billetera,
  // configurando el RPC y empezando el refresco automático del balance.
  @override
  void initState() {
    super.initState();
    _loadWalletData();
    _initializeRpcAndClient();
    _startBalanceAutoRefresh();
    _loadRpcList();
  }

  /// 🛰️ Actualiza la conexión con un nuevo nodo RPC.
  /// Valida el formato HTTPS, actualiza el cliente Web3,
  /// guarda la configuración en almacenamiento seguro y notifica al usuario.
  void _updateRpc(String newRpcUrl, String newChainId) async {
    try {
      // Validar formato mínimo del URL
      final uri = Uri.tryParse(newRpcUrl);
      if (uri == null || uri.host.isEmpty || !uri.isScheme('https')) {
        throw const FormatException('RPC debe usar HTTPS y tener un host válido');
      }

      // Intentar crear el cliente Web3
      final client = Web3Client(newRpcUrl, Client());

      if (!mounted) return;
      setState(() {
        rpcUrl = newRpcUrl;
        chainId = int.tryParse(newChainId) ?? 56;
        selectedRpc = {'url': newRpcUrl, 'chainId': newChainId};
        web3client = client;
      });

      await secureStorage.write(key: 'selectedRpcUrl', value: newRpcUrl);
      await secureStorage.write(key: 'selectedRpcChainId', value: newChainId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ RPC actualizado a: $newRpcUrl'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String message = '❌ Error al conectar con el nodo RPC.';

      if (e is FormatException ||
          e.toString().contains(
              'Error: Invalid argument(s): No host specified in URI')) {
        message =
        '❌ Datos incorrectos, no te funcionarán. Asegúrate de incluir "https://" y un ChainId válidos.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    }
  }

  // 🧩 Recupera el último RPC guardado o usa uno por defecto.
  Future<void> _initializeRpcAndClient() async {
    final savedUrl = await secureStorage.read(key: 'selectedRpcUrl');
    final savedChainId = await secureStorage.read(key: 'selectedRpcChainId');

    // Si no hay un RPC guardado, utiliza el RPC definido como predeterminado.
    final String url = savedUrl ?? rpcUrl;
    final String chainId = savedChainId ?? '56';

    // Buscar el RPC seleccionado dentro de la lista.
    final rpc = rpcList.firstWhere(
          (r) => r['url'] == url && r['chainId'] == chainId,
      orElse: () => rpcList.firstWhere(
            (r) => r['url'] == rpcUrl,
        orElse: () => rpcList.first,
      ),
    );

    if (!mounted) return;

    setState(() {
      rpcUrl = rpc['url']!;
      selectedRpc = rpc;
      web3client = Web3Client(rpcUrl, Client());
      _fetchPreciosVisuales();
    });
  }

  // 🧹 Limpieza del Nido:
  // Cancela timers.
  // Importante cuando el usuario navega a otras pantallas.
  @override
  void dispose() {
    _balanceTimer?.cancel();
    web3client?.dispose();
    super.dispose();
  }

  // 💵 Devuelve el precio en wei para cada tipo de nido.
  Future<BigInt> _getPrecioNido(int buildingId) async {
    final abi = ContractAbi.fromJson(await rootBundle.loadString('assets/contract_abi.json'), 'Huevobit');
    final contract = DeployedContract(abi, EthereumAddress.fromHex(contractAddress));

    final result = await web3client!.call(
        contract: contract,
        function: contract.function('precioNido'),
        params: [BigInt.from(buildingId)]
    );

    return result[0] as BigInt;
  }

  // 🔄 Obtiene los precios actuales directamente del contrato inteligente
  Future<void> _fetchPreciosVisuales() async {
    if (web3client == null) return;
    try {
      final abi = ContractAbi.fromJson(
          await rootBundle.loadString('assets/contract_abi.json'), 'Huevobit');
      final contract =
      DeployedContract(abi, EthereumAddress.fromHex(contractAddress));

      for (int i = 1; i <= 3; i++) {
        final result = await web3client!.call(
            contract: contract,
            function: contract.function('precioNido'),
            params: [BigInt.from(i)]);

        final precioWei = result[0] as BigInt;
        final precioBnb = EtherAmount.fromBigInt(EtherUnit.wei, precioWei)
            .getValueInUnit(EtherUnit.ether);

        if (mounted) {
          setState(() {
            preciosActivos[i] = precioBnb;
          });
        }
      }
    } catch (e) {
      debugPrint("Error al sincronizar precios: $e");
    }
  }

  // 🧮 Genera un hash único de pago.
  // Incluye dirección, id del nido, precio y nonce del contrato.
  String _generarHashPagoSeguro(String publicAddress, int buildingId,
      BigInt precioWei, BigInt nonce) {
    final hash = keccak256(
      Uint8List.fromList(
        utf8.encode('$publicAddress$buildingId$precioWei$nonce'),
      ),
    );
    return '0x${bytesToHex(hash)}';
  }

  /// 💸 Ejecuta el pago del jugador hacia el contrato.
  /// 1. Verifica fondos y nonce.
  /// 2. Genera un hash de pago.
  /// 3. Escucha el evento HashGenerado.
  /// 4. Envía la transacción.
  /// 5. Espera confirmaciones y guarda el hash asociado.
  ///
  /// ⚠️ Incluye manejo de errores para:
  // - Fondos insuficientes
  // - Nodo RPC saturado
  // - Conexión inestable
  Future<String> _pagarEntrada(int buildingId) async {
    if (publicAddress == null || privateKey == null) {
      throw Exception('Billetera no inicializada');
    }

    try {
      final precioWei = await _getPrecioNido(buildingId);
      final balance =
      await web3client!.getBalance(EthereumAddress.fromHex(publicAddress!));

      if (balance.getInWei < precioWei) {
        throw Exception('Balance insuficiente');
      }

      final BigInt nonceActual = await _obtenerNonceContrato(publicAddress!);

      final hashPago = _generarHashPagoSeguro(
          publicAddress!, buildingId, precioWei, nonceActual);
      final hashPagoBytes = hexToBytes(hashPago);

      final abi = ContractAbi.fromJson(
          await rootBundle.loadString('assets/contract_abi.json'), 'Huevobit');
      final contract =
      DeployedContract(abi, EthereumAddress.fromHex(contractAddress));
      final hashGeneradoEvent = contract.event('HashGenerado');

      String? transactionHash;
      final completer = Completer<String>();
      late StreamSubscription sub;

      sub = web3client
          !.events(
        FilterOptions.events(contract: contract, event: hashGeneradoEvent),
      )
          .listen((eventLog) {
        try {
          final decoded =
          hashGeneradoEvent.decodeResults(eventLog.topics!, eventLog.data!);
          final jugador = decoded[0] as EthereumAddress;
          final idNidoEvent = (decoded[1] as BigInt).toInt();
          final eventHashBytes = decoded[2] as Uint8List;
          final eventHashHex = '0x${bytesToHex(eventHashBytes)}';

          if (jugador.hex.toLowerCase() == publicAddress!.toLowerCase() &&
              idNidoEvent == buildingId) {
            if (!completer.isCompleted) completer.complete(eventHashHex);
          }
        } catch (e) {
          "Error al procesar el evento del hash generado";
        }
      });

      await Future.delayed(const Duration(seconds: 3));

      try {
        final credentials = EthPrivateKey.fromHex(privateKey!);
        final function = contract.function('pagarEntrada');

        // 🔹 Obtener gasPrice dinámico de la red
        final gasPrice = await web3client!.getGasPrice();

        // 🔹 Codificar los datos de la llamada
        final data = function.encodeCall([
          BigInt.from(buildingId),
          hashPagoBytes,
          nonceActual,
        ]);

        // 🔹 Estimar gas real para esta transacción
        final estimatedGas = await web3client!.estimateGas(
          sender: credentials.address,
          to: contract.address,
          value: EtherAmount.fromBigInt(EtherUnit.wei, precioWei),
          data: data,
        );

        // 🔹 Añadir un margen de seguridad del 10%
        final gasLimit = (estimatedGas * BigInt.from(11)) ~/ BigInt.from(10);

        // 🔹 Crear la transacción con valores ajustados
        final tx = Transaction.callContract(
          contract: contract,
          function: function,
          parameters: [
            BigInt.from(buildingId),
            hashPagoBytes,
            nonceActual,
          ],
          value: EtherAmount.fromBigInt(EtherUnit.wei, precioWei),
          gasPrice: gasPrice,
          maxGas: gasLimit.toInt(),
        );

        // 🔹 Enviar la transacción
        final txHash = await web3client!.sendTransaction(
          credentials,
          tx,
          chainId: chainId,
          fetchChainIdFromNetworkId: false,
        );

        transactionHash = txHash;
      } catch (e) {
        // 🔹 Manejo inteligente de errores comunes
        final msg = e.toString();

        if (msg.contains('insufficient funds')) {
          throw Exception(
              'Saldo insuficiente: no tienes suficiente ETH para cubrir la entrada y el gas.');
        }

        if (msg.contains('is not available')) {
          throw Exception(
              'El Nodo responde que no está disponible, prueba otro.');
        }
        if (msg.contains('Unexpected character')) {
          throw Exception(
              'El formato del RPC no es correcto.');
        }
        if (msg.contains(
            'Error: ClientException: Connection closed before full header was received')) {
          throw Exception(
              'Error: la conexión fue cerrada por el RPC. Espera unos segundos o intenta con otro.');
        }

        if (msg.contains('Too many requests') || msg.contains('rate limit')) {
          throw Exception(
              'Nodo RPC parece saturado. Intenta de nuevo en unos segundos.');
        }

        if (msg.contains('Connection reset') ||
            msg.contains('SocketException')) {
          throw Exception(
              'Error de conexión con la red. Revisa tu Internet o cambia de RPC.');
        }

        // 🔹 Otros errores se relanzan
        rethrow;
      }

      // Esperar el evento HashGenerado
      final eventHashHex = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception(
              'Evento HashGenerado sigue en proceso, revísalo en un momento.');
        },
      );

      await sub.cancel();
      await Future.delayed(const Duration(seconds: 1));
      await _esperarConfirmacionTransaccion(transactionHash);

      paymentHashes.putIfAbsent(buildingId, () => []).add(eventHashHex);

      await secureStorage.write(
        key: 'paymentHashes',
        value: jsonEncode(
          paymentHashes.map(
                (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      );

      return eventHashHex;
    } catch (e) {
      final errorMsg = e.toString();

      if (errorMsg.contains('insufficient funds') ||
          errorMsg.contains('insufficient balance')) {
        throw Exception(
          '⛽ BNB insuficiente para completar la transacción. '
              'Necesitas cubrir el pago de entrada y el gas.',
        );
      }

      if (errorMsg.contains('-32005') ||
          errorMsg.contains('limit exceeded')) {
        throw Exception(
          '⚠️ No se pudo consultar la blockchain. '
              'El RPC seleccionado rechazó la consulta por exceder su límite. '
              'Cambia de RPC e inténtalo nuevamente.',
        );
      }

      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Connection reset by peer')) {
        throw Exception(
            '⚠️ Verifica que hayas colocado el RPC de forma correcta.');
      } else if (errorMsg.contains('TimeoutException')) {
        throw Exception(
            'La transacción fue enviada, pero todavía no pudo confirmarse en la aplicación.\n\n'
        '⚠️ No vuelvas a pagar por ahora. Espera unos momentos y revisa nuevamente.'
        );
      } else {
        throw Exception(
          '⚠️ No se pudo completar el pago. '
              'Verifica que tengas suficiente BNB para cubrir el monto de entrada '
              'y el gas de la transacción. Si tienes fondos suficientes, '
              'intenta nuevamente o cambia de RPC.',
        );
      }
    }
  }

  // ⏳ Espera a que la transacción aparezca confirmada en la blockchain.
// Consulta periódicamente su receipt hasta que exista y tenga status exitoso.
// Se vuelve a consultar cada 5 segundos mientras sea necesario.
// No establece un número fijo de intentos: continúa hasta obtener una
// confirmación válida o hasta que se produzca un error externo.
  Future<void> _esperarConfirmacionTransaccion(
      String transactionHash) async {
    while (true) {
      bool transaccionRevertida = false;

      try {
        final receipt =
        await web3client!.getTransactionReceipt(transactionHash);

        if (receipt != null && receipt.status == true) {
          return;
        }

        if (receipt != null && receipt.status == false) {
          transaccionRevertida = true;
        }
      } catch (e) {
        // Error temporal del RPC: se vuelve a intentar.
      }

      // Está fuera del try/catch, por lo que ya no se ignora.
      if (transaccionRevertida) {
        throw Exception('Transacción revertida');
      }

      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // 🔢 Llama al contrato para obtener el nonce actual del jugador.
  Future<BigInt> _obtenerNonceContrato(String publicAddress) async {
    final abi = ContractAbi.fromJson(
        await rootBundle.loadString('assets/contract_abi.json'), 'Huevobit');
    final contract =
    DeployedContract(abi, EthereumAddress.fromHex(contractAddress));

    final result = await web3client!.call(
        contract: contract,
        function: contract.function('obtenerNonce'),
        params: [EthereumAddress.fromHex(publicAddress)]);
    return result[0] as BigInt;
  }

  // 💽 Carga los datos de la billetera almacenados en el dispositivo.
  // Si los datos están dañados, los limpia y evita errores.
  Future<void> _loadWalletData() async {
    setState(() => _isLoadingWallet = true);
    try {
      mnemonic = await secureStorage.read(key: 'mnemonic');
      privateKey = await secureStorage.read(key: 'privateKey');
      publicAddress = await secureStorage.read(key: 'publicAddress');
      userId = await secureStorage.read(key: 'userId');
      userIdSignature = await secureStorage.read(key: 'userIdSignature');
      final storedHashes = await secureStorage.read(key: 'paymentHashes');
      if (storedHashes != null) {
        final decoded = jsonDecode(storedHashes) as Map<String, dynamic>;
        paymentHashes = decoded.map(
              (key, value) =>
              MapEntry(int.parse(key), List<String>.from(value)),
        );
      }
      contractAbiJson = await rootBundle.loadString('assets/contract_abi.json');
      walletGenerated = mnemonic != null;

      if (publicAddress != null) await _fetchBalance(publicAddress);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      'Error al cargar los datos de la billetera: $e. Se limpiaron datos corruptos.';
      await _clearCorruptedData();
    } finally {
      if (mounted) setState(() => _isLoadingWallet = false);
    }
  }

  // 🧹 Limpia datos corruptos o inconsistentes del almacenamiento seguro.
  // Se usa como medida de seguridad si algo falla al leer la wallet.
  Future<void> _clearCorruptedData() async {
    await secureStorage.delete(key: 'mnemonic');
    await secureStorage.delete(key: 'privateKey');
    await secureStorage.delete(key: 'publicAddress');
    await secureStorage.delete(key: 'userId');
    await secureStorage.delete(key: 'userIdSignature');
    await secureStorage.delete(key: 'paymentHashes');
    setState(() {
      walletGenerated = false;
      paymentHashes = {};
    });
  }

  // 💰 Obtiene el balance actual del usuario en BNB desde el nodo RPC.
  Future<void> _fetchBalance([String? address]) async {
    final addr = address ?? publicAddress;
    if (addr == null) return;

    try {
      final bal = await web3client!.getBalance(EthereumAddress.fromHex(addr));
      if (!mounted) return;
      setState(() {
        balance = bal.getValueInUnit(EtherUnit.ether);
      });
    } catch (e) {
      'Error al obtener el balance de la dirección $addr: $e';
    }
  }

  // 🔄 Actualiza automáticamente el balance cada 1 minuto.
  // Cancela el temporizador si el widget se desmonta o no hay dirección.
  void _startBalanceAutoRefresh() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted || publicAddress == null) {
        timer.cancel();
      } else {
        _fetchBalance(publicAddress);
      }
    });
  }

  // 🧾 Guarda de forma segura los datos sensibles en FlutterSecureStorage.
  Future<void> _saveWalletData() async {
  final log = <String>[];

  Future<void> guardar(String nombre, String key, String value) async {
    try {
      await secureStorage.write(key: key, value: value);
      log.add('$nombre: OK');
    } catch (e) {
      log.add('$nombre: ERROR -> $e');
      rethrow;
    }
  }

  await guardar('mnemonic', 'mnemonic', mnemonic!);
  await guardar('privateKey', 'privateKey', privateKey!);
  await guardar('publicAddress', 'publicAddress', publicAddress!);
  await guardar('userId', 'userId', userId!);
  await guardar('userIdSignature', 'userIdSignature', userIdSignature!);
}

  // 🆔 Genera un identificador de usuario único (no relacionado a blockchain)
  // Combina UUID + timestamp para trazabilidad interna.
  String _generateUserId() {
    final randomPart = uuid.v4().replaceAll('-', '');
    final timestamp = DateTime
        .now()
        .millisecondsSinceEpoch
        .toRadixString(36);
    return '${randomPart.substring(0, 12)}${timestamp.substring(
        timestamp.length - 8)}';
  }

  // ✍️ Firma el userId con la clave privada del jugador.
  // Sirve para autenticaciones off-chain o validaciones internas.
  Future<String> _signUserId(String userId, String privateKeyHex) async {
    try {
      final credentials = EthPrivateKey.fromHex(privateKeyHex);
      final idHash = keccak256(Uint8List.fromList(utf8.encode(userId)));
      final signature = credentials.signPersonalMessageToUint8List(idHash);
      return '0x${bytesToHex(signature)}';
    } catch (e) {
      'Error al firmar el ID de usuario con la clave privada: $e';
      throw Exception('Error al firmar el ID de usuario: $e');
    }
  }

  ///   Genera una nueva billetera blockchain local:
  /// - Crea mnemónico y clave privada.
  /// - Deriva la dirección pública.
  /// - Firma un userId.
  /// - Guarda todo localmente.
  /// ⚠️ El usuario es responsable de guardar sus 12 palabras.
  Future<void> generateWallet() async {
    try {
      final newMnemonic = bip39.generateMnemonic();
      final seed = bip39.mnemonicToSeed(newMnemonic, passphrase: '');

      final node = bip32.BIP32.fromSeed(seed)
          .derivePath("m/44'/60'/0'/0/0");

      final privateKeyBytes = node.privateKey;
      if (privateKeyBytes == null) {
        throw StateError('No se pudo derivar la clave privada Ethereum.');
      }
      final privateKeyHex =
          '0x${privateKeyBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()}';

      final credentials = EthPrivateKey.fromHex(privateKeyHex);
      final address = credentials.address;

      final newUserId = _generateUserId();
      final signature = await _signUserId(newUserId, privateKeyHex);

      setState(() {
        mnemonic = newMnemonic;
        privateKey = privateKeyHex;
        publicAddress = address.hex;
        walletGenerated = true;
        userId = newUserId;
        userIdSignature = signature;
      });

      await _saveWalletData(); // si falla, lanza excepción y salta al catch

    // 👇 solo llegamos aquí si el guardado fue exitoso
    setState(() {
      walletGenerated = true;
    });
      
      await _fetchBalance(address.hex);
    } catch (e) {
    setState(() {
      walletGenerated = false; // por si algo ya lo había puesto en true antes
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar billetera: ${e.toString()}')),
      );
    }
  }

  // 📋 Copia cualquier texto al portapapeles y muestra aviso visual.
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado al portapapeles')),
    );
  }

  // 🧰 Caja de información protegida (como mnemónico o clave privada).
  // Permite mostrar/ocultar y copiar de forma controlada.
  Widget _buildProtectedInfoBox(String title, String value, bool show,
      VoidCallback toggle) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 10),
          if (!show) const Icon(Icons.lock, color: Colors.yellow, size: 28),
          if (show)
            Text(
              value,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.justify,
            ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: toggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              side: const BorderSide(color: Colors.yellow),
            ),
            child: Text(show ? 'Ocultar' : 'Ver',
                style: const TextStyle(color: Colors.yellow)),
          ),
          const SizedBox(height: 5),
          if (show)
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.yellow),
            onPressed: () => _copyToClipboard(value),
          ),
        ],
      ),
    );
  }

  // Caja simple para mostrar información pública como dirección o firmas.
  Widget _buildInfoBox(String title, String value, {bool isAddress = false}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.justify,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.yellow),
                onPressed: () => _copyToClipboard(value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 💳 Muestra la dirección pública para depósitos.
  // El jugador puede copiarla y usarla en otra wallet para enviar fondos.
  Widget _buildDepositSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          const Text(
            'Depositar',
            style: TextStyle(color: Colors.yellow, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  publicAddress!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.yellow),
                onPressed: () => _copyToClipboard(publicAddress!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 💼 Instrucciones claras sobre cómo retirar fondos.
  // Explica que el control es total del usuario y advierte sobre la seguridad.
  Widget _buildWithdrawalSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(15),
      child: const Column(
        children: [
          Text(
            'Cómo Retirar',
            style: TextStyle(color: Colors.yellow, fontSize: 18),
          ),
          SizedBox(height: 10),
          Text(
            'Tienes el control de tus 12 palabras y clave privada. Puedes usar cualquier billetera Web3 compatible con EVM (como MetaMask, Trust Wallet, etc.) para gestionar tus fondos.\n\n'
                'Importa tu clave privada o frase de recuperación en una billetera segura para retirar tus fondos cuando lo desees.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.justify,
          ),
          SizedBox(height: 15),
          Text(
            'ADVERTENCIA',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 5),
          Text(
            'Huevobit no se hace responsable por robo o pérdida de tus 12 palabras, clave privada ni de los recursos asociados a esta cuenta.\n\nTú tienes el control completo de tus activos al guardar tu frase y clave privada. Huevobit no almacena esta información en ningún lugar, ni en servidores, ni en ningún servicio externo, todo está en la App de forma local.\n\nUsa esta dirección para pagar tus entradas a los Nidos y recibirás tu recompensa en esta misma dirección si ganas.\n\nGuarda tus ganancias en otra billetera personal para mayor seguridad.\n\n'
                '⚠️ No hay reembolso ni reclamos de ningún tipo.\n\n',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  // 📘 Botón que abre el diálogo con las reglas oficiales del juego.
  Widget _buildRulesButton() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: OutlinedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const ReglasJuegoDialog(),
          );
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.yellow,
          side: const BorderSide(color: Colors.white),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: const Text('Ver reglas del juego'),
      ),
    );
  }

  // 🔍 Abrevia cadenas largas (direcciones, hashes, contratos...)
  // Muestra primeros y últimos 4 caracteres con puntos intermedios.
  String short(String text) {
    if (text.length <= 10) return text;
    return '${text.substring(0, 6)}...${text.substring(text.length - 4)}';
  }

  /// 🏗️ Crea un botón para entrar a un Nido (juego).
  /// Gestiona todo el flujo de pago, confirmación, validación y redirección.
  /// Incluye múltiples manejos de error y mensajes al usuario.
  Widget _buildBuildingButton(String title, int buildingId) {
    final precioVisual = preciosActivos[buildingId] ?? 0.0;
    final amount = '${precioVisual.toStringAsFixed(3)} BNB';

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: ElevatedButton(
        onPressed: walletGenerated
            ? () => _mostrarOpcionesNido(buildingId, title)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.yellow,
          side: const BorderSide(color: Colors.yellow),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: Text('$title ($amount)'),
      ),
    );
  }

  /// 🔎 Verifica los Hashes disponibles de un Nido directamente en el contrato.
  /// Conserva los Hashes no usados y elimina del caché los que el contrato
  /// confirme como usados.
  Future<void> _verificarHashesDelNido(int buildingId) async {
    if (publicAddress == null) return;

    // ⏳ Aviso mientras se consulta el RPC.
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          '⏳ Verificando Hash',
          style: TextStyle(color: Colors.yellow),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.yellow),
            SizedBox(height: 15),
            Text(
              'Verificando si hay un Hash no usado disponible...',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    try {
      final hashes = List<String>.from(
        paymentHashes[buildingId] ?? [],
      );

      if (hashes.isEmpty) return;

      final abi = ContractAbi.fromJson(
        await rootBundle.loadString('assets/contract_abi.json'),
        'Huevobit',
      );

      final contrato = DeployedContract(
        abi,
        EthereumAddress.fromHex(contractAddress),
      );

      final funcionHashesUsados =
      contrato.function('hashesUsados');

      final hashesValidos = <String>[];

      for (final hash in hashes) {
        try {
          // 🛡️ Comprobar primero que tenga formato bytes32.
          if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash.trim())) {
            continue;
          }

          final hashBytes = hexToBytes(hash.trim());

          final resultado = await web3client
              !.call(
            contract: contrato,
            function: funcionHashesUsados,
            params: [hashBytes],
          )
              .timeout(const Duration(seconds: 3));

          final usado =
              resultado.isNotEmpty && resultado[0] == true;

          if (!usado) {
            // ✅ El contrato confirma que todavía está disponible.
            hashesValidos.add(hash);
          }


        } catch (e) {
          // ⚠️ Si no podemos comprobarlo, NO eliminamos el Hash.
          // Es más seguro conservarlo y volver a comprobarlo después.
          hashesValidos.add(hash);
        }
      }
      // ⏳ Pequeña pausa para no bombardear el RPC.
      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      setState(() {
        if (hashesValidos.isEmpty) {
          paymentHashes.remove(buildingId);
        } else {
          paymentHashes[buildingId] = hashesValidos;
        }
      });

      // 💾 Guardar el estado actualizado del caché.
      await secureStorage.write(
        key: 'paymentHashes',
        value: jsonEncode(
          paymentHashes.map(
                (key, value) => MapEntry(
              key.toString(),
              value,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error verificando Hashes del Nido: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ No se pudo verificar el Hash con la Blockchain. '
                  'El RPC puede estar ocupado. Intenta nuevamente.',
            ),
          ),
        );
      }
    } finally {
      // 🔒 Cerrar el diálogo de verificación.
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// 🗔 Diálogo 1: Opciones principales al tocar el Nido
  void _mostrarOpcionesNido(int buildingId, String title) async {
    // 🔎 Consultar/actualizar los Hash disponibles
    await _verificarHashesDelNido(buildingId);

    if (!mounted) return;

    final hashesDisponibles =
    List<String>.from(paymentHashes[buildingId] ?? []);

    final tieneHashEnCache = hashesDisponibles.isNotEmpty;

    final hashSugerido =
    tieneHashEnCache ? hashesDisponibles.last : "";

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Opciones de Entrada', style: TextStyle(color: Colors.yellow)),
        content: Text(
          tieneHashEnCache
              ? '🎉 Hemos detectado un Hash no usado en tu App. ¿Qué deseas hacer?'
              : 'Selecciona una opción para continuar.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _mostrarDialogoIngresarHash(buildingId, hashSugerido);
            },
            child: const Text('Entrar con Hash', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _mostrarDialogoConfirmarPago(buildingId, title);
            },
            child: const Text('Pagar', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  /// 🗔 Diálogo 2: Ingresar Hash manualmente (o usar el del caché)
  void _mostrarDialogoIngresarHash(int buildingId, String hashSugerido) {
    TextEditingController hashController = TextEditingController(text: hashSugerido);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Ingresar Hash', style: TextStyle(color: Colors.yellow)),
        content: TextField(
          controller: hashController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Pega tu Hash aquí...',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.yellow)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.yellow)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              final hash = hashController.text.trim();

              if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '⚠️ Hash inválido. Debes introducir un HashPago válido de 32 bytes.',
                    ),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CanastasScreen(
                    rpcUrl: rpcUrl,
                    contractAddress: contractAddress,
                    abi: contractAbiJson!,
                    userAddress: publicAddress!,
                    idUsuario: userId!,
                    firmaId: userIdSignature!,
                    hashPago: hashController.text.trim(),
                    idNido: buildingId,
                    chainId: chainId,
                  ),
                ),
              );
            },
            child: const Text('Entrar', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  /// 🗔 Diálogo 3: Confirmar Pago
  void _mostrarDialogoConfirmarPago(int buildingId, String title) {
    final precioVisual = preciosActivos[buildingId] ?? 0.0;

    showDialog(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
            backgroundColor: Colors.black,
            title: const Text(
              'Confirmar Pago',
              style: TextStyle(color: Colors.yellow),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔑 Paga ${precioVisual.toStringAsFixed(
                      3)} BNB para entrar a $title\n\n'
                      '❗️ Tu billetera paga monto y gas siempre; excepto cuando se elige el ganador.\n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  '⚠️ Blockchain es IRREVERSIBLE\n\n'
                      '⚠️ No hay reembolsos ni reclamos de ningún tipo.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _procesarPagoYMostrarHash(buildingId);
                },
                child: const Text(
                  'Pagar',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ],
          ),
    );
  }

  /// ⚙️ Diálogo 4: Proceso de Pago, Espera y Navegación
  Future<void> _procesarPagoYMostrarHash(int buildingId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => const Dialog(
        backgroundColor: Colors.blueAccent,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.yellow,
              ),
              SizedBox(height: 18),
              Text(
                '⏳ Procesando pago en el contrato...\n\n'
                    'Espera mientras la red confirma tu pago. '
                    'No cierres la aplicación durante este proceso.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      String hashGenerado = await _pagarEntrada(buildingId);

      if (!mounted) return;
      Navigator.pop(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (successContext) => AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('¡Pago Confirmado!', style: TextStyle(color: Colors.greenAccent)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Tu pago ha sido procesado. Este es tu Hash de entrada:', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 10),
              Text(short(hashGenerado), style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _copyToClipboard(hashGenerado);
                Navigator.pop(successContext);

                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CanastasScreen(
                      rpcUrl: rpcUrl,
                      contractAddress: contractAddress,
                      abi: contractAbiJson!,
                      userAddress: publicAddress!,
                      idUsuario: userId!,
                      firmaId: userIdSignature!,
                      hashPago: hashGenerado,
                      idNido: buildingId,
                      chainId: chainId,
                    ),
                  ),
                );
              },
              child: const Text('Copiar y continuar', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(successContext);

                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CanastasScreen(
                      rpcUrl: rpcUrl,
                      contractAddress: contractAddress,
                      abi: contractAbiJson!,
                      userAddress: publicAddress!,
                      idUsuario: userId!,
                      firmaId: userIdSignature!,
                      hashPago: hashGenerado,
                      idNido: buildingId,
                      chainId: chainId,
                    ),
                  ),
                );
              },
              child: const Text('Continuar sin copiar', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''),
      ),
      ),
      );
    }
  }

  /// ⚙️ Sección visual para gestionar los nodos RPC.
  /// Permite elegir, agregar o eliminar RPCs personalizados con validaciones.
  /// Guarda automáticamente los cambios y muestra el RPC activo.
  Widget _buildRpcSettings() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Cambiar RPC",
            style: TextStyle(
              color: Colors.yellow,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "⚠️ AVISO IMPORTANTE: la lista de RPCs oficiales de la BNB Chain no garantiza que siempre estén disponibles ni que no te puedan bloquear la IP. Si alguno falla o no está disponible, considera agregar uno tuyo o ajeno bajo tu propia responsabilidad.",
            style: TextStyle(
              color: Colors.yellow,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.justify,
          ),
          const SizedBox(height: 20),

          // Dropdown para seleccionar RPC
          DropdownButtonFormField<String>(
            isExpanded: true,
            dropdownColor: Colors.black,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black,
              labelText: "Elegir RPC",
              labelStyle: const TextStyle(color: Colors.yellow),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.yellow),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.yellow, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            value: selectedRpc?['url'],
            items: rpcList.map((rpc) {
              return DropdownMenuItem<String>(
                value: rpc['url'],
                child: Text(
                  rpc['url']!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
            onChanged: (url) {
              if (url != null) {
                final chosen = rpcList.firstWhere((r) => r['url'] == url);
                _updateRpc(chosen['url']!, chosen['chainId']!);
              }
            },
          ),

          const SizedBox(height: 20),

          // Botón para agregar nuevo RPC
          ElevatedButton(
            onPressed: _addRpcDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.yellow,
              side: const BorderSide(color: Colors.yellow),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            ),
            child: const Text("Agregar RPC"),
          ),

          // Lista de RPCs agregados manualmente
          if (rpcList.length > defaultRpcCount) ...[
            const SizedBox(height: 25),
            const Text(
              "RPCs agregados:",
              style:
              TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              children: rpcList
                  .asMap()
                  .entries
                  .where((e) =>
              e.key >= defaultRpcCount)
                  .map((entry) {
                final rpc = entry.value;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.yellow),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          rpc['url']!,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.redAccent, size: 20),
                          tooltip: 'Eliminar RPC',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Colors.black,
                                title: const Text(
                                  "Confirmar eliminación",
                                  style: TextStyle(color: Colors.yellow),
                                ),
                                content: Text(
                                  "¿Seguro que deseas eliminar este RPC?\n\n${rpc['url']}",
                                  style: const TextStyle(color: Colors.white),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text("Cancelar",
                                        style: TextStyle(color: Colors.grey)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text("Eliminar",
                                        style:
                                        TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              if (!mounted) return;

                              // 1️⃣ Antes de modificar la lista, validar selección
                              final isSelectedInDropdown = selectedRpc?['url'] == rpc['url'];
                              if (isSelectedInDropdown) {
                                selectedRpc = null; // Limpia el valor para que el Dropdown no reviente
                              }

                              // 2️⃣ Ahora sí, eliminar dentro del setState
                              setState(() {
                                rpcList.removeAt(entry.key);

                                // Si además era el actual, restaurar a uno válido
                                if (rpc['url'] == rpcUrl && rpcList.isNotEmpty) {
                                  final def = rpcList.first;
                                  _updateRpc(def['url']!, def['chainId']!);
                                }
                              });

                              _saveRpcList();

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('RPC eliminado correctamente'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 30),

          const Text(
            "RPC actual",
            style: TextStyle(
              color: Colors.yellow,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          if (selectedRpc != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.yellow),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "URL: ${selectedRpc!['url']}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "ChainID: ${selectedRpc!['chainId']}",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          else
            const Text(
              "Ningún RPC seleccionado",
              style: TextStyle(color: Colors.white70),
            ),
        ],
      ),
    );
  }

  // Salva los RPCs agregados manualmente.
  Future<void> _saveRpcList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = rpcList.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList('rpcList', jsonList);
  }

  String _normalizarRpcUrl(String url) {
    return url.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  List<Map<String, String>> _eliminarRpcDuplicados(
      List<Map<String, String>> lista) {
    final vistos = <String>{};
    final resultado = <Map<String, String>>[];

    for (final rpc in lista) {
      final url = _normalizarRpcUrl(rpc['url'] ?? '');
      final chainId = (rpc['chainId'] ?? '').trim();

      if (url.isEmpty || chainId.isEmpty) continue;

      // El URL es el identificador del RPC dentro del Dropdown.
      if (vistos.add(url)) {
        resultado.add({
          'url': url,
          'chainId': chainId,
        });
      }
    }

    return resultado;
  }

  // Cargar los RPCs agregados manualmente tras volver de una pantalla.
  Future<void> _loadRpcList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('rpcList');

    if (jsonList == null) return;

    final listaCargada = <Map<String, String>>[];

    for (final e in jsonList) {
      try {
        final decoded = jsonDecode(e);

        listaCargada.add({
          'url': decoded['url'].toString(),
          'chainId': decoded['chainId'].toString(),
        });
      } catch (_) {
        // Ignorar entradas corruptas.
      }
    }

    final listaLimpia = _eliminarRpcDuplicados(listaCargada);

    if (!mounted) return;

    setState(() {
      rpcList = listaLimpia;
    });

    // Guarda nuevamente la lista ya corregida.
    await _saveRpcList();
  }

  // Diálogo emergente para agregar manualmente un nuevo RPC HTTPS válido.
  // Incluye validaciones de campos vacíos y formato de URL.
  void _addRpcDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text("Agregar RPC", style: TextStyle(color: Colors.yellow)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text("URL:", style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "https://...",
                        hintStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.yellow),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.yellow),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child:
                    Text("ChainID:", style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: chainIdController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "56",
                        hintStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.yellow),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.yellow),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                urlController.clear();
                chainIdController.clear();
              },
              child: const Text("Cancelar", style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                final url = urlController.text.trim();
                final chainId = chainIdController.text.trim();
                if (int.tryParse(chainId) != 56) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '❌ Solo se permiten los RPC de BNB Chain Mainnet (Chain ID 56).',
                      ),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                // ⚠️ Validar campos vacíos
                if (url.isEmpty || chainId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Debes completar ambos campos.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                // ⚠️ Validar que comience con https://
                if (!url.startsWith('https://')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          '❌ La URL del RPC debe comenzar con "https://".'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                // ⚠️ Nueva validación: debe tener host (no solo "https://")
                final uri = Uri.tryParse(url);
                if (uri == null || uri.host.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          '❌ URL inválida. Debe incluir un dominio o dirección válida.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                final urlNormalizada = _normalizarRpcUrl(url);

                final yaExiste = rpcList.any(
                      (rpc) => _normalizarRpcUrl(rpc['url'] ?? '') == urlNormalizada,
                );

                if (yaExiste) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Este RPC ya está agregado.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                // ✅ Si pasa todo, se guarda y actualiza
                if (!mounted) return;
                setState(() {
                  rpcList.add({'url': urlNormalizada, 'chainId': chainId});
                });

                _saveRpcList();
                _updateRpc(urlNormalizada, chainId); // reconecta
                Navigator.pop(context);
                urlController.clear();
                chainIdController.clear();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ RPC agregado correctamente: $urlNormalizada'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text("Guardar", style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  /// 🖥️ Construye toda la interfaz del Nido.
  /// Contiene los pasos del jugador, balance, wallet, nidos, y configuración.
  /// El corazón visual y funcional de la app.
  @override
  Widget build(BuildContext context) {
    return
      Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text(
            '🥚 Huevobit 🥚',
            style: TextStyle(color: Colors.yellow, fontSize: 24),
          ),
          centerTitle: true,
          bottom: publicAddress != null
              ? PreferredSize(
            preferredSize: const Size.fromHeight(150),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        balance != null
                            ? 'Balance: ${balance!.toStringAsFixed(4)} BNB'
                            : 'Balance: --',
                        style: const TextStyle(color: Colors.white),
                      ),
                      IconButton(
                        icon:
                        const Icon(Icons.refresh, color: Colors.yellow),
                        tooltip: "Refrescar Balance",
                        onPressed: publicAddress != null
                            ? () => _fetchBalance(publicAddress!)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Contrato: ${short(contractAddress)}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy,
                            color: Colors.yellow, size: 20),
                        tooltip: 'Copiar contrato',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: contractAddress),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Contrato copiado al portapapeles')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          )
              : null,
        ),
        body: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(10),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    const Text(
                      '¡Disfruta mi juego blockchain! 🎉',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sigue estos pasos para comenzar:\n\n'
                          '1. 🏦 Genera tu billetera blockchain\n'
                          '2. 💰 Deposita fondos en tu dirección\n'
                          '3. 🎮 Elige tu nido cripto\n'
                          '4. 🏆 Juega y disfruta',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      '⚠️ ADVERTENCIA IMPORTANTE:\n\nCuando generes la billetera guarda muy bien tus 12 palabras y clave privada, ya que, si no lo haces, perderás todos tus fondos sin reclamo y nadie te puede ayudar a recuperarlos.',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height:30),
                    Text(
                      '⚠️ ADVERTENCIA IMPORTANTE: esto no es una billetera personal.',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height: 30),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 200),
                      child: ElevatedButton(
                        onPressed: (walletGenerated || _isLoadingWallet) ? null : generateWallet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.yellow,
                          side: const BorderSide(color: Colors.yellow),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Generar Billetera Blockchain'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (walletGenerated) ...[
                      _buildProtectedInfoBox(
                          '12 Palabras de Recuperación:',
                          mnemonic!,
                          showMnemonic,
                              () => setState(() => showMnemonic = !showMnemonic)),
                      const SizedBox(height: 15),
                      _buildProtectedInfoBox(
                          'Clave Privada:',
                          privateKey!,
                          showPrivateKey,
                              () => setState(() => showPrivateKey = !showPrivateKey)),
                      const SizedBox(height: 15),
                      _buildInfoBox('Dirección Pública:', publicAddress!,
                          isAddress: true),
                      const SizedBox(height: 15),
                      _buildInfoBox('ID de Usuario:', userId!),
                      const SizedBox(height: 15),
                      _buildInfoBox('Firma del ID:', userIdSignature!),
                      const SizedBox(height: 30),
                      _buildDepositSection(),
                      const SizedBox(height: 20),
                      _buildWithdrawalSection(),
                      const SizedBox(height: 30),
                    ],
                    _buildRulesButton(),
                    _buildRpcSettings(),
                    const SizedBox(height: 30),
                    const Text(
                      'Selecciona tu Nido:',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('⚠️ Información importante'),
                                content: const SingleChildScrollView(
                                  child: Text(
                                    '💳 Si ves el mensaje que dice “Sigue en proceso, '
                                        'revísalo en un momento...”, no vuelvas a intentar pagar. '
                                        'Espera a que la operación sea confirmada por el contrato '
                                        'y recibida por la aplicación. Si al rato intentas pagar nuevamente, '
                                        'la aplicación te indicará si ya tienes un Hash disponible.\n\n'

                                        '🔒 Recuerda que solo podrás usar un Hash no utilizado '
                                        'si no borras los datos de la app ni la eliminas.\n\n'

                                        '⏳ Algunas operaciones pueden tardar unos momentos en '
                                        'aparecer en la aplicación. Esto puede depender de la '
                                        'confirmación de la Blockchain, la congestión de la red '
                                        'y la respuesta del RPC utilizado.\n\n'

                                        '🔍 Si realizaste un pago y todavía no aparece confirmado '
                                        'en la aplicación, puedes comprobarlo directamente en el '
                                        'área de eventos del contrato. Busca el evento '
                                        '“HashGenerado” para verificar si tu Hash ya fue confirmado.\n\n'

                                        '🌐 Si la aplicación tarda demasiado en actualizar la '
                                        'información o presenta problemas de conexión, puede ser '
                                        'debido al RPC seleccionado. Puedes intentar utilizar otro '
                                        'RPC disponible.\n\n'

                                        '⚠️ Un problema, retraso o fallo temporal del RPC no '
                                        'significa necesariamente que tu pago se haya perdido. '
                                        'Las operaciones confirmadas permanecen registradas en '
                                        'la Blockchain para siempre.\n\n'

                                        '🔄 Si tienes dudas sobre el estado de una operación, '
                                        'evita repetir el pago inmediatamente. Primero espera unos '
                                        'momentos y verifica si la operación ya fue procesada.\n\n'

                                        '🔒 Nunca compartas tu frase de recuperación ni tu clave '
                                        'privada. Quien tenga acceso a ellas puede controlar tu '
                                        'billetera y sus fondos.',
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
                    const SizedBox(height: 20),
                    _buildBuildingButton('Nido Cripto 1', 1),
                    const SizedBox(height: 15),
                    _buildBuildingButton('Nido Cripto 2', 2),
                    const SizedBox(height: 15),
                    _buildBuildingButton('Nido Cripto 3', 3),
                    const SizedBox(height: 20),
                    Footer(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}
