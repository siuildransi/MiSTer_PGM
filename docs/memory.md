# Documentación Técnica: Memoria y Arbitraje PGM

Este documento detalla la organización de la memoria y la lógica de acceso compartida del núcleo PGM.

## Mapa de Direcciones (CPU 68000)

La CPU principal (68k) direcciona un espacio de 24 bits. La decodificación se realiza en `PGM.sv` con señales `_sel`:

| Rango de Direcciones | Señal `_sel` | Decodificación Verilog | Componente |
| :--- | :--- | :--- | :--- |
| `0x000000 - 0x0FFFFF` | `bios_sel` | `adr[23:20] == 4'h0` | BIOS (SDRAM) |
| `0x100000 - 0x3FFFFF` | `prom_sel` | `adr[23:20] >= 4'h1 && <= 4'h3` | P-ROM (SDRAM) |
| `0x800000 - 0x81FFFF` | `ram_sel` | `adr[23:17] == 7'b1000000` | Work RAM (BRAM) |
| `0x900000 - 0x907FFF` | `vram_sel` | `adr[23:17] == 7'b1001000` | VRAM |
| `0xA00000 - 0xA011FF` | `pal_sel` | `adr[23:17] == 7'b1010000` | Palette RAM |
| `0xB00000 - 0xB0FFFF` | `vreg_sel` | `adr[23:16] == 8'hB0` | Video Registers |
| `0xC00000 - 0xC0FFFF` | `io_sel` | `adr[23:16] == 8'hC0` | I/O & Sound |

> **⚠️ IMPORTANTE**: Las señales `_sel` se evalúan en un bloque **combinacional** (`always @(*)`). Cambiar la lógica de prioridad del `if-else if` puede alterar el comportamiento del bus. El orden actual es: `ram_sel` → `bios_sel/prom_sel` → `vram_sel` → `pal_sel` → `io_sel`.

### Detalle del Espacio I/O (`0xC00000`)

Documentado en detalle en [docs/io.md](io.md).

| Dirección | R/W | Función |
| :--- | :--- | :--- |
| `0xC00002` | R | Leer Sound Latch 1 (datos desde Z80) |
| `0xC00002` | W | Escribir Sound Latch 1 + Trigger NMI al Z80 |
| `0xC00004` | R | Leer Sound Latch 2 (respuesta del Z80) |
| `0xC08000` | R | Entradas P1 (byte bajo) y P2 (byte alto) |
| `0xC08004` | R | Entradas de sistema (Coin, Start) |

## DTACK y Acceso a Memoria

La lógica de `cpu68k_dtack_n` determina cuándo la CPU recibe datos válidos:

```verilog
// PGM.sv — Bloque combinacional
always @(*) begin
    cpu68k_dtack_n = 1'b1;        // Por defecto: CPU espera
    cpu68k_din = 16'hFFFF;        // Bus por defecto
    sdram_req = 1'b0;

    if (!as_n) begin
        if (ram_sel) begin
            cpu68k_dtack_n = 1'b0;             // RAM interna: 0 wait states
            cpu68k_din = {wram_rd_h, wram_rd_l};
        end else if (bios_sel || prom_sel) begin
            sdram_req = 1'b1;                  // SDRAM: espera ack del árbitro
            cpu68k_din = sdram_data;
            if (sdram_ack) cpu68k_dtack_n = 1'b0;
        end else if (vram_sel) ...             // VRAM: 0 wait states
        ...
    end
end
```

> **⚠️ NOTA**: `ram_sel` tiene **0 wait states** (DTACK inmediato) porque usa BRAM interna. Los accesos a SDRAM (`bios_sel`/`prom_sel`) requieren esperar el acknowledge del árbitro, lo cual puede tardar varios ciclos dependiendo de la contención.

## RAM de Trabajo (Work RAM) — 128KB

Implementada como **dos instancias** de `dpram_dc` (High byte + Low byte) para soportar accesos parciales del 68000:

