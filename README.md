# AuroraMatrix FPGA Calculator

AuroraMatrix is an FPGA-based matrix calculator that ingests matrices over UART, stores them on-chip, performs common matrix operations in hardware, and streams results back over the same link. The design targets a 100 MHz Xilinx FPGA flow and includes a lightweight Python UART console for host-side interaction.

## Highlights
- Full pipeline: UART ingest → on-chip storage → operand selection → hardware math → UART display
- Supported ops: transpose, add, scalar multiply, matrix multiply, and convolution
- Up to 5×5 integer matrices (0–9), with per-dimension configurability in `src/defs.vh`
- Slot-based storage with overwrite-on-capacity semantics for repeatable demos
- Board I/O: switches select modes/ops, button confirms, LEDs/7-seg reflect state and countdowns
- Python `serial_ui.py` for an ergonomic send/receive console (115200 8N1 by default)

## Repository Layout
- [src/](src): RTL (top level, FSM, UART, matrix core, storage, display, debounce, defs)
- [tb/](tb): XSIM testbenches (system flow, controller FSM, matrix calculator)
- [constraints/](constraints): Board pinout (`board_constraints.xdc`)
- [matrix_calc.runs/](matrix_calc.runs): Vivado outputs (bitstream, reports, checkpoints)
- [serial_ui.py](serial_ui.py): Cross-platform Tkinter UART helper for interacting with the FPGA
- [update_project.tcl](update_project.tcl), [add_sources.tcl](add_sources.tcl): Vivado project maintenance scripts

## Build (Vivado GUI)
1) Open `matrix_calc.xpr` in Vivado (tested with 2020.x+). Ensure the board/part matches your target.
2) Run Synthesis → Implementation → Generate Bitstream. The generated file lands at `matrix_calc.runs/impl_1/matrix_calc_top_v2.bit`.
3) Program your board with that bitstream. The design expects a 100 MHz system clock and UART at 115200 8N1.

### Build via Tcl (optional)
If you prefer a non-project flow, from a Vivado Tcl shell:
```
cd <repo_root>
source update_project.tcl
```
Then launch synthesis/implementation and bitstream generation as needed.

## Operating the Hardware
- **Inputs**: 8 switches (`sw`) choose menu/operation; `btn_confirm` commits selections; UART RX receives matrix data.
- **Outputs**: UART TX streams prompts and results; LEDs reflect coarse FSM state/error; 7-seg shows op codes or countdowns.
- **Matrix input format (UART)**: send `m n` followed by `m*n` elements (row-major). Values outside 0–9 are flagged. Extra elements are ignored; missing elements are zero-filled.
- **Matrix generation**: choose generate mode, provide `m n count`; the hardware produces random matrices and stores them.
- **Operations**: after selecting an op, choose operand IDs as prompted over UART. Results are emitted over UART and can also be re-read from storage.

## Python UART Helper
The GUI in [serial_ui.py](serial_ui.py) simplifies sending commands and viewing results.

**Install & run** (Python 3.8+):
```
python -m pip install pyserial
python serial_ui.py
```
Select the COM port, keep baud at 115200, connect, then type payloads like `2 3 4 5 6 7 8 9` to feed a 2×3 matrix.

## Key RTL Blocks
- `matrix_calc_top_v2`: top-level integration of UART, FSM, storage, math core, display, and board I/O.
- `controller_fsm_v2`: orchestrates modes (menu/input/generate/display/compute), operand selection, and data muxing.
- `matrix_uart_input_v2` / `matrix_uart_output_v2`: stream matrices in/out with framing and basic validation.
- `matrix_storage_v2`: dimension-aware storage with query, dump, and summary reporting.
- `matrix_calc_unit`: arithmetic core supporting transpose/add/scalar-mul/mat-mul/convolution; emits result dimensions and optional conv cycles.
- `matrix_gen`: pseudo-random matrix generator for quick demos and stress runs.
- `seg_display_v2`, `debounce`, `defs.vh`: board display, button conditioning, and global parameters.

## Simulation
Use the testbenches under [tb/](tb) with XSIM or your preferred simulator. Example (XSIM):
```
xelab tb/tb_matrix_calc.v -s tb_matrix_calc_sim
xsim tb_matrix_calc_sim -runall
```

## Configuration Points
- Edit [src/defs.vh](src/defs.vh) to adjust max matrix size, data width, UART baud, debounce interval, or operation codes.
- Update [constraints/board_constraints.xdc](constraints/board_constraints.xdc) to match your board pinout.

## Naming & Packaging
- Suggested repository name: **aurora-matrix-fpga**
- Deliverables to ship: RTL under `src/`, constraints, `matrix_calc.xpr`, `update_project.tcl`, generated bitstream under `matrix_calc.runs/impl_1/`, and the Python UART helper.

## License
No license has been declared. Add one before publishing if you need open-source distribution.