# Documentación Técnica: Sistema de Sonido PGM

El sistema de sonido utiliza una arquitectura secundaria basada en un procesador Zilog Z80 y un sintetizador Wavetable ICS2115.

## Arquitectura General

```
68k (20MHz)  ──→  Sound Latch 1 (0xC00002)  ──→  Z80 (8MHz)  ──→  ICS2115
                                                      ↑                  ↓
                 Sound Latch 2 (0xC00004)  ←──────────┘           SDRAM (muestras)
                                                                       ↓
                                                                  Audio Out (L/R)
```

## Protocolo de Interrupciones NMI (Handshake)
Para asegurar una baja latencia en los comandos de sonido, se ha implementado un sistema de interrupción no enmascarable (NMI):
1. **Trigger**: Cuando la CPU 68k escribe en el registro `0xC00002` (Sound Latch 1), el hardware genera un pulso `NMI_n` al Z80.
2. **Respuesta**: El Z80 salta a la dirección `0x0066` y lee el puerto I/O `0x00`.
3. **Ack**: Al leer el puerto `0x00`, el hardware limpia automáticamente la petición de NMI, permitiendo recibir el siguiente comando.

## Mapa de I/O del Z80

| Puerto Z80 | Dirección | Función |
| :--- | :--- | :--- |
| `0x00` | Lectura | Leer Sound Latch 1 (datos desde 68k) / Ack NMI |
| `0x00` | Escritura | Escribir Sound Latch 2 (respuesta hacia 68k) |
| `0x01` | Lectura | Estado de IRQ |
| `0x02` | L/E | ICS2115 Registro de Dirección (Indirecto) |
| `0x03` | L/E | ICS2115 Registro de Datos (Indirecto) |

## Mapa de Registros del ICS2115
El acceso se realiza de forma indirecta mediante dos puertos físicos Z80:
- **Puerto `0x02`**: Selecciona el registro interno a acceder (Asignar `z_adr[0] = 0` al core).
- **Puerto `0x03`**: Lee/escribe el valor del registro (Asignar `z_adr[0] = 1` al core).

> **⚠️ NOTA TÉCNICA**: El core `ics2115.sv` utiliza un puerto `.addr(1:0)` donde solo se deben usar los bits bajos. En `PGM.sv`, la conexión debe ser `.addr({1'b0, z_adr[0]})` para asegurar que los puertos I/O `0x02` y `0x03` se mapeen a los índices `0` y `1` respectivamente. Usar `z_adr[1:0]` mapearía incorrectamente a `2` y `3`.

### Registros Indirectos Clave

| Registro | Función | Descripción |
| :--- | :--- | :--- |
| `0x08` | Selección de Voz | Selecciona la voz activa (0-31) |
| `0x40` | Control de Voz | Bit 0: Play/Stop |
| `0x41` | Dirección Inicio [7:0] | Byte bajo de la dirección de muestra |
| `0x42` | Dirección Inicio [15:8] | Byte medio de la dirección de muestra |
| `0x43` | Dirección Inicio [23:16] | Byte alto de la dirección de muestra |
| `0x44-0x45` | Incremento de Fase | Controla la frecuencia/pitch de la voz |

## Arquitectura del Mezclador TDM (Time Division Multiplexing)
Debido a la alta polifonía (32 voces) y para optimizar los recursos de la FPGA, el módulo `ics2115.sv` utiliza un motor de mezcla por división de tiempo:
- **Ciclo de Mezcla**: En cada intervalo de muestreo, el motor recorre secuencialmente las voces de la 0 a la 31.
- **Estados de Voz**: Una FSM interna gestiona cuatro estados por voz:
    - `TDM_IDLE`: Reinicio de acumuladores y comprobación de activación.
    - `TDM_FETCH`: Solicitud de lectura a la SDRAM externa.
    - `TDM_MIX`: Acumulación del valor de 16 bits en un sumador de 24 bits con signo.
    - `TDM_FINISH`: Aplicación de saturación aritmética (clipping a ±32767) para evitar distorsión.

## Gestión de Memoria de Muestras (SDRAM)
El chip de sonido tiene prioridad baja en el árbitro de SDRAM (`ARB_AUDIO`). Utiliza lecturas de ráfaga (64 bits) que contienen múltiples muestras empaquetadas, minimizando el impacto en el ancho de banda del sistema de vídeo.

### Handshake CDC (50MHz → 8MHz)
Para sincronizar el acknowledge de la SDRAM (dominio 50MHz) con el Z80 (dominio 8MHz), se implementa un mecanismo **Request-Hold-Ack**:
1. El árbitro (50MHz) aserta `sound_ack_hold` cuando los datos están listos.
2. `sound_ack_hold` se sincroniza al dominio 8MHz con dos flip-flops (`sound_ack_s1`, `sound_ack_s2`).
3. El ICS2115 (8MHz) recibe el ack y baja su petición `sdram_rd`.
4. El árbitro detecta la caída de la petición y limpia `sound_ack_hold`.
