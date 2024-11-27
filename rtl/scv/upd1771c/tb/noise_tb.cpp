// Verilated -*- C++ -*-
// DESCRIPTION: main() calling loop, created with Verilator --main

#include "verilated.h"
#include "Vnoise_tb.h"

//======================

int main(int argc, char** argv, char**) {
    // Setup context, defaults, and parse command line
    Verilated::debug(0);
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);

    // Construct the Verilated model, from Vtop.h generated from Verilating
    const std::unique_ptr<Vnoise_tb> topp{new Vnoise_tb{contextp.get()}};

    // Simulate until $finish
    while (!contextp->gotFinish()) {
        // Evaluate model
        topp->eval();
        // Advance time
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }

    if (!contextp->gotFinish()) {
        VL_DEBUG_IF(VL_PRINTF("+ Exiting without $finish; no events left\n"););
    }

    // Final model cleanup
    topp->final();
    return 0;
}

// Local Variables:
// compile-command: "verilator --cc --exe noise_tb.cpp --build -j 4 --timing --assert --trace-fst --trace-threads 1 --top-module noise_tb --relative-includes -DUPD1771C_ROM_INIT_FROM_HEX ../upd1771c.sv noise_tb.sv"
// End:
