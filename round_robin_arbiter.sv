// Fair arbiter for one router output.
//
// There is one copy of this module per output port. Its request vector has one
// bit for each input FIFO that wants this output. If several inputs request at
// once, the arbiter grants one input and remembers where the next search starts.
//
// Example with five requesters:
//   request = 5'b01010 means inputs 1 and 3 both want this output.
//   If the search starts at input 0, input 1 wins first.
//   After input 1 transfers, the next search starts at input 2, so input 3 can
//   win the next time both inputs are requesting.
//
// The arbiter also locks a grant if the output is not ready. This is necessary
// for ready/valid protocols: while valid=1 and ready=0, the selected flit must
// remain the same until it is accepted.
module round_robin_arbiter #(
    parameter int NUM_REQUESTERS = 5,
    parameter int INDEX_WIDTH = (NUM_REQUESTERS > 1) ? $clog2(NUM_REQUESTERS) : 1
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // One request bit from each input FIFO for this particular output.
    input  logic [NUM_REQUESTERS-1:0]    request,

    // ready is the downstream output's ready signal.
    input  logic                         ready,

    // One-hot grant is convenient for controlling the crossbar.
    output logic [NUM_REQUESTERS-1:0]    grant_onehot,
    output logic                         grant_valid,

    // Binary input number is useful for status/debug and arbitration state.
    output logic [INDEX_WIDTH-1:0]       grant_index
);

    // Search begins here after reset and moves past each successfully served
    // requester. It is state: unlike a combinational priority encoder, its
    // changing value makes the choice fair over time.
    logic [INDEX_WIDTH-1:0] next_start;

    // A stalled output holds its original input selection. The requester keeps
    // its FIFO head until ready, so that saved index continues to refer to the
    // same unconsumed flit.
    logic                   grant_locked;
    logic [INDEX_WIDTH-1:0] locked_index;

    always_comb begin : p_choose_grant
        integer offset;
        integer candidate;

        // Safe defaults represent "no requester selected".
        grant_onehot = '0;
        grant_valid = 1'b0;
        grant_index = '0;

        if (grant_locked) begin
            // Do not change the output's offered flit during backpressure.
            grant_index = locked_index;
            if (request[locked_index]) begin
                grant_onehot[locked_index] = 1'b1;
                grant_valid = 1'b1;
            end
        end else begin
            // Scan all requester positions, starting at next_start and
            // wrapping around. The first active request becomes the winner.
            for (offset = 0; offset < NUM_REQUESTERS; offset++) begin
                candidate = (next_start + offset) % NUM_REQUESTERS;

                if (!grant_valid && request[candidate]) begin
                    grant_onehot[candidate] = 1'b1;
                    grant_valid = 1'b1;
                    grant_index = candidate;
                end
            end
        end
    end

    // Update fairness and lock state only on a clock edge.
    always_ff @(posedge clk or negedge rst_n) begin : p_update_arbiter_state
        if (!rst_n) begin
            next_start <= '0;
            grant_locked <= 1'b0;
            locked_index <= '0;
        end else if (grant_valid && !ready) begin
            // The output is showing a flit, but its receiver has not taken it.
            // Save the winning input so a new request cannot replace that flit.
            grant_locked <= 1'b1;
            locked_index <= grant_index;
        end else if (grant_valid && ready) begin
            // A transfer happened (valid and ready). Let the requester after
            // this winner have first chance in the next arbitration.
            if (grant_index == NUM_REQUESTERS - 1)
                next_start <= '0;
            else
                next_start <= grant_index + 1'b1;

            grant_locked <= 1'b0;
        end
    end

    initial begin
        if (NUM_REQUESTERS < 1)
            $fatal(1, "NUM_REQUESTERS must be at least one");
    end

endmodule