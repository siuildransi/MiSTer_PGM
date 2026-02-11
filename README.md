# MiSTer PGM Core Development

Este repositorio contiene la implementación del hardware de la placa arcade PGM (PolyGame Master) de IGS para la plataforma MiSTer FPGA.

## 🏗️ Arquitectura del Sistema

El núcleo emula fielmente los componentes principales de la arquitectura original, optimizando el uso de recursos para la FPGA Cyclone V.

### 1. Procesamiento (CPUs)
- **CPU Principal**: Motorola 68000 (implementada mediante el core `fx68k`). Corre a ~20MHz y gestiona la lógica del juego, las listas de visualización y el arbitraje de recursos.
- **CPU de Sonido**: Zilog Z80 (implementada mediante `T80s`). Corre a ~8.4MHz y se encarga exclusivamente de la música y efectos, comunicándose con el chip ICS2115.
- **Procesador de Protección (Planificado)**: ARM7 (ASIC). Se implementará mediante **HLE (High Level Emulation)** para replicar los algoritmos de protección sin la carga de emular un procesador ARM completo.

### 2. Sistema de Video (`rtl/video/pgm_video.sv`)
El motor de video es una de las partes más avanzadas del core, replicando las capacidades únicas de la PGM:
- **Planos de Scroll**: Soporte para capas de fondo y texto con transparencia.
- **Motor de Sprites con Zoom**:
    *   **Zoom Bidireccional**: Capacidad de escalar sprites en tiempo real en los ejes X e Y.
    *   **Line Buffer**: Escaneo dinámico de líneas para gestionar hasta 32 sprites por línea de escaneo (configurable).
    *   **Acumulador de Zoom**: Implementación de una FSM especializada para el cálculo de píxeles fuente basándose en el factor de escala (acumulador de punto fijo).
- **Paleta de Colores**: Gestión de colores mediante RAM sincronizada con acceso compartido para la CPU.

### 3. Sistema de Sonido (`rtl/audio/`)
- **Chip ICS2115**: Wavetable Synthesizer de 32 canales. 
- **Sound Latches**: Comunicación mediante registros en `C00002` (68k -> Z80) y `C00004` (Z80 -> 68k) con soporte para NMIs.
- **Memoria de Audio**: RAM local de 64KB para el Z80 cargada dinámicamente.

### 4. Gestión de Memoria y Bus
- **Arbitro de SDRAM**: Un controlador centralizado en `PGM.sv` garantiza el acceso compartido a la memoria SDRAM externa con los siguientes canales de prioridad:
    1.  **CPU 68k**: Acceso a BIOS/PROM (`ARB_CPU`).
    2.  **Video**: Lectura de gráficos A-ROM/B-ROM (`ARB_VIDEO`).
    3.  **Audio**: Lectura de muestras S-ROM (`ARB_AUDIO`).
- **DPRAMs**: Uso extensivo de memorias de doble puerto (`dpram_dc.sv`) para buffers de video (VRAM) y RAM de trabajo (WRAM), permitiendo accesos simultáneos desde diferentes dominios de reloj.

### 5. I/O y Controles
- **Registro C08000**: Mapeo completo de Joysticks y 4 Botones (A, B, C, D) para Player 1 y 2.
- **Registro C08004**: Entradas de sistema (Coin, Start, Test).
- **Active Low**: Toda la lógica de entrada replica el comportamiento del hardware real (0 = Activo).

## 🚀 Despliegue y Pruebas

### Carga de ROMs
El core utiliza el framework `ioctl` de MiSTer para cargar los diferentes segmentos de la ROM:
- **Index 0**: Programa principal (P-ROM) y Gráficos (A-ROM/B-ROM).
- **Index 1**: Programa de sonido (M-ROM) cargado directamente en la RAM del Z80.

### Requisitos del MRA
Se requiere un archivo `.mra` compatible que organice las partes de la ROM según el mapa de memoria esperado por el core.

---
## 📜 Créditos y Desarrollo
- **Desarrollo Inicial**: Implementación de video y base del sistema.
- **Mejoras Recientes**: Controles, infraestructura de sonido y arbitraje de SDRAM.
- **Futuro**: Motor de audio ICS2115 completo y ARM7 HLE para títulos protegidos.
