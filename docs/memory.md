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

## Implementación de RAM Dual-Port Real (`dpram_dc.sv`)
A diferencia de las implementaciones estándar, nuestro módulo `dpram_dc` ha sido optimizado para soportar escritura simultánea en ambos puertos (True Dual Port RAM). Esto es crítico para el bus de sonido (Z80), permitiendo:
- **Puerto A**: Carga de datos desde MiSTer vía `ioctl` a 50MHz.
- **Puerto B**: Acceso de lectura/escritura del Z80 a 8.46MHz.
Quartus infiere automáticamente bloques **M10K** gracias al atributo `synthesis syn_ramstyle = "no_rw_check, M10K"`, garantizando eficiencia en el uso de celdas lógicas.

## Arbitraje SDRAM y Eficiencia de Bus
El bus de datos hacia la SDRAM es de **64 bits**, lo que permite optimizar las lecturas:
- **Ráfaga Dinámica**: Cada acceso de 64 bits carga el equivalente a 4 palabras de 16 bits.
- **Buffers de Alineación**: Se utilizan registros intermedios para alinear las peticiones de 16 bits de la CPU 68k con el bus de 64 bits de la SDRAM, evitando esperas innecesarias (wait states).

| Señal de Árbitro | Origen | Reloj | Función |
| :--- | :--- | :--- | :--- |
| `sdram_req` | CPU 68k | 20MHz | Petición de código o datos BIOS/PROM. |
| `vid_rd` | Video Engine | 25MHz | Solicitud de gráficos de sprites/tiles. |
| `sound_rd` | ICS2115 | 8MHz | Lectura de muestras wavetable. |

## Latencia y Sincronización (CDC)
Dado que el árbitro corre a 50MHz y las peticiones vienen de dominios de 20MHz, 25MHz y 8MHz, se implementa una lógica de sincronización de tres etapas (`s1`, `s2`) para evitar problemas de metaestabilidad durante el cruce de dominios de reloj.
