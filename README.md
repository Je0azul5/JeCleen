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
- **Almacenamiento:** analiza el usuario, Aplicaciones, el disco de datos o una carpeta elegida. Muestra tamaños por carpeta, distribución porcentual y los 20 archivos más grandes de todo el árbol. Permite entrar en subcarpetas, regresar, buscar, filtrar carpetas y mostrar elementos en Finder. El análisis funciona en segundo plano, muestra avances y se puede cancelar conservando los resultados parciales.
- **Limpieza:** analiza archivos no vacíos de `~/Library/Caches` y `~/Library/Logs` sin cambios durante al menos siete días. Permite filtrar, buscar, mostrar en Finder y seleccionar archivos individualmente. Nada se selecciona automáticamente.
- **Memoria:** muestra la memoria física, una estimación disponible y la memoria comprimida. Ordena los 12 mayores consumidores agrupando cada app con los procesos auxiliares dentro de su paquete; cada grupo se despliega para ver sus PID. Permite solicitar el cierre normal de aplicaciones abiertas para reducir su consumo.
- **Procesos:** consulta PID, memoria residente y CPU, ordenados por memoria. Actualiza cada cinco segundos. Solo permite cerrar aplicaciones de usuario con interfaz; excluye Finder y CleanUP.

## Limpieza y límites

Revisa las rutas y cierra las apps relacionadas antes de limpiar sus cachés. La antigüedad de un archivo no garantiza que sea prescindible. Las cachés pueden regenerarse y algunas aplicaciones podrían necesitar descargar datos de nuevo.

La app pide confirmación y mueve únicamente los archivos seleccionados a la Papelera. Puedes recuperarlos en Finder; el espacio no se recupera hasta vaciar la Papelera por tu cuenta. No vacía la Papelera, no usa `sudo`, no instala agentes y no modifica Documentos, Descargas ni carpetas del sistema.

El análisis descarta enlaces simbólicos y paquetes. Antes de mover cada archivo comprueba otra vez su ruta, identidad, tamaño y fecha. Los errores de permisos y archivos que cambian se muestran como avisos. El análisis cubre solo lo que el usuario puede leer, sin pedir acceso total al disco.

## Medición del almacenamiento

El explorador de almacenamiento solo consulta metadatos y no elimina archivos. A diferencia del análisis de limpieza, incluye el contenido de paquetes como `.app` para medir su tamaño. Incluye archivos ocultos, omite enlaces simbólicos y no atraviesa otros volúmenes montados. Las rutas inaccesibles aparecen como avisos y los resultados se marcan como parciales; se conservan hasta 100 mensajes de detalle.

Puedes alternar entre **En disco** (espacio asignado informado por macOS) y **Tamaño lógico** (longitud declarada del archivo). No lee contenidos ni descarga archivos de iCloud. Un archivo en la nube o disperso puede tener tamaño lógico grande y ocupar poco o nada localmente. Los tamaños se suman por ruta: los clones APFS y enlaces duros pueden compartir bloques, así que el total medido no representa espacio recuperable ni debe coincidir con el uso del volumen, que también incluye snapshots y metadatos. Los tamaños pueden cambiar durante el análisis.

Para mantener acotada la memoria del analizador, se conservan los hijos inmediatos y hasta 100 candidatos a archivos grandes, sin cargar todo el árbol en memoria. Al entrar en una subcarpeta se hace un análisis nuevo de esa carpeta.

La estimación de memoria disponible suma páginas libres e inactivas; no equivale a la presión de memoria del Monitor de Actividad. La memoria comprimida está incluida en el uso. La memoria residente por proceso no es sumable directamente por las páginas compartidas. El porcentaje de CPU puede superar el 100% en procesos que usan varios núcleos. No se ejecutan comandos de purga: macOS administra automáticamente cachés y memoria virtual.

El paquete generado se firma localmente (ad hoc), para uso en el Mac de desarrollo. La distribución pública requiere firma Developer ID y notarización.
