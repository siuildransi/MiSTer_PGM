# Documentación Técnica: Sistema de Sonido PGM

El sistema de sonido utiliza una arquitectura secundaria basada en un procesador Zilog Z80 y un sintetizador Wavetable ICS2115.

## Arquitectura del Mezclador TDM (Time Division Multiplexing)
Debido a la alta polifonía (32 voces) y para optimizar los recursos de la FPGA, el módulo `ics2115.sv` utiliza un motor de mezcla por división de tiempo:
- **Ciclo de Mezcla**: En cada intervalo de muestreo (~33kHz), el motor recorre secuencialmente las voces de la 0 a la 31.
- **Estados de Voz**: Una FSM interna gestiona cuatro estados por voz:
    - `TDM_IDLE`: Reinicio de acumuladores y comprobación de activación.
    - `TDM_FETCH`: Solicitud de ráfaga a la SDRAM externa.
    - `TDM_MIX`: Acumulación del valor de 16 bits en un sumador de 24 bits.
    - `TDM_FINISH`: Aplicación de saturación aritmética para evitar distorsión (clipping).

## Protocolo de Interrupciones NMI (Handshake)
Para asegurar una baja latencia en los comandos de sonido, se ha implementado un sistema de interrupción no enmascarable (NMI):
1. **Trigger**: Cuando la CPU 68k escribe en el registro `0xC00002` (Sound Latch 1), el hardware genera un pulso `NMI_n` al Z80.
2. **Respuesta**: El Z80 salta a la dirección `0x0066` y lee el puerto I/O `0x00`.
3. **Ack**: Al leer el puerto `0x00`, el hardware limpia automáticamente la petición de NMI, permitiendo recibir el siguiente comando.

## Mapa de Registros del ICS2115
El acceso se realiza de forma indirecta mediante dos puertos físicos:
- **Puertos Físicos**: `0x8000` (Dirección) y `0x8001` (Datos).
- **Registros Indirectos Clave**:
    - `0x08`: Selección de Voz (0-31). Las operaciones posteriores afectarán a la voz elegida aquí.
    - `0x40`: Control de Voz (Bit 0: Play/Stop).
    - `0x41-0x43`: Dirección de inicio de muestra (24 bits).
    - `0x44-0x45`: Incremento de fase (Frecuencia/Pitch).

## Gestión de Memoria de Muestras (SDRAM)
El chip de sonido tiene prioridad baja en el árbitro de SDRAM (`ARB_AUDIO`). Utiliza lecturas de ráfaga (64 bits) que contienen múltiples muestras comprimidas o empaquetadas, minimizando el impacto en el ancho de banda del sistema de vídeo.
