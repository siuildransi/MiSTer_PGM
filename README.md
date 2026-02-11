# MiSTer PGM Core Development

Este repositorio contiene el desarrollo del núcleo PGM (PolyGame Master) para MiSTer FPGA.

## 🚀 Estado Actual del Proyecto

El desarrollo se encuentra en una fase activa, con los componentes principales de video, control e infraestructura de sonido ya implementados.

### 📺 Motor de Video (`pgm_video.sv`)
- **Capas de Fondo y Texto**: Implementación completa de la renderización de planos.
- **Sprites con Zoom por Hardware**: Motor de sprites avanzado que soporta zoom en X e Y, utilizando FSMs optimizadas para el ahorro de recursos en la FPGA.
- **Gestión de Memoria**: Uso eficiente de `dpram_dc` y arbitraje de SDRAM para el acceso a las ROMs de gráficos (A-ROM y B-ROM).

### 🕹️ Controles de Entrada (`PGM.sv`)
- **Mapeo de Jugadores (Registro `C08000`)**: Soporte para Player 1 y Player 2 con 4 botones por jugador (A, B, C, D) y joystick de 4 direcciones.
- **Sistema y Monedas (Registro `C08004`)**: Mapeo completo de las señales de Coin y Start del framework MiSTer.
- **Lógica Active Low**: Fiel al hardware original para asegurar compatibilidad total con el código del juego.

### 🔊 Infraestructura de Sonido (En Progreso)
- **CPU Z80**: Configuración de la CPU de sonido con 64KB de RAM local.
- **Sound Latches**: Implementación de la comunicación bidireccional entre la CPU 68000 y el Z80 a través de los latches `C00002` (comandos) y `C00004` (estado).
- **Chip ICS2115**: Integración inicial del sintetizador de tabla de ondas con acceso dedicado a la SDRAM para la lectura de muestras de audio (S-ROM).
- **Arbitraje SDRAM**: Añadido el canal `ARB_AUDIO` con prioridad equilibrada para evitar cortes en el sonido o parpadeos en el video.

## 🛠️ Desarrollo y Compilación

### CI/CD con GitHub Actions
El proyecto utiliza un pipeline automatizado para compilar el core en cada "push". Los resultados (archivos `.rbf`) se pueden encontrar en la pestaña de **Actions** del repositorio.

### Cómo Contribuir
Actualmente el trabajo se está realizando en la rama: `dev-macbook-pgm-core`.

## 📜 Próximos Pasos
1.  **Motor de Audio**: Finalizar la FSM del ICS2115 para la mezcla de múltiples voces.
2.  **Protección ARM7 (HLE)**: Implementar la emulación de alto nivel (High-Level Emulation) de los algoritmos de protección ASIC mediante máquinas de estados en Verilog, basándose en la documentación de MAME.

---
*Desarrollado para la comunidad MiSTer FPGA.*
