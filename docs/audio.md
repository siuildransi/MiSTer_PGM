# Documentación Técnica: Sistema de Sonido PGM

El sistema de sonido utiliza una arquitectura secundaria basada en un procesador Zilog Z80 y un sintetizador Wavetable ICS2115.

## Estructura de Control (Z80)
- **Reloj**: 8.468 MHz.
- **Memoria**: 64KB de RAM local cargada a través del puerto `ioctl` (Index 1).
- **Entradas/Salidas**:
    - **Port 0x00**: Lectura del Latch 1 (Comandos de la 68k) / Escritura al Latch 2 (Estado del Z80).
    - **Port 0x8000-0x8003**: Interfaz de control del chip ICS2115.

## Comunicación Inter-CPU (Sound Latches)

| Dirección 68k | Dirección Z80 | Función |
| :--- | :--- | :--- |
| `0xC00002` (W) | `I/O 0x00` (R) | **Sound Latch 1**: Comandos enviados por el juego. |
| `0xC00004` (R) | `I/O 0x00` (W) | **Sound Latch 2**: Respuesta de estado del Z80. |

## Sintetizador ICS2115 (Wavetable MIDI)
- Soporta hasta **32 voces polifónicas**.
- Cada voz puede leer muestras PCM de la SDRAM externa.
- La comunicación Z80 <-> ICS2115 es de 8 bits a través de puertos I/O.
- El módulo `ics2115.sv` utiliza el canal `ARB_AUDIO` del árbitro de SDRAM para precargar muestras en buffers locales.

## Flujo de Audio
1. La 68k escribe un ID de sonido en `C00002`.
2. El Z80 lee el ID, busca la configuración de voz en su RAM.
3. El Z80 programa el ICS2115 con la dirección de la muestra y frecuencia.
4. El ICS2115 solicita datos a la SDRAM y genera la señal estéreo de 16 bits.
