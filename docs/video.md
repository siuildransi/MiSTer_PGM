# Documentación Técnica: Motor de Video PGM

El motor de video (`rtl/video/pgm_video.sv`) replica el hardware gráfico de IGS, capaz de manejar múltiples capas y sprites con zoom.

## Especificaciones de Salida
- **Resolución**: 448 x 224 píxeles (basado en el timing de 25MHz).
- **Frecuencia Vertical**: ~60Hz.

## Motor de Sprites (Sprite Engine)

La PGM destaca por su capacidad de escalar sprites mediante un motor de zoom por hardware.

### 1. Escaneo de Líneas (Line Buffering)
Para cumplir con los límites de tiempo reales, el motor utiliza dos **Line Buffers** de 10 bits:
- Mientras un buffer se lee para enviar píxeles a la pantalla, el otro se limpia y rellena con los sprites de la *siguiente* línea.
- Esto permite renderizar hasta **32 sprites por línea** sin parpadeos.

### 2. Algoritmo de Zoom X/Y
El escalado se realiza mediante acumuladores de punto fijo:
- **Zoom vertical (Y)**: Se calcula durante la fase de `SCAN_SPRITES`, determinando qué línea del sprite fuente corresponde a la línea de escaneo actual.
- **Zoom horizontal (X)**: Implementado en el estado `FETCH_WRITE`. 
    - Un factor de `64` representa escala 1:1.
    - Valores menores a 64 amplían el sprite.
    - Valores mayores a 64 reducen el sprite.

## Gestión del Ancho de Banda y Ráfagas SDRAM
Un reto clave en el motor de video es la lectura rápida de datos de sprites. Cada píxel es de **5 bits (bpp)**, y los datos se guardan en la SDRAM empaquetados en palabras de 64 bits:
- **Lectura Optimizada**: Una sola lectura de 64 bits devuelve ~12 píxeles.
- **Interfacing**: El motor de video solicita datos durante el borrado horizontal (H-Blank) para no interferir con la visualización de la línea actual.
- **Acceso Directo**: Los datos de la SDRAM fluyen directamente al `sdram_latch` del motor de video sin pasar por la CPU, maximizando el rendimiento.

## Composición de Buffers (Line Double Buffering)
Para evitar el "tearing" y permitir el escalado, el sistema usa dos memorias RAM de línea:
1. **Fase de Escritura**: El `Sprite Engine` calcula las posiciones X basándose en el zoom y proyecta los píxeles sobre el buffer inactivo.
2. **Fase de Lectura**: El `Mixer` lee el buffer activo sincrónicamente con el reloj de vídeo para generar la señal VGA.
Este diseño garantiza una latencia de renderizado de exactamente 1 línea de escaneo.

## Definición de Registros de Vídeo (vregs)
Los registros de control de vídeo se pasan al módulo como un bus compacto de 512 bits:
- `vregs[47:32]`: Scroll Y del fondo (BG).
- `vregs[63:48]`: Scroll X del fondo (BG).
- `vregs[79:64]`: Scroll Y de la capa de texto (TX).
- `vregs[95:80]`: Scroll X de la capa de texto (TX).
- `vregs[255:0]`: Tabla de Zoom (16 niveles predefinidos).

## Capas de Fondo y Texto (Tilemaps)
- **Capa TX**: Matriz de caracteres de 8x8 píxeles utilizada para la interfaz de usuario.
- **Capa BG**: Fondo principal del juego con soporte para scroll horizontal y vertical de 32x32 píxeles por tile.
- Ambas capas acceden a la VRAM para obtener los índices de tiles y a la SDRAM para los datos de los píxeles reales.

## Mezclador (Mixer)
El mezclador final decide qué píxel mostrar basándose en la prioridad y la transparencia:
1.  **Prioridad 1**: Capa de Texto (si el píxel no es transparente).
2.  **Prioridad 2**: Sprites.
3.  **Prioridad 3**: Capa de Fondo.
4.  **Fallback**: Color de fondo (Backcolor).

Se ha corregido la polaridad de la señal `v_blank_n` para asegurar compatibilidad total con el procesador de vídeo de MiSTer.
