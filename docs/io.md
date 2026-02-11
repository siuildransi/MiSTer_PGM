# Documentación Técnica: Controles e I/O PGM

Este documento describe cómo se mapean las entradas físicas del MiSTer a los registros lógicos de la placa PGM.

## Flujo de Señales

```
MiSTer Framework          emu.sv                PGM.sv
─────────────────   ──────────────────   ──────────────────────
joy0[31:0]  ────→   .joystick_0(joy0) ──→  pgm_inputs (Active Low)
joy1[31:0]  ────→   .joystick_1(joy1) ──→  pgm_system (Active Low)
status[31:0] ───→   .joy_buttons()    ──→  (reservado)
```

## Conexión en `emu.sv`

```verilog
// hps_io recibe los joysticks del framework MiSTer
hps_io #(...) hps_io (
    .joystick_0(joy0),      // wire [31:0]
    .joystick_1(joy1),      // wire [31:0]
    ...
);

// Se pasan directamente al core PGM
PGM pgm_core (
    .joystick_0(joy0),
    .joystick_1(joy1),
    .joy_buttons(status[15:0]),
    ...
);
```

> **⚠️ NOTA**: Los puertos `joystick_0`, `joystick_1` y `joy_buttons` fueron añadidos al módulo `PGM` en la rama `dev-macbook-pgm-core`. La rama `main` original NO incluía estos puertos. Si se hace merge, verificar que `PGM.sv` declare estos puertos en su cabecera.

## Registro de Controles de Jugador (`0xC08000`)

**Archivo**: `PGM.sv`, variable `pgm_inputs`.  
**Dirección decodificada**: `adr[15:1] == 15'h4000` dentro de `io_sel`.

Este registro de 16 bits contiene el estado de los joysticks y botones principales. Todas las señales son **Active Low** (0 = Presionado). La inversión se realiza en hardware:

```verilog
// PGM.sv — La inversión ~ convierte Active High (MiSTer) a Active Low (PGM)
wire [15:0] pgm_inputs = ~{
    joystick_1[7], joystick_1[6], joystick_1[5], joystick_1[4], 
    joystick_1[3], joystick_1[2], joystick_1[1], joystick_1[0], // P2 (byte alto)
    joystick_0[7], joystick_0[6], joystick_0[5], joystick_0[4], 
    joystick_0[3], joystick_0[2], joystick_0[1], joystick_0[0]  // P1 (byte bajo)
};
```

| Bit | Jugador 1 (Byte Bajo) | Jugador 2 (Byte Alto) | Señal MiSTer |
| :--- | :--- | :--- | :--- |
| 0 | Arriba | Arriba | `joystick_X[0]` |
| 1 | Abajo | Abajo | `joystick_X[1]` |
| 2 | Izquierda | Izquierda | `joystick_X[2]` |
| 3 | Derecha | Derecha | `joystick_X[3]` |
| 4 | Botón A (B1) | Botón A (B1) | `joystick_X[4]` |
| 5 | Botón B (B2) | Botón B (B2) | `joystick_X[5]` |
| 6 | Botón C (B3) | Botón C (B3) | `joystick_X[6]` |
| 7 | Botón D (B4) | Botón D (B4) | `joystick_X[7]` |

## Registro de Sistema (`0xC08004`)

**Archivo**: `PGM.sv`, variable `pgm_system`.  
**Dirección decodificada**: `adr[15:1] == 15'h4002` dentro de `io_sel`.

```verilog
// PGM.sv
wire [15:0] pgm_system = ~{
    8'h00,                              // Byte alto: sin usar
    4'b0000,                            // Bits 7-4: reservados
    joystick_1[8], joystick_0[8],       // Bits 3,2: Start 2, Start 1
    joystick_1[9], joystick_0[9]        // Bits 1,0: Coin 2, Coin 1
};
```