```verilog
// PGM.sv
// Señales de escritura parcial controladas por UDS_n/LDS_n del 68k
wire wram_we_h = ram_sel && !rw_n && !as_n && !uds_n;  // Byte alto [15:8]
wire wram_we_l = ram_sel && !rw_n && !as_n && !lds_n;  // Byte bajo [7:0]

dpram_dc #(16, 8) wram_hi_inst (
    .clk_a(fixed_20m_clk), .we_a(wram_we_h), .addr_a(adr[16:1]),  // Puerto A: CPU
    .clk_b(video_clk),     .we_b(1'b0),      .addr_b(...)          // Puerto B: Video (solo lectura)
);
```

> **⚠️ IMPORTANTE**: El Puerto B de la Work RAM es **solo lectura** (`we_b(1'b0)`). Se usa para que el motor de video lea datos de sprites sin interferir con la CPU. **NO habilitar escritura** en el Puerto B.

## VRAM y Palette RAM

| RAM | Parámetros `dpram_dc` | Addr Bits | Data Bits | Puerto A | Puerto B |
| :--- | :--- | :--- | :--- | :--- | :--- |
| VRAM | `#(14, 16)` | 14 bits | 16 bits | CPU 68k (20MHz) W | Video (video_clk) R |
| Palette | `#(11, 16)` | 11 bits | 16 bits | CPU 68k (20MHz) W | Video (video_clk) R |

> **⚠️ NOTA sobre Palette**: La dirección en el código usa `adr[11:1]` (no `adr[12:1]`), dando un rango efectivo de 2048 words = 4096 bytes. El rango `0xA00000-0xA011FF` del hardware original es ~4.5KB, así que el tamaño actual es ligeramente inferior.

## Video Registers

Los registros de vídeo se almacenan en dos arrays internos (no BRAM):
```verilog
// PGM.sv
reg [15:0] zoom_table [0:15];   // 16 entradas de zoom predefinidas
reg [15:0] vid_regs   [0:15];   // Registros de control (scroll, etc.)
```

Se empaquetan en un bus de 512 bits para pasar al módulo de video:
```verilog
// zoom_table → vregs[255:0] (posiciones 0-15, 16 bits cada una)
// vid_regs   → vregs[511:256] (posiciones 16-31, 16 bits cada una)
assign vregs_packed[i*16 +: 16] = zoom_table[i];       // i = 0..15
assign vregs_packed[(16+i)*16 +: 16] = vid_regs[i];    // i = 0..15
```

Escritura desde la CPU:
```verilog
if (vreg_sel) begin
    if (adr[15:12] == 4'h2) zoom_table[adr[4:1]] <= d_out; // 0xB020xx → zoom
    else vid_regs[adr[4:1]] <= d_out;                        // 0xB000xx → regs
end
```

## Arbitraje de SDRAM

### Arquitectura del Árbitro

El árbitro reside en `PGM.sv` y opera en el dominio de 50MHz:

```
                ┌──────────────┐
sdram_req ──→   │              │ ──→ ddram_addr
 (CPU, 20MHz)   │   ÁRBITRO    │ ──→ ddram_rd
vid_rd    ──→   │   FSM        │ ──→ ddram_we
 (Video, 25MHz) │   (50MHz)    │
sound_rd  ──→   │              │ ←── ddram_dout
 (Audio, 8MHz)  └──────────────┘ ←── ddram_dout_ready
```

### Estados del Árbitro

| Estado | Valor | Condición de Entrada | Acción |
| :--- | :--- | :--- | :--- |
| `ARB_IDLE` | `2'd0` | Sin peticiones pendientes | Escanea peticiones por prioridad |
| `ARB_CPU` | `2'd1` | `sdram_req_s2` activo | Lee BIOS/P-ROM, guarda en `sdram_buf` |
| `ARB_VIDEO` | `2'd2` | `vid_rd_s2` activo | Lee gráficos sprites/tiles |
| `ARB_AUDIO` | `2'd3` | `sound_rd_s2` (flanco) | Lee muestras de sonido |

### Prioridad
```
CPU > VIDEO > AUDIO
```

> **⚠️ NOTA**: El audio usa **detección de flanco** (`sound_rd_s2 && !sound_rd_last`) para evitar lecturas repetidas. El video y CPU usan detección de nivel. **NO cambiar** la detección de audio a nivel o se producirán lecturas infinitas.

