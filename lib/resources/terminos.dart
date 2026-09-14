import 'package:flutter/material.dart';

class TerminosDialog extends StatelessWidget {
  const TerminosDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.white, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TÉRMINOS Y CONDICIONES DE HUEVOBIT\n\n'
                  '1. Introducción\n\n'
                  'Huevobit es un juego basado en tecnología Blockchain, donde los usuarios pueden participar en canastas virtuales, donde un contrato inteligente les asignará su posición representada con un número al entrar a una canasta, para optar por una recompensa. Este juego no es una lotería ni un sistema de apuestas regulado, tampoco hay rifas ni concursos. Es un sistema de entretenimiento descentralizado y automatizado que utiliza un contrato inteligente inmutable para gestionar las reglas del juego. El ganador se elige de forma segura, íntegra e inmutable con el Sistema VRF de un Oráculo.\n\n'
                  '2. Requisitos de Participación\n\n'
                  'Solo pueden participar personas mayores de 18 años o adultos según las leyes de su país.\n\n'
                  '3. Uso de Tecnología Blockchain\n\n'
                  'Todas las transacciones y reglas se ejecutan mediante contrato inteligente inmutable, sin intervención manual.\n\n'
                  'Una vez iniciada la participación, no se pueden realizar modificaciones ni reembolsos.\n\n'
                  '4. Seguridad y Responsabilidad del Usuario\n\n'
                  'Cada usuario es responsable de la seguridad de su billetera digital Blockchain generada por la App en sentido general.\n\n'
                  'Huevobit no se hace responsable por pérdidas debido a errores del usuario, hackeos o problemas externos (como fallos en la red Blockchain).\n\n'
                  '5. Modificaciones a los Términos\n\n'
                  'Nos reservamos el derecho de modificar estos Términos y Condiciones en cualquier momento, con o sin previo aviso, a nuestra entera discreción. Es responsabilidad del usuario revisar periódicamente esta sección para conocer cualquier actualización.\n\n'
                  '6. Limitación de Responsabilidad Legal\n\n'
                  'Huevobit, su desarrollador y colaboradores no serán responsables por ningún daño directo, indirecto, incidental, especial o consecuente que surja del uso o la imposibilidad de uso de la aplicación, incluyendo, sin limitación, pérdida de fondos, interrupción del servicio, fallos de seguridad, errores en la App, en el contrato inteligente o cualquier otro evento fuera del control directo del desarrollador.\n\n'
                  'El uso de versiones modificadas o no oficiales de la aplicación queda estrictamente prohibido. Cualquier daño o pérdida causada por dichas versiones no será responsabilidad de Huevobit.\n\n'
                  '7. Aceptación de los Términos\n\n'
                  'Al presionar “Aceptar”, instalar o utilizar esta aplicación, el usuario declara haber leído, comprendido y aceptado plenamente estos Términos y Condiciones, quedando legalmente vinculado por los mismos. Si el usuario no está de acuerdo con alguno de los términos aquí expuestos, debe abstenerse de utilizar la aplicación.\n\n'
                  '8. Licencia y Propiedad Intelectual\n\n'
                  'Huevobit utiliza la licencia MIT para su código fuente, lo que permite el uso, copia, modificación y distribución del software, siempre que se mantenga el aviso de derechos de autor y la licencia original.\n\n'
                  'Sin embargo, el nombre comercial “Huevobit”, su logotipo, diseño visual, interfaz y elementos gráficos son propiedad de su autor y no pueden ser utilizados, clonados o distribuidos con fines comerciales o fraudulentos sin autorización expresa por escrito.\n\n'
                  '9. Promotores, Colaboradores y Recompensas\n\n'
                  'Huevobit es un proyecto independiente desarrollado por una sola persona. Cualquier colaboración futura, promoción o participación de terceros será de carácter voluntario y remunerada únicamente según los criterios establecidos por el desarrollador principal.\n\n'
                  'La participación de promotores, embajadores o colaboradores no implica relación laboral, sociedad, ni derechos sobre la propiedad intelectual del proyecto. Toda compensación se considerará un acuerdo independiente y temporal, sin vínculo contractual permanente.\n\n'
                  'DESCARGO DE RESPONSABILIDAD\n\n'
                  'Huevobit no es una lotería ni un servicio financiero. Es un juego de entretenimiento basado en tecnología Blockchain.\n\n'
                  'No garantizamos ganancias. La participación es voluntaria y no implica ningún retorno financiero asegurado.\n\n'
                  'Las criptomonedas conllevan riesgos. Los valores de los activos digitales pueden fluctuar, y el usuario asume toda la responsabilidad sobre sus decisiones.\n\n'
                  'No ofrecemos asesoría legal o financiera. Si tienes dudas sobre la legalidad de los juegos Blockchain en tu país, consulta con un experto antes de jugar.\n\n'
                  'El contrato inteligente es inmutable. No podemos modificar, cancelar ni revertir transacciones una vez procesadas en la Blockchain.\n\n'
                  'El usuario acepta que Huevobit puede modificar las reglas del juego y sus servicios sin previo aviso. Cualquier cambio entrará en vigor inmediatamente después de su publicación en la plataforma.\n\n'
                  '© 2025 Huevobit. Todos los derechos reservados.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.yellow,
                  side: const BorderSide(color: Colors.white),
                ),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}