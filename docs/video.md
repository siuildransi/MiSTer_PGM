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
