# CleanUP

App nativa para macOS, escrita en SwiftUI, para revisar archivos antiguos y consultar memoria y procesos. Interfaz en español, sin dependencias externas y sin servicios en la nube.

## Abrir la app

Requiere macOS 14 o posterior y Swift 6 (Xcode o Command Line Tools).

```sh
bash scripts/build-app.sh
open dist/CleanUP.app
```

Para desarrollo: `swift run CleanUP`. Abre `Package.swift` en Xcode si prefieres usar el depurador. Para ejecutar las pruebas: `swift test`.

## Funciones

- **Vista general:** espacio disponible en el volumen del usuario, memoria y número de procesos.
- **Limpieza:** analiza archivos no vacíos de `~/Library/Caches` y `~/Library/Logs` sin cambios durante al menos siete días. Permite filtrar, buscar, mostrar en Finder y seleccionar archivos individualmente. Nada se selecciona automáticamente.
- **Memoria:** muestra la memoria física, una estimación disponible y la memoria comprimida. Permite solicitar el cierre normal de aplicaciones abiertas para reducir su consumo.
- **Procesos:** consulta PID, memoria residente y CPU, ordenados por memoria. Actualiza cada cinco segundos. Solo permite cerrar aplicaciones de usuario con interfaz; excluye Finder y CleanUP.

## Limpieza y límites

Revisa las rutas y cierra las apps relacionadas antes de limpiar sus cachés. La antigüedad de un archivo no garantiza que sea prescindible. Las cachés pueden regenerarse y algunas aplicaciones podrían necesitar descargar datos de nuevo.

La app pide confirmación y mueve únicamente los archivos seleccionados a la Papelera. Puedes recuperarlos en Finder; el espacio no se recupera hasta vaciar la Papelera por tu cuenta. No vacía la Papelera, no usa `sudo`, no instala agentes y no modifica Documentos, Descargas ni carpetas del sistema.

El análisis descarta enlaces simbólicos y paquetes. Antes de mover cada archivo comprueba otra vez su ruta, identidad, tamaño y fecha. Los errores de permisos y archivos que cambian se muestran como avisos. El análisis cubre solo lo que el usuario puede leer, sin pedir acceso total al disco.

La estimación de memoria disponible suma páginas libres e inactivas; no equivale a la presión de memoria del Monitor de Actividad. La memoria comprimida está incluida en el uso. La memoria residente por proceso no es sumable directamente por las páginas compartidas. El porcentaje de CPU puede superar el 100% en procesos que usan varios núcleos. No se ejecutan comandos de purga: macOS administra automáticamente cachés y memoria virtual.

El paquete generado se firma localmente (ad hoc), para uso en el Mac de desarrollo. La distribución pública requiere firma Developer ID y notarización.
