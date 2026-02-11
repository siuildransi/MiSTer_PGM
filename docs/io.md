# Documentación Técnica: Controles e I/O PGM

Este documento describe cómo se mapean las entradas físicas del MiSTer a los registros lógicos de la placa PGM.

## Registro de Controles de Jugador (`0xC08000`)

Este registro de 16 bits contiene el estado de los joysticks y botones principales. Todas las señales son **Active Low** (0 = Presionado).

| Bit | Jugador 1 (Byte Bajo) | Jugador 2 (Byte Alto) |
| :--- | :--- | :--- |
| 0 | Arriba | Arriba |
| 1 | Abajo | Abajo |
| 2 | Izquierda | Izquierda |
| 3 | Derecha | Derecha |
| 4 | Botón A (B1) | Botón A (B1) |
| 5 | Botón B (B2) | Botón B (B2) |
| 6 | Botón C (B3) | Botón C (B3) |
| 7 | Botón D (B4) | Botón D (B4) |

## Registro de Sistema (`0xC08004`)

Gestiona las funciones generales de la máquina.

| Bit | Función MiSTer | Descripción PGM |
| :--- | :--- | :--- |
| 0 | `Select` (P1) | Coin 1 |
| 1 | `Select` (P2) | Coin 2 |
| 2 | `Start` (P1) | Start 1 |
| 3 | `Start` (P2) | Start 2 |
| 4 | - | Test (Botón de servicio) |
| 5 | - | Service |

## Configuración del Framework (`emu.sv`)
El módulo `emu.sv` conecta las señales `joy0` y `joy1` del framework MiSTer directamente al módulo `PGM`. La inversión de los bits (para cumplir con Active Low) se realiza internamente en `PGM.sv` mediante:
```verilog
wire [15:0] pgm_inputs = ~{ joystick_1[7:0], joystick_0[7:0] };
```
Esta implementación asegura que no haya latencia añadida en la respuesta de los controles.