### Buffer de Lectura CPU

Las lecturas de SDRAM devuelven 64 bits. La CPU selecciona la palabra de 16 bits correcta:

```verilog
// PGM.sv — Selección de palabra dentro de la ráfaga de 64 bits
assign sdram_data = (adr[2:1] == 2'd0) ? sdram_buf[15:0]  :
                    (adr[2:1] == 2'd1) ? sdram_buf[31:16] :
                    (adr[2:1] == 2'd2) ? sdram_buf[47:32] : sdram_buf[63:48];
```

### Multiplexor de Dirección Física

```verilog
assign ddram_addr = ioctl_download ? {5'b0, ioctl_addr[26:3]} :
                    (arb_state == ARB_CPU)   ? {5'b0, adr[23:3]} : 
                    (arb_state == ARB_AUDIO) ? sound_addr : vid_addr;
```

> **⚠️ IMPORTANTE**: Durante `ioctl_download`, el árbitro queda en `ARB_IDLE` y el loader tiene acceso directo al bus. Las CPUs están en reset durante la carga (`reset = RESET || ioctl_download`).

## Sincronización CDC (Clock Domain Crossing)

### Peticiones → 50MHz (Doble Flip-Flop)

Todas las peticiones se sincronizan al dominio del árbitro con **dos flip-flops** en cascada:

```verilog
// Ejemplo: CPU request (20MHz → 50MHz)
reg  sdram_req_s1, sdram_req_s2;
always @(posedge fixed_50m_clk) {sdram_req_s2, sdram_req_s1} <= {sdram_req_s1, sdram_req};
```

Se aplica el mismo patrón a `vid_rd` y `sound_rd`.

### Acknowledges ← 50MHz

| Dirección | Mecanismo | Señales |
| :--- | :--- | :--- |
| 50MHz → 20MHz (CPU) | Doble FF | `sdram_ack_50` → `sdram_ack_s1` → `sdram_ack_s2` |
| 50MHz → 8MHz (Audio) | **Hold-Ack** | `sound_ack_hold` → `sound_ack_s1` → `sound_ack_s2` |

> **⚠️ CRÍTICO**: El audio ack usa un mecanismo **Request-Hold-Ack** porque el dominio 8MHz es demasiado lento para capturar un pulso de un ciclo a 50MHz. Ver [docs/audio.md](audio.md) para detalles completos. **NO simplificar** a un pulso simple como el del CPU.

## Implementación de `dpram_dc.sv`

True Dual-Port RAM con dos dominios de reloj independientes:

```verilog
module dpram_dc #(parameter ADDR_WIDTH=16, parameter DATA_WIDTH=8) (
    // Puerto A: clk_a, we_a, addr_a, din_a, dout_a
    // Puerto B: clk_b, we_b, addr_b, din_b, dout_b
);
    reg [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1]
        /* synthesis syn_ramstyle = "no_rw_check, M10K" */;
```

> **⚠️ NOTA**: El atributo `syn_ramstyle = "no_rw_check, M10K"` es **esencial** para que Quartus infiera bloques de memoria M10K del Cyclone V en lugar de usar celdas lógicas. Eliminarlo causaría un consumo excesivo de recursos FPGA.

### Instancias en el Proyecto

| Instancia | Params | Puerto A | Puerto B | Uso |
| :--- | :--- | :--- | :--- | :--- |
| `wram_hi_inst` | `#(16, 8)` | CPU 68k (20MHz) | Video (video_clk) | Work RAM byte alto |
| `wram_lo_inst` | `#(16, 8)` | CPU 68k (20MHz) | Video (video_clk) | Work RAM byte bajo |
| `vram_inst` | `#(14, 16)` | CPU 68k (20MHz) | Video (video_clk) | VRAM |
| `pal_inst` | `#(11, 16)` | CPU 68k (20MHz) | Video (video_clk) | Palette |
| `sound_ram` | `#(16, 8)` | Loader (50MHz) | Z80 (8MHz) | Sound RAM 64KB |