| Bit | Función MiSTer | Función PGM | Señal MiSTer |
| :--- | :--- | :--- | :--- |
| 0 | Select (P1) | Coin 1 | `joystick_0[9]` |
| 1 | Select (P2) | Coin 2 | `joystick_1[9]` |
| 2 | Start (P1) | Start 1 | `joystick_0[8]` |
| 3 | Start (P2) | Start 2 | `joystick_1[8]` |
| 4 | — | Test | No conectado |
| 5 | — | Service | No conectado |
| 6-7 | — | Reservados | — |
| 8-15 | — | Sin usar | Siempre `0xFF` tras inversión |

> **⚠️ IMPORTANTE**: Los bits 4 (Test) y 5 (Service) NO están conectados actualmente. Para acceder al modo Test/Service se necesitaría añadir mappings adicionales desde OSD/status.

## Mapa Completo de Decodificación I/O

Toda la lógica I/O se decodifica en el bloque combinacional `always @(*)` de `PGM.sv`. La selección primaria es `io_sel = (adr[23:16] == 8'hC0)`:

| Condición (`adr[15:1]`) | Dirección | Operación | Dato |
| :--- | :--- | :--- | :--- |
| `15'h0001` | `0xC00002` | Lectura | `{8'h00, sound_latch_1}` |
| `15'h0002` | `0xC00004` | Lectura | `{8'h00, sound_latch_2}` |
| `15'h4000` | `0xC08000` | Lectura | `pgm_inputs` |
| `15'h4002` | `0xC08004` | Lectura | `pgm_system` |
| Otros | — | Lectura | `16'hFFFF` (bus por defecto) |

### Escrituras I/O (Bloque secuencial `always @(posedge fixed_20m_clk)`)

| Condición | Dirección | Efecto |
| :--- | :--- | :--- |
| `adr[15:1] == 15'h0001 && !lds_n` | `0xC00002` W | Escribe `sound_latch_1` + activa `z80_nmi_req` |

> **⚠️ NOTA**: La escritura del latch activa automáticamente la NMI del Z80. El acknowledge (`z80_nmi_ack_8m`) se sincroniza desde 8MHz a 20MHz mediante un flip-flop de cruce de dominio (`z80_nmi_ack_20`). **NO eliminar** esta sincronización.

## Chip de Protección IGS027A (ARM7 HLE)

**Archivo**: `rtl/protection/igs027a_hle.sv`  
**Dirección decodificada**: `prot_sel = (adr[23:16] == 8'h40)` (`0x400000 - 0x40FFFF`).

Este módulo emula en alto nivel (HLE) las respuestas del coprocesador ARM7 (Type 3) utilizado en juegos como *Demon Front*. La comunicación se realiza mediante un handshake de registros.

### Mapa de Registros (`0x400000`)

| Dirección (68k) | Acceso | Función |
| :--- | :--- | :--- |
| `0x400000` | W | **Command Register**: Dispara el procesamiento HLE. |
| `0x400000` | R | **Status Register**: Bit 0 indica Ready (1) o Busy (0). |
| `0x400002` | R/W | **Data Register 0**: Parámetro de entrada / Respuesta de salida. |
| `0x400004` | R/W | **Data Register 1** |
| `0x400006` | R/W | **Data Register 2** |

### Comandos HLE Soportados (Demon Front)

| Comando | Función | Respuesta Esperada (`Data 0`) |
| :--- | :--- | :--- |
| `0x0011` | Inicialización / Check | `0x55AA` |
| `0x0012` | Escritura RAM interna | Ack (Status = Done) |
| `0x0013` | Lectura RAM interna | Dato almacenado |
| `0x0014` | Transformación de Sprites | Bypass (Done) |

> **⚠️ NOTA TÉCNICA**: El módulo `igs027a_hle` genera su propia señal `DTACK`. Al acceder al rango `0x400000`, el core delega el control de espera de la CPU a este módulo. Una falla en la lógica de `dtack_n` interna del módulo de protección colgará el core por completo.

