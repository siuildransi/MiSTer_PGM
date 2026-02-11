# Documentación Técnica: Memoria y Arbitraje PGM

Este documento detalla la organización de la memoria y la lógica de acceso compartida del núcleo PGM.

## Mapa de Direcciones (CPU 68000)

La CPU principal (68k) direcciona un espacio de 24 bits. El mapeo implementado en `PGM.sv` es el siguiente:

| Rango de Direcciones | Componente | Descripción |
| :--- | :--- | :--- |
| `0x000000 - 0x0FFFFF` | **BIOS** | Cargado desde SDRAM (`bios_sel`) |
| `0x100000 - 0x3FFFFF` | **P-ROM** | Código principal del juego en SDRAM (`prom_sel`) |
| `0x800000 - 0x81FFFF` | **Work RAM** | 128KB de RAM de trabajo (BRAM interna) |
| `0x900000 - 0x907FFF` | **VRAM** | Memoria de video (Tilemaps, Atributos) |
| `0xA00000 - 0xA011FF` | **Palette RAM** | Almacenamiento de colores (3k bytes) |
| `0xB00000 - 0xB0FFFF` | **Registers** | Registros de control de video y Zoom |
| `0xC00000 - 0xC0FFFF` | **I/O & Sound** | Latches de sonido y puertos de control |

## Arbitraje de SDRAM (`ARB`)

Dado que múltiples componentes necesitan acceder a la SDRAM externa, se utiliza una máquina de estados (FSM) a 50MHz para gestionar las prioridades.

### Estados del Árbitro:
1.  **ARB_IDLE**: Estado de espera detectando peticiones.
2.  **ARB_CPU**: Prioridad cuando la 68k necesita instrucciones o datos (`bios_sel` / `prom_sel`).
3.  **ARB_VIDEO**: Acceso del motor de video para buscar datos de sprites (A-ROM / B-ROM).
4.  **ARB_AUDIO**: Acceso del chip ICS2115 para leer muestras de sonido (S-ROM).

### Lógica de Prioridad:
`CPU > VIDEO > AUDIO`

El audio tiene la prioridad más baja pero cuenta con buffers internos en el ICS2115 para evitar cortes durante ráfagas de acceso de video.

## Memoria Dual-Port (`dpram_dc`)
Se utiliza `dpram_dc.sv` para cruzar dominios de reloj (Clock Domain Crossing):
- **WRAM**: La 68k escribe a 20MHz mientras el motor de video lee a ~25MHz para procesar sprites.
- **VRAM / PAL**: Permite actualizaciones de la CPU sin interrumpir la generación de la señal de video.
