/// El anclaje de certificado: a qué autoridad —y solo a cuál— se le cree.
///
/// ── Qué problema resuelve ─────────────────────────────────────────────────────
///
/// TLS por sí solo dice «este certificado lo firma **alguna** de las ciento y
/// pico autoridades que el sistema se cree». Basta con que una de ellas emita mal
/// —o con que alguien instale un certificado en el móvil, que es lo que hace un
/// proxy de inspección— para que el tráfico se pueda leer y modificar por el
/// camino. Aquí viaja el histórico de entrenamiento de una persona y el token con
/// el que se accede a él.
///
/// Con anclaje, el móvil se cree **una sola** autoridad: la del servidor. Si el
/// certificado que llega no encadena hasta ella, **el apretón de manos falla y no
/// se envía ni un byte** de la petición. Que la comprobación esté ahí y no
/// después de recibir la respuesta es lo que hace que el token no llegue a salir.
///
/// ── Cómo se configura ─────────────────────────────────────────────────────────
///
/// `--dart-define API_ANCLAS=<el PEM en base64>`, igual que entran la URL y la
/// versión. Va en base64 y no como fichero para no depender de `rootBundle`: este
/// fichero **no importa Flutter**, así que se puede probar en `dart test` y
/// construir el cliente sin esperar a que cargue un *asset*.
///
///     base64 -w0 anclas.pem
///
/// Qué poner dentro, según cómo se haya montado el servidor:
///
///   · **Caddy con Let's Encrypt** (lo normal): los dos raíces de LE, ISRG Root X1
///     y X2. Duran hasta 2035, así que las renovaciones automáticas cada 60 días
///     no obligan a publicar un APK. Se descargan de letsencrypt.org/certificates.
///   · **Caddy con su CA interna** (`tls internal`): el raíz que Caddy genera al
///     arrancar, que dura diez años. Es el anclaje más estrecho —un certificado
///     mal emitido por cualquier autoridad pública no vale aquí— y el que tiene
///     sentido en una API que ningún navegador visita. Sale de
///     `/data/caddy/pki/authorities/local/root.crt` dentro del contenedor.
///
/// **Sin `API_ANCLAS` la app funciona igual**, con las autoridades del sistema:
/// sigue habiendo TLS, pero no hay anclaje. Es lo mismo que hacen `API_URL` y
/// `VERSION` cuando no están: la funcionalidad se degrada, no revienta.
///
/// ── Lo que este anclaje no hace ───────────────────────────────────────────────
///
/// No fija el certificado **hoja**, sino la autoridad. Fijar la hoja obligaría a
/// publicar un APK cada vez que Caddy renueva, y un APK que se instala a mano
/// desde una release tarda semanas en llegar a todos los móviles: el resultado
/// sería una app que deja de sincronizar sola cada dos meses. La autoridad es el
/// punto donde el anclaje aporta casi todo y no cuesta nada de operar.
library;

import 'dart:convert';
import 'dart:io';

/// Los certificados en los que confiar, en base64, o vacío para usar los del
/// sistema.
const _anclas = String.fromEnvironment('API_ANCLAS');

/// Si esta compilación lleva anclaje.
bool get hayAnclaje => _anclas.isNotEmpty;

/// El cliente HTTP con el que hablar con el servidor.
///
/// Lanza [FormatException] o [TlsException] si `API_ANCLAS` no es un PEM válido.
/// Quien lo llama lo traduce a un error de sincronización: una compilación con el
/// anclaje mal puesto no debe tirar la app, solo dejarla sin sincronizar.
HttpClient clienteAnclado() {
  if (_anclas.isEmpty) return HttpClient();

  final contexto = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64.decode(_anclas));
  return HttpClient(context: contexto);
}
