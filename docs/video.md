# Documentación Técnica: Motor de Video PGM

El motor de video (`rtl/video/pgm_video.sv`) es una arquitectura de escaneo de líneas (line-buffer based) diseñada para replicar el hardware de IGS con polifonía de hasta 32 sprites con zoom por línea.

## 📺 Especificaciones de Temporización (Timing)

| Parámetro | Valor Píxeles | Tiempo (~25.175 MHz) |
| :--- | :--- | :--- |
| **H-Active** | 448 | 17.8 µs |
| **H-Front Porch** | 16 | 0.63 µs |
| **H-Sync** | 96 | 3.81 µs |
| **H-Back Porch** | 48 | 1.90 µs |
| **H-Total** | 608 (límite render) / 800 (VGA) | 31.7 µs |
| **V-Active** | 224 | 7.1 ms |
| **V-Total** | 525 | 16.6 ms (60 Hz) |

> **⚠️ ADVERTENCIA**: El motor de video PGM original usa una resolución de 448x224. En el core MiSTer, el reloj `video_clk` de **25.175 MHz** es el estándar. Si se cambia la frecuencia del reloj, se deben recalcular los contadores `h_cnt` y `v_cnt` para mantener la sincronía.

## 🏗️ Arquitectura del Pipeline de Renderizado

El motor opera en un ciclo de 1 línea de retardo:

1.  **Línea N**: El motor escanea los atributos, lee de SDRAM y escribe los píxeles en el **Line Buffer A**.
2.  **Línea N+1**: El motor lee el **Line Buffer A** para el Mixer, mientras prepara la línea N+1 en el **Line Buffer B**.

### Máquina de Estados de Sprites (`sprite_state`)

| Estado | Función Crítica |
| :--- | :--- |
| `SCAN_SPRITES` | Lee la RAM de atributos (128x32 bits). Calcula: `scan_sy_off = ((v_cnt - sy) * zy) >> 6`. |
| `FETCH_REQ` | Genera `ddram_addr` basándose en el `code` del sprite y el `source_y_offset`. |
| `FETCH_WAIT` | Espera `ddram_dout_ready`. El latch `sdram_latch` captura 64 bits (12 píxeles). |
| `FETCH_WRITE` | Realiza el **Zoom X** mediante un acumulador de 8 bits. |

> **⚠️ TRUCO DE IMPLEMENTACIÓN**: El zoom X usa `src_x_accum`. Cuando `src_x_accum >= 64`, avanzamos al siguiente píxel fuente. Esto permite escalas arbitrarias. Si se modifica esta lógica, asegurar que `src_x_whole` no exceda el límite del sprite (48 píxeles).

## 🎨 Gestión de Color y Mixer

### Mezcla de Capas (Orden de Prioridad)

El mixer en la línea 416 de `pgm_video.sv` utiliza un esquema de transparencia por índice:

1.  **Capa TX (Texto)**: Prioridad máxima si el índice de color (bits 3:0) no es `15`.
2.  **Sprites**: Prioridad media si el índice de color (bits 4:0) no es `0`.
3.  **Capa BG (Fondo)**: Prioridad baja.
4.  **Backcolor**: Renderizado si todas las capas anteriores son transparentes.

```verilog
// Lógica de selección del mixer (pgm_video.sv)
if (mix_t_p_w[3:0] != 4'd15) pal_addr <= {5'd1, mix_t_p_w[4:0]}; 
else if (mix_s_data_w[4:0] != 5'd0) pal_addr <= {mix_s_data_w[9:5], mix_s_data_w[4:0]}; 
else pal_addr <= {5'd2, mix_b_p_w}; 
```

### Palette RAM (RGB555)
La paleta se almacena como `dpram_dc`. Cada entrada es de 16 bits:
- `[14:10]`: Rojo (5 bits)
- `[9:5]`: Verde (5 bits)
- `[4:0]`: Azul (5 bits)
El core expande esto a RGB888 añadiendo `3'b0` al final de cada canal.

## 🧱 Engine de Tiles (Capas TX y BG)

### Diferencias entre Capas

| Característica | Capa TX | Capa BG |
| :--- | :--- | :--- |
| Tamaño de Tile | 8x8 | 32x32 |
| VRAM Base | `0x2000` | `0x0000` |
| Píxeles por lectura SDRAM | 8 píxeles (4bpp) | 10 píxeles (5bpp) |
| Scroll | Pixel-exact | Pixel-exact |

> **⚠️ NOTA CRÍTICA SOBRE SDRAM**: Las capas de fondo y sprites comparten el bus SDRAM a través del árbitro en `PGM.sv`. El motor de video tiene prioridad sobre el audio pero **cede** ante la CPU si esta solicita el bus para cargar código. Esto puede provocar "esperas" que el motor de video debe gestionar mediante buffers.

## ⚠️ Evitar Erreores Comunes (Manual de Supervivencia)

1.  **Ancho de Bits**: El acumulador de zoom X debe manejar desbordamientos correctamente. Actualmente usa 8 bits (`src_x_accum`) y 6 bits (`src_x_whole`). Si se amplía el tamaño de los sprites de 48px, se deben ampliar estos registros.
2.  **Señales Combinacionales**: NO usar asignaciones bloqueantes (`=`) para lógica que dependa de `v_cnt` o `h_cnt` dentro del bloque síncrono. Usar los wires `_w` declarados al principio del módulo.
3.  **H-Blanking**: El proceso `SCAN_SPRITES` comienza en `h_cnt == 640`. Si se modifica el timing horizontal, asegurar que hay suficiente tiempo para procesar los 256 atributos antes de que comience el área activa de la siguiente línea.
4.  **Literales**: Siempre usar literales con tamaño explícito (ej: `4'd15` en lugar de `15`) para evitar que el sintetizador asuma 32 bits y consuma lógica innecesaria.
