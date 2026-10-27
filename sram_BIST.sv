
/*
 * SRAM Built-In Self-Test (BIST)
 * Seher Mian
 * October 8, 2026
 *
 * Description:
 *   Tests a 16-bit SRAM with an 18-bit address bus using two
 *   address-dependent XOR test patterns.
 *
 *   Test sequence:
 *     1. Write even addresses in ascending order.
 *     2. Read and verify even addresses in descending order.
 *     3. Write odd addresses in ascending order.
 *     4. Read and verify odd addresses in descending order.
 *     5. Wait for outstanding reads and signal completion.
 *
 *   Timing assumption:
 *     The expected-data pipeline below assumes a two-cycle
 *     SRAM read latency. Adjust the pipeline if the actual
 *     SRAM interface uses a different latency.
 */

`timescale 1ns/100ps

`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

module SRAM_BIST (
    input  logic        Clock,
    input  logic        Resetn,
    input  logic        BIST_start,

    output logic [17:0] BIST_address,
    output logic [15:0] BIST_write_data,
    output logic        BIST_we_n,
    input  logic [15:0] BIST_read_data,

    output logic        BIST_finish,
    output logic        BIST_mismatch
);

    // ---------------------------------------------------------
    // State machine
    // ---------------------------------------------------------

    typedef enum logic [2:0] {
        S_IDLE,
        S_WRITE_CYCLE,
        S_READ_CYCLE,
        S_DELAY_3,
        S_DELAY_4,
        S_WRITE_ODD,
        S_READ_ODD
    } bist_state_t;

    bist_state_t BIST_state;

    // ---------------------------------------------------------
    // Test patterns and read verification pipeline
    // ---------------------------------------------------------

    localparam logic [15:0] PATTERN_EVEN = 16'hA5A5;
    localparam logic [15:0] PATTERN_ODD  = 16'h5A5A;

    logic        BIST_start_buf;
    logic        read_cycle;

    logic [15:0] BIST_expected_data;
    logic [15:0] expected_data_d1;
    logic [15:0] expected_data_d2;

    logic valid_d1;
    logic valid_d2;

    // Detect a rising edge of BIST_start.
    wire BIST_start_edge = BIST_start & ~BIST_start_buf;

    // Both read states issue SRAM read requests.
    assign read_cycle = (BIST_state == S_READ_CYCLE) ||
                        (BIST_state == S_READ_ODD);

    // ---------------------------------------------------------
    // SRAM interface
    // ---------------------------------------------------------

    // Generate the write pattern based on the current address.
    // Only the lower 16 address bits are used to form the data.
    assign BIST_write_data =
        BIST_address[15:0] ^
        ((BIST_state == S_WRITE_ODD) ? PATTERN_ODD : PATTERN_EVEN);

    // Generate the expected data for the address being read.
    assign BIST_expected_data =
        BIST_address[15:0] ^
        ((BIST_state == S_READ_ODD) ? PATTERN_ODD : PATTERN_EVEN);

    // SRAM write enable is active low:
    //   0 = write
    //   1 = read or idle
    assign BIST_we_n = ~((BIST_state == S_WRITE_CYCLE) ||
                         (BIST_state == S_WRITE_ODD));

    // Sequential logic
 

    always_ff @(posedge Clock or negedge Resetn) begin
        if (!Resetn) begin

            // Reset the controller.
            BIST_state     <= S_IDLE;
            BIST_address   <= 18'd0;
            BIST_start_buf <= 1'b0;

            // Reset status outputs.
            BIST_finish   <= 1'b0;
            BIST_mismatch <= 1'b0;

            // Clear the read verification pipeline.
            expected_data_d1 <= 16'd0;
            expected_data_d2 <= 16'd0;

            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;

        end else begin

            // Store the previous start value for edge detection.
            BIST_start_buf <= BIST_start;

            // Read verification pipeline
         
            //
            // Capture the expected data for each read request.
            // Delay the expected value and its valid flag to
            // align with the two-cycle SRAM read response.
            //
            // Check pending reads independently of the current
            // FSM state so that final reads are not discarded
            // when the controller transitions to another state.

            valid_d1 <= read_cycle;
            valid_d2 <= valid_d1;

            if (read_cycle) begin
                expected_data_d1 <= BIST_expected_data;
            end else begin
                expected_data_d1 <= 16'd0;
            end

            expected_data_d2 <= expected_data_d1;

            // Latch any detected mismatch until reset or the
            // next BIST run.
            if (valid_d2 && (BIST_read_data != expected_data_d2)) begin
                BIST_mismatch <= 1'b1;
            end

            // BIST finite state machine
     

            case (BIST_state)

              
                // Idle: wait for a new start request.
          
                S_IDLE: begin
                    if (BIST_start_edge) begin
                        BIST_address <= 18'd0;

                        // Clear results from the previous run.
                        BIST_mismatch <= 1'b0;
                        BIST_finish   <= 1'b0;

                        // Clear any stale pipeline state.
                        expected_data_d1 <= 16'd0;
                        expected_data_d2 <= 16'd0;
                        valid_d1         <= 1'b0;
                        valid_d2         <= 1'b0;

                        BIST_state <= S_WRITE_CYCLE;
                    end
                end

                // ---------------------------------------------
                // Write all even addresses in ascending order.
                // Address sequence: 0, 2, 4, ..., 3FFFE.
                // ---------------------------------------------
                S_WRITE_CYCLE: begin
                    if (BIST_address == 18'h3FFFE) begin
                        // Begin reading the even addresses.
                        BIST_state   <= S_READ_CYCLE;
                        BIST_address <= 18'h3FFFE;
                    end else begin
                        BIST_address <= BIST_address + 18'd2;
                    end
                end

                // ---------------------------------------------
                // Read all even addresses in descending order.
                // Address sequence: 3FFFE, ..., 4, 2, 0.
                // ---------------------------------------------
                S_READ_CYCLE: begin
                    if (BIST_address == 18'h00000) begin
                        // Begin writing odd addresses.
                        BIST_state   <= S_WRITE_ODD;
                        BIST_address <= 18'h00001;
                    end else begin
                        BIST_address <= BIST_address - 18'd2;
                    end
                end

                // ---------------------------------------------
                // Write all odd addresses in ascending order.
                // Address sequence: 1, 3, 5, ..., 3FFFF.
                // ---------------------------------------------
                S_WRITE_ODD: begin
                    if (BIST_address == 18'h3FFFF) begin
                        // Begin reading the odd addresses.
                        BIST_state   <= S_READ_ODD;
                        BIST_address <= 18'h3FFFF;
                    end else begin
                        BIST_address <= BIST_address + 18'd2;
                    end
                end

                // ---------------------------------------------
                // Read all odd addresses in descending order.
                // Address sequence: 3FFFF, ..., 5, 3, 1.
                // ---------------------------------------------
                S_READ_ODD: begin
                    if (BIST_address == 18'h00001) begin
                        // Allow outstanding reads to complete.
                        BIST_state <= S_DELAY_3;
                    end else begin
                        BIST_address <= BIST_address - 18'd2;
                    end
                end

         
                // Drain the read verification pipeline
             
                S_DELAY_3: begin
                    BIST_state <= S_DELAY_4;
                end

                S_DELAY_4: begin
                    // Assert completion only after all pending
                    // read-valid flags have cleared.
                    if (!valid_d1 && !valid_d2) begin
                        BIST_finish <= 1'b1;
                        BIST_state  <= S_IDLE;
                    end
                end

                // Recover to idle if an invalid state occurs.
             
                default: begin
                    BIST_state <= S_IDLE;
                end

            endcase
        end
    end

endmodule

`ifndef DISABLE_DEFAULT_NET
`default_nettype wire
`endif
